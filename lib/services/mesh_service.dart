import 'dart:async';
import 'dart:convert';

import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/data/data_base/db_crypto.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class MeshStats {
  final int totalMessagesSent;
  final int totalMessagesReceived;
  final int totalMessagesDeliveredToMe;
  final int successfulDeliveries;
  final double avgDeliveryMillis;
  final int currentConnectedDevices;
  final DateTime? lastSendTime;
  final DateTime? lastReceiveTime;
  final DateTime? lastCleanupTime;
  final DateTime? nextCleanupTime;
  final int lastCleanupRemovedCount;

  const MeshStats({
    required this.totalMessagesSent,
    required this.totalMessagesReceived,
    required this.totalMessagesDeliveredToMe,
    required this.successfulDeliveries,
    required this.avgDeliveryMillis,
    required this.currentConnectedDevices,
    required this.lastSendTime,
    required this.lastReceiveTime,
    required this.lastCleanupTime,
    required this.nextCleanupTime,
    required this.lastCleanupRemovedCount,
  });

  factory MeshStats.initial() => const MeshStats(
        totalMessagesSent: 0,
        totalMessagesReceived: 0,
        totalMessagesDeliveredToMe: 0,
        successfulDeliveries: 0,
        avgDeliveryMillis: 0,
        currentConnectedDevices: 0,
        lastSendTime: null,
        lastReceiveTime: null,
        lastCleanupTime: null,
        nextCleanupTime: null,
        lastCleanupRemovedCount: 0,
      );

  MeshStats copyWith({
    int? totalMessagesSent,
    int? totalMessagesReceived,
    int? totalMessagesDeliveredToMe,
    int? successfulDeliveries,
    double? avgDeliveryMillis,
    int? currentConnectedDevices,
    DateTime? lastSendTime,
    DateTime? lastReceiveTime,
    DateTime? lastCleanupTime,
    DateTime? nextCleanupTime,
    int? lastCleanupRemovedCount,
  }) =>
      MeshStats(
        totalMessagesSent: totalMessagesSent ?? this.totalMessagesSent,
        totalMessagesReceived: totalMessagesReceived ?? this.totalMessagesReceived,
        totalMessagesDeliveredToMe:
            totalMessagesDeliveredToMe ?? this.totalMessagesDeliveredToMe,
        successfulDeliveries: successfulDeliveries ?? this.successfulDeliveries,
        avgDeliveryMillis: avgDeliveryMillis ?? this.avgDeliveryMillis,
        currentConnectedDevices:
            currentConnectedDevices ?? this.currentConnectedDevices,
        lastSendTime: lastSendTime ?? this.lastSendTime,
        lastReceiveTime: lastReceiveTime ?? this.lastReceiveTime,
        lastCleanupTime: lastCleanupTime ?? this.lastCleanupTime,
        nextCleanupTime: nextCleanupTime ?? this.nextCleanupTime,
        lastCleanupRemovedCount:
            lastCleanupRemovedCount ?? this.lastCleanupRemovedCount,
      );
}

class MeshService {
  MeshService._();
  static final MeshService instance = MeshService._();

  static const String _serviceUuid = '0000feed-0000-1000-8000-00805f9b34fb';
  static const String _characteristicUuid = '0000beef-0000-1000-8000-00805f9b34fb';

  bool _running = false;
  Timer? _scanTimer;
  Timer? _cleanupTimer;
  StreamSubscription<List<ScanResult>>? _scanSub;

  final ValueNotifier<MeshStats> stats = ValueNotifier(MeshStats.initial());
  final Set<String> _connectedDeviceIds = <String>{};

