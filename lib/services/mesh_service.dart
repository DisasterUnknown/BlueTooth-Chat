import 'dart:async';
import 'dart:convert';

import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Simple Bluetooth mesh-style service built on top of flutter_blue_plus.
///
/// Goals:
/// - Work completely offline (no internet required).
/// - Use scan bursts instead of constant scanning to save battery.
/// - Forward only pending, non-duplicate messages with limited hops.
///
/// NOTE:
/// This uses a custom service/characteristic UUID. All devices running this
/// app will expose the same service and characteristic, so they can discover
/// and exchange batched messages with each other.
class MeshService {
  MeshService._();
  static final MeshService instance = MeshService._();

  static const String _serviceUuid =
      '0000feed-0000-1000-8000-00805f9b34fb'; // arbitrary but fixed
  static const String _characteristicUuid =
      '0000beef-0000-1000-8000-00805f9b34fb';

  bool _running = false;
  Timer? _scanTimer;
  Timer? _cleanupTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;

  // Cache my ID so we don't recompute for every operation.
  String? _myIdCache;

  Future<String> _getMyId() async {
    _myIdCache ??= await AppIdentifier.getId();
    return _myIdCache!;
  }

  /// Start periodic scan bursts and cleanup.
  Future<void> start() async {
    if (_running) return;
    _running = true;

    final myId = await _getMyId();
    LogService.log('Mesh', 'Starting mesh service for user $myId');

    // Short delay so that Bluetooth + permissions are definitely settled.
    await Future.delayed(const Duration(seconds: 1));

    // Scan every 2 minutes in ~8-second bursts.
    _scanTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _runScanBurst();
    });
    // Also do an initial burst immediately.
    unawaited(_runScanBurst());

    // Lightweight cleanup every 10 minutes.
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _runCleanup();
    });
  }

  Future<void> stop() async {
    _running = false;
    _scanTimer?.cancel();
    _cleanupTimer?.cancel();
    await _scanSub?.cancel();
    _scanSub = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // ignore
    }
  }

  /// One scan burst: low-power scan for nearby peers exposing our service.
  Future<void> _runScanBurst() async {
    if (!_running) return;

    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        LogService.log('Mesh', 'Bluetooth not supported on this device');
        return;
      }
    } catch (e) {
      LogService.log('Mesh', 'Error checking BT support: $e');
      return;
    }

    LogService.log('Mesh', 'Starting scan burst');

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        androidScanMode: AndroidScanMode.lowPower,
      );

      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          _handleScanResult(result);
        }
      });
    } catch (e) {
      LogService.log('Mesh', 'Error starting scan: $e');
      return;
    }

    // Stop after the window.
    Future.delayed(const Duration(seconds: 9), () async {
      try {
        await FlutterBluePlus.stopScan();
        LogService.log('Mesh', 'Stopped scan burst');
      } catch (e) {
        LogService.log('Mesh', 'Error stopping scan: $e');
      }
    });
  }

  Future<void> _handleScanResult(ScanResult result) async {
    if (!_running) return;

    final device = result.device;
    final name = device.platformName;

    // Optional filter: skip devices that clearly are not ours.
    if (name.isEmpty) return;

    LogService.log('Mesh', 'Found device ${device.remoteId} ($name)');

    // Try connecting once, then immediately exchanging messages.
    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 8));
    } catch (_) {
      // Already connected or failed – best effort.
    }

    try {
      final services = await device.discoverServices();
      final meshService = services.firstWhere(
        (s) => s.serviceUuid.str128 == _serviceUuid,
        orElse: () => services.isNotEmpty ? services.first : services.first,
      );

      if (meshService.characteristics.isEmpty ||
          meshService.serviceUuid.str128 != _serviceUuid) {
        // Peer is not running this app / protocol.
        await device.disconnect();
        return;
      }

      final characteristic = meshService.characteristics.firstWhere(
        (c) => c.characteristicUuid.str128 == _characteristicUuid,
        orElse: () => meshService.characteristics.first,
      );

      await _forwardPendingMessagesToPeer(characteristic);
      await _receiveFromPeer(characteristic);
    } catch (e) {
      LogService.log('Mesh', 'Error during service discovery: $e');
    } finally {
      try {
        await device.disconnect();
      } catch (_) {
        // ignore
      }
    }
  }

  /// Serialize and send all pending messages to a connected peer.
  Future<void> _forwardPendingMessagesToPeer(
    BluetoothCharacteristic characteristic,
  ) async {
    final db = DBHelper();
    final pending = await db.getPendingNonUserMsgs();

    if (pending.isEmpty) return;

    final toSend =
        pending.where((m) => (m['hops'] as int? ?? 0) > 0).toList(growable: false);
    if (toSend.isEmpty) return;

    final batch = {
      'type': 'mesh_batch',
      'messages': toSend,
    };
    final jsonStr = jsonEncode(batch);
    final bytes = utf8.encode(jsonStr);

    // BLE packets are limited; for simplicity, send as a single write and let
    // plugin fragment if needed. For large loads, you could chunk here.
    try {
      await characteristic.write(
        bytes,
        withoutResponse: true,
      );
      LogService.log('Mesh', 'Forwarded ${toSend.length} messages to peer');
    } catch (e) {
      LogService.log('Mesh', 'Error writing to characteristic: $e');
    }
  }

  /// Read messages from the peer (single read best-effort).
  Future<void> _receiveFromPeer(
    BluetoothCharacteristic characteristic,
  ) async {
    try {
      final data = await characteristic.read();
      if (data.isEmpty) return;

      final payload = utf8.decode(data);
      final myId = await _getMyId();
      await handleIncomingBatch(payload, myId);
    } catch (e) {
      LogService.log('Mesh', 'Error reading from characteristic: $e');
    }
  }

  /// Process a batch payload received from a peer.
  Future<void> handleIncomingBatch(String payload, String myUserCode) async {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(payload) as Map<String, dynamic>;
    } catch (e) {
      LogService.log('Mesh', 'Invalid batch JSON: $e');
      return;
    }

    if (decoded['type'] != 'mesh_batch') return;

    final List msgs = decoded['messages'] as List? ?? <dynamic>[];
    if (msgs.isEmpty) return;

    final db = DBHelper();

    for (final raw in msgs) {
      if (raw is! Map<String, dynamic>) continue;
      final msgId = raw['msgId'] as String?;
      if (msgId == null) continue;

      if (await db.isMsgInHash(msgId)) {
        continue;
      }

      await db.insertHashMsg(msgId);

      final receiver = raw['receiverUserCode'] as String?;
      final sender = raw['senderUserCode'] as String?;
      final hops = (raw['hops'] as int?) ?? 0;

      if (receiver == myUserCode && sender != null) {
        // Store in my chat table; decryption will be attempted when reading.
        await db.insertChatMsg(
          sender,
          {
            'msgId': msgId,
            'msg': raw['msg'],
            'sendDate': raw['sendDate'],
            'receiveDate': DateTime.now().toIso8601String(),
            'isReceived': 1,
          },
          encrypt: false,
        );

        await db.insertNonUserMsg({
          ...raw,
          'receiveDate': DateTime.now().toIso8601String(),
          'isReceived': 1,
        });
      } else if (hops > 0) {
        await db.insertNonUserMsg({
          ...raw,
          'hops': hops - 1,
          'receiveDate': DateTime.now().toIso8601String(),
          'isReceived': 0,
        });
      }
    }
  }

  Future<void> _runCleanup() async {
    final db = DBHelper();
    try {
      final removed = await db.removeOldNonUserMsgs(olderThanDays: 3);
      LogService.log('Mesh', 'Cleanup removed $removed old relay messages');
    } catch (e) {
      LogService.log('Mesh', 'Cleanup error: $e');
    }
  }

  /// High-level API used by the chat screen when the local user sends a message.
  Future<void> sendNewMessage({
    required String myUserCode,
    required String targetUserCode,
    required String plainText,
  }) async {
    final db = DBHelper();
    final msgId = generateMsgId(myUserCode);

    await db.insertChatMsg(
      targetUserCode,
      {
        'msgId': msgId,
        'msg': plainText,
        'sendDate': DateTime.now().toIso8601String(),
        'receiveDate': null,
        'isReceived': 0,
      },
      encrypt: true,
      receiverUserCode: targetUserCode,
    );

    await db.insertNonUserMsg({
      'msgId': msgId,
      'msg': plainText,
      'sendDate': DateTime.now().toIso8601String(),
      'receiveDate': null,
      'senderUserCode': myUserCode,
      'receiverUserCode': targetUserCode,
      'isReceived': 0,
      'hops': 4,
    });

    await db.insertHashMsg(msgId);
  }
}


