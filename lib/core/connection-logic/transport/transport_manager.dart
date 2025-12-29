import 'dart:async';
import 'gossip_transport.dart';
import 'nearby_transport.dart';
import '../gossip/gossip_message.dart';
import '../gossip/peer.dart';
import '../../../services/bluetooth_turn_on_service.dart';
import '../../../core/enums/logs_enums.dart';
import '../../../services/log_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class TransportManager {
  static final TransportManager _instance = TransportManager._internal();
  factory TransportManager() => _instance;

  late final NearbyTransport _transport;
  bool _isInitialized = false;
  StreamSubscription<BluetoothAdapterState>? _bluetoothStateSubscription;

  final _messageController = StreamController<ReceivedMessage>.broadcast();
  final _peerController = StreamController<Peer>.broadcast();
  final _peerDisconnectedController = StreamController<Peer>.broadcast();
  final _peerListController = StreamController<List<Peer>>.broadcast();
  final Map<String, Peer> _activePeers = {};

  TransportManager._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;

    _transport = NearbyTransport();
    await _transport.initialize();

    // Listen to transport events
    _transport.onMessageReceived.listen(_messageController.add);

    _transport.onPeerDiscovered.listen((peer) {
      _peerController.add(peer);
      _activePeers[peer.id] = peer;
      _emitPeerSnapshot();
    });

    _transport.onPeerDisconnected.listen((peer) {
      _activePeers.remove(peer.id);
      _peerDisconnectedController.add(peer);
      _emitPeerSnapshot();
    });

    _emitPeerSnapshot();
    _isInitialized = true;

    // Monitor Bluetooth state and auto-reconnect
    _setupBluetoothReconnection();
  }

  /// Monitor Bluetooth state and automatically restart when Bluetooth is turned back on
  void _setupBluetoothReconnection() {
    _bluetoothStateSubscription = BluetoothController.stateStream.listen((state) async {
      if (!_isInitialized) return;
      
      if (state == BluetoothAdapterState.on) {
        LogService.log(
          LogTypes.nearbyTransport,
          'Bluetooth turned on - Restarting NearbyTransport to reconnect to mesh network',
        );
        try {
          // Restart the transport
          await _transport.restart();
          LogService.log(
            LogTypes.nearbyTransport,
            'NearbyTransport restarted successfully - Device is back online in mesh network',
          );
        } catch (e, stack) {
          LogService.log(
            LogTypes.nearbyTransport,
            'Failed to restart NearbyTransport after Bluetooth turned on: $e, $stack',
          );
        }
      } else if (state == BluetoothAdapterState.off) {
        LogService.log(
          LogTypes.nearbyTransport,
          'Bluetooth turned off - Mesh network disconnected, will reconnect automatically when Bluetooth is enabled',
        );
      }
    });
  }

  void _emitPeerSnapshot() {
    _peerListController.add(_activePeers.values.toList(growable: false));
  }

  Stream<ReceivedMessage> get onMessageReceived => _messageController.stream;
  Stream<Peer> get onPeerDiscovered => _peerController.stream;
  Stream<Peer> get onPeerDisconnected => _peerDisconnectedController.stream;
  Stream<List<Peer>> get connectedPeersStream => _peerListController.stream;
  List<Peer> get connectedPeers => _activePeers.values.toList(growable: false);

  Future<void> sendMessage(Peer peer, GossipMessage message) async {
    if (!_isInitialized) throw Exception('TransportManager not initialized');
    await _transport.sendMessage(peer, message);
  }

  Future<void> disconnect() async {
    if (!_isInitialized) return;
    _bluetoothStateSubscription?.cancel();
    await _transport.disconnect();
    _activePeers.clear();
    _emitPeerSnapshot();
    _isInitialized = false;
  }

  Future<bool> hasInternet() async {
    if (!_isInitialized) return false;
    return await _transport.hasInternet();
  }
}