  String? _myIdCache;
  Future<String> _getMyId() async {
    _myIdCache ??= await AppIdentifier.getId();
    return _myIdCache!;
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;

    final myId = await _getMyId();
    LogService.log('Mesh', 'Starting mesh service for user $myId');

    await Future.delayed(const Duration(seconds: 1));

    _scanTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _runScanBurst();
    });
    unawaited(_runScanBurst());

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
    } catch (_) {}
  }

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
    if (name.isEmpty) return;

    LogService.log('Mesh', 'Found device ${device.remoteId} ($name)');

    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 8));
      _connectedDeviceIds.add(device.remoteId.str);
      stats.value = stats.value.copyWith(currentConnectedDevices: _connectedDeviceIds.length);
    } catch (_) {}

    try {
      final services = await device.discoverServices();
      final meshService = services.firstWhere(
        (s) => s.serviceUuid.str128 == _serviceUuid,
        orElse: () => services.isNotEmpty ? services.first : services.first,
      );

      if (meshService.characteristics.isEmpty ||
          meshService.serviceUuid.str128 != _serviceUuid) {
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
      } catch (_) {}
      _connectedDeviceIds.remove(device.remoteId.str);
      stats.value = stats.value.copyWith(currentConnectedDevices: _connectedDeviceIds.length);
    }
  }

  Future<void> _forwardPendingMessagesToPeer(BluetoothCharacteristic characteristic) async {
    final db = DBHelper();
    final pending = await db.getPendingNonUserMsgs();
    if (pending.isEmpty) return;

    final toSend =
        pending.where((m) => (m['hops'] as int? ?? 0) > 0).toList(growable: false);
    if (toSend.isEmpty) return;

    final batch = {'type': 'mesh_batch', 'messages': toSend};
    final jsonStr = jsonEncode(batch);
    final bytes = utf8.encode(jsonStr);

    try {
      await characteristic.write(bytes, withoutResponse: true);
      final now = DateTime.now();
      final current = stats.value;
      stats.value = current.copyWith(
        totalMessagesSent: current.totalMessagesSent + toSend.length,
        lastSendTime: now,
      );
      LogService.log('Mesh', 'Forwarded ${toSend.length} messages to peer');
    } catch (e) {
      LogService.log('Mesh', 'Error writing to characteristic: $e');
    }
  }

  Future<void> _receiveFromPeer(BluetoothCharacteristic characteristic) async {
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
      if (await db.isMsgInHash(msgId)) continue;

      await db.insertHashMsg(msgId);

      final receiver = raw['receiverUserCode'] as String?;
      final sender = raw['senderUserCode'] as String?;
      final hops = (raw['hops'] as int?) ?? 0;

      final now = DateTime.now();
      final current = stats.value;

      stats.value = current.copyWith(
        totalMessagesReceived: current.totalMessagesReceived + 1,
        lastReceiveTime: now,
      );

      if (receiver == myUserCode && sender != null) {
        await db.insertChatMsg(sender, {
          'msgId': msgId,
          'msg': raw['msg'],
          'sendDate': raw['sendDate'],
          'receiveDate': now.toIso8601String(),
          'isReceived': 1,
        }, encrypt: false);

        await db.insertNonUserMsg({
          ...raw,
          'receiveDate': now.toIso8601String(),
          'isReceived': 1,
        });

        final sendDateStr = raw['sendDate'] as String?;
        if (sendDateStr != null) {
          final sendTime = DateTime.tryParse(sendDateStr);
          if (sendTime != null) {
            final latency = now.difference(sendTime).inMilliseconds.toDouble();
            final prevCount = current.successfulDeliveries;
            final newCount = prevCount + 1;
            final newAvg = ((current.avgDeliveryMillis * prevCount) + latency) / newCount;
            stats.value = stats.value.copyWith(
              totalMessagesDeliveredToMe: current.totalMessagesDeliveredToMe + 1,
              successfulDeliveries: newCount,
              avgDeliveryMillis: newAvg,
            );
          }
        }
      } else if (hops > 0) {
        await db.insertNonUserMsg({
          ...raw,
          'hops': hops - 1,
          'receiveDate': now.toIso8601String(),
          'isReceived': 0,
        });
      }
    }
  }

  Future<void> _runCleanup() async {
    final db = DBHelper();
    try {
      final removed = await db.removeOldNonUserMsgs(olderThanDays: 3);
      final now = DateTime.now();
      final next = now.add(const Duration(minutes: 10));
      final current = stats.value;
      stats.value = current.copyWith(
        lastCleanupTime: now,
        nextCleanupTime: next,
        lastCleanupRemovedCount: removed,
      );
      LogService.log('Mesh', 'Cleanup removed $removed old relay messages');
    } catch (e) {
      LogService.log('Mesh', 'Cleanup error: $e');
    }
  }

  Future<void> sendNewMessage({
    required String myUserCode,
    required String targetUserCode,
    required String plainText,
  }) async {
    final db = DBHelper();
    final msgId = generateMsgId(myUserCode);

    await db.insertChatMsg(targetUserCode, {
      'msgId': msgId,
      'msg': plainText,
      'sendDate': DateTime.now().toIso8601String(),
      'receiveDate': null,
      'isReceived': 0,
    }, encrypt: false);

    final encryptedForReceiver = CryptoHelper.encryptMsg(plainText, targetUserCode);
    await db.insertNonUserMsg({
      'msgId': msgId,
      'msg': encryptedForReceiver,
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
