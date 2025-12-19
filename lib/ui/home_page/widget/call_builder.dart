import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:flutter/material.dart';

Future<Map<String, dynamic>> _loadDbStatsWithId() async {
  final db = DBHelper();
  final myId = await AppIdentifier.getId();
  final users = await db.getAllUsers();
  final totalRelay = await db.countNonUserMsgs();
  final pendingRelay = await db.countPendingNonUserMsgs();
  final hashes = await db.countHashMsgs();
  return {
    'myId': myId,
    'users': users.length,
    'relayTotal': totalRelay,
    'relayPending': pendingRelay,
    'hashes': hashes,
  };
}

/// DB + security overview panel with live counts from the local database.
///
/// Uses a single [ListView] so it fills the entire tab without layout issues.
Widget buildCallList() {
  return FutureBuilder<Map<String, dynamic>>(
    future: _loadDbStatsWithId(),
    builder: (context, snapshot) {
      final data = snapshot.data ??
          const {
            'myId': null,
            'users': 0,
            'relayTotal': 0,
            'relayPending': 0,
            'hashes': 0,
          };
      final myId = data['myId'] as String?;
      final userCount = data['users'] as int? ?? 0;
      final relayTotal = data['relayTotal'] as int? ?? 0;
      final relayPending = data['relayPending'] as int? ?? 0;
      final hashes = data['hashes'] as int? ?? 0;

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Data & Security Overview',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (myId != null) ...[
            const SizedBox(height: 8),
            Text(
              'Your ID: $myId',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF2A2A2A),
              child: Icon(Icons.people, color: Colors.lightBlueAccent),
            ),
            title: const Text(
              'Known Users Stored Locally',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              '$userCount user(s) saved with ID + display name.',
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
              child: Icon(Icons.sync_alt, color: Colors.orangeAccent),
            ),
            title: const Text(
              'Relay Queue (nonUserMsgs)',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Total relay records: $relayTotal\n'
              'Pending forwards: $relayPending',
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
              child: Icon(Icons.verified, color: Colors.lightGreen),
            ),
            title: const Text(
              'Hash-based Deduplication (hashMsgs)',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              '$hashes unique message ID(s) seen so far.\n'
              'Prevents the same encrypted message from\n'
              'being processed or forwarded twice.',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF2A2A2A),
              child: Icon(Icons.lock, color: Colors.greenAccent),
            ),
            title: const Text(
              'Message Encryption',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Messages are encrypted per receiver using a key\n'
              'derived from their user ID before being stored or\n'
              'forwarded through the mesh.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF2A2A2A),
              child: Icon(Icons.storage_rounded, color: Colors.purple),
            ),
            title: const Text(
              'Local-only Storage',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'All chats and routing metadata live inside a local\n'
              'SQLite database on this device. No cloud or\n'
              'internet connection is used.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    },
  );
}