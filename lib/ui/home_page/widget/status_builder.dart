import 'package:bluetooth_chat_app/services/bluetooth_turn_on_service.dart';
import 'package:bluetooth_chat_app/services/mesh_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Live Bluetooth + mesh metrics panel.
///
/// Uses a single [ListView] so it fills the entire tab and avoids layout
/// issues when swiping between panels.
Widget buildStatusList() {
  final mesh = MeshService.instance;
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Bluetooth & Mesh Status',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 12),
      StreamBuilder<BluetoothAdapterState>(
        stream: BluetoothController.stateStream,
        builder: (context, snapshot) {
          final state = snapshot.data;
          String label = 'Unknown';
          Color color = Colors.grey;
          if (state == BluetoothAdapterState.on) {
            label = 'On';
            color = Colors.greenAccent;
          } else if (state == BluetoothAdapterState.off) {
            label = 'Off';
            color = Colors.redAccent;
          } else if (state == BluetoothAdapterState.turningOn ||
              state == BluetoothAdapterState.turningOff) {
            label = 'Changing';
            color = Colors.orangeAccent;
          }
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: color,
              child: const Icon(Icons.bluetooth, color: Colors.black),
            ),
            title: const Text(
              'Bluetooth Adapter',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              label,
              style: TextStyle(color: Colors.grey.shade300),
            ),
          );
        },
      ),
      const Divider(color: Colors.white10),
      ValueListenableBuilder<MeshStats>(
        valueListenable: mesh.stats,
        builder: (context, stats, _) {
          final avgSeconds =
              stats.avgDeliveryMillis > 0 ? stats.avgDeliveryMillis / 1000 : 0;
          final nextCleanupStr = stats.nextCleanupTime != null
              ? _formatTime(stats.nextCleanupTime!)
              : 'Scheduled ~every 10 minutes';
          return Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF2A2A2A),
                  child: Icon(Icons.devices, color: Colors.lightBlueAccent),
                ),
                title: const Text(
                  'Connected Peers (this session)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${stats.currentConnectedDevices} device(s) currently connected.',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF2A2A2A),
                  child: Icon(Icons.send, color: Colors.greenAccent),
                ),
                title: const Text(
                  'Messages',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Sent: ${stats.totalMessagesSent}  |  '
                  'Seen on network: ${stats.totalMessagesReceived}\n'
                  'Delivered to this device: ${stats.totalMessagesDeliveredToMe}',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF2A2A2A),
                  child: Icon(Icons.timer, color: Colors.orangeAccent),
                ),
                title: const Text(
                  'Delivery Time',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  stats.successfulDeliveries == 0
                      ? 'No deliveries recorded yet.'
                      : 'Average delivery: ${avgSeconds.toStringAsFixed(1)}s\n'
                        'Based on ${stats.successfulDeliveries} delivered message(s).',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF2A2A2A),
                  child: Icon(Icons.cleaning_services,
                      color: Colors.lightGreenAccent),
                ),
                title: const Text(
                  'Cleanup',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Last removed: ${stats.lastCleanupRemovedCount} relay message(s).\n'
                  'Next cleanup around: $nextCleanupStr',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ],
  );
}

String _formatTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final min = time.minute.toString().padLeft(2, '0');
  final ampm = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$min $ampm';
}