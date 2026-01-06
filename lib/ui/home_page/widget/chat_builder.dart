import 'dart:async';
import 'package:bluetooth_chat_app/services/routing_service.dart';
import 'package:bluetooth_chat_app/ui/chat_page/chat_page.dart';
import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/data/data_base/db_crypto.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:flutter/material.dart';

Widget buildChatList({VoidCallback? onContactsChanged}) {
  return FutureBuilder<String>(
    future: AppIdentifier.getId(),
    builder: (context, myIdSnapshot) {
      if (!myIdSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final myId = myIdSnapshot.data!;
      final db = DBHelper();
      
      // Use StreamBuilder with periodic refresh to make it reactive
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: Stream.periodic(const Duration(seconds: 2), (_) async {
          final users = await db.getAllUsers();
          // Get latest message and unread count for each user
          final usersWithData = await Future.wait(users.map((user) async {
            final userCode = user['userCode'] as String? ?? '';
            final latestMsg = await db.getLatestMessage(userCode);
            final unreadCount = await db.getUnreadCount(userCode);
            
            // Decrypt latest message if it exists
            String? latestMsgText;
            DateTime? latestMsgTime;
            if (latestMsg != null) {
              final isReceived = latestMsg['isReceived'] as int? ?? 0;
              if (isReceived == 1) {
                try {
                  final msgValue = latestMsg['msg'];
                  if (msgValue is String) {
                    final decrypted = CryptoHelper.decryptMsg(msgValue, myId);
                    if (decrypted != null) {
                      latestMsgText = decrypted;
                    }
                  }
                } catch (_) {
                  latestMsgText = 'Encrypted message';
                }
              } else {
                latestMsgText = CryptoHelper.decryptMsg(latestMsg['msg'], userCode);
              }
              final sendDateStr = latestMsg['sendDate'] as String?;
              if (sendDateStr != null) {
                latestMsgTime = DateTime.tryParse(sendDateStr);
              }
            }
            
            return {
              ...user,
              'latestMsg': latestMsgText,
              'latestMsgTime': latestMsgTime,
              'unreadCount': unreadCount,
            };
          }));
          return usersWithData;
        }).asyncMap((future) => future),
        initialData: const [],
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return const Center(
              child: Text(
                'No users yet. Tap + to add one.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          final users = snapshot.data!;
          
          // Sort by latest message time (most recent first)
          users.sort((a, b) {
            final timeA = a['latestMsgTime'] as DateTime?;
            final timeB = b['latestMsgTime'] as DateTime?;
            if (timeA == null && timeB == null) return 0;
            if (timeA == null) return 1;
            if (timeB == null) return -1;
            return timeB.compareTo(timeA);
          });
          
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final name = (user['name'] as String?) ?? 'Unknown';
              final userCode = user['userCode'] as String? ?? '';
              final latestMsg = user['latestMsg'] as String?;
              final latestMsgTime = user['latestMsgTime'] as DateTime?;
              final unreadCount = user['unreadCount'] as int? ?? 0;
              final hasUnread = unreadCount > 0;
              
              // Format time
              String timeStr = '';
              if (latestMsgTime != null) {
                final now = DateTime.now();
                final diff = now.difference(latestMsgTime);
                if (diff.inDays == 0) {
                  final hour = latestMsgTime.hour % 12 == 0 ? 12 : latestMsgTime.hour % 12;
                  final min = latestMsgTime.minute.toString().padLeft(2, '0');
                  final ampm = latestMsgTime.hour >= 12 ? 'PM' : 'AM';
                  timeStr = '$hour:$min $ampm';
                } else if (diff.inDays == 1) {
                  timeStr = 'Yesterday';
                } else if (diff.inDays < 7) {
                  timeStr = '${diff.inDays}d ago';
                } else {
                  timeStr = '${latestMsgTime.month}/${latestMsgTime.day}';
                }
              }
              
              return ListTile(
                tileColor: hasUnread ? Colors.greenAccent.withValues(alpha: 0.1) : null,
                leading: Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: hasUnread 
                          ? Colors.greenAccent.shade400 
                          : Colors.greenAccent.shade400.withValues(alpha: 0.7),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.black),
                      ),
                    ),
                    if (hasUnread)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (timeStr.isNotEmpty)
                      Text(
                        timeStr,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (latestMsg != null)
                      Text(
                        latestMsg.length > 40 ? '${latestMsg.substring(0, 40)}...' : latestMsg,
                        style: TextStyle(
                          color: hasUnread ? Colors.greenAccent.shade200 : Colors.grey.shade400,
                          fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        userCode,
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                  ],
                ),
                onTap: () {
                  RoutingService().navigateWithSlide(
                    begin: Offset(0.0, 1.0),
                    ChatPage(userName: name, userId: userCode),
                  );
                  // Refresh to update unread counts
                  onContactsChanged?.call();
                },
                onLongPress: () {
                  _showContactActions(
                    context: context,
                    name: name,
                    userCode: userCode,
                    onChanged: onContactsChanged,
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

void _showContactActions({
  required BuildContext context,
  required String name,
  required String userCode,
  VoidCallback? onChanged,
}) {
  final db = DBHelper();

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1F1F1F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white70),
              title: const Text(
                'Edit Contact Name',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(context);
                final controller = TextEditingController(text: name);
                final updated = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1F1F1F),
                    title: const Text(
                      'Edit Contact',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Display name',
                        hintStyle: TextStyle(color: Colors.grey.shade600),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );

                if (updated != null && updated.isNotEmpty) {
                  await db.updateUserName(userCode, updated);
                  onChanged?.call();
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Delete Contact & Chats',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1F1F1F),
                    title: const Text(
                      'Delete Contact',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: Text(
                      'Delete $name and all chats with this contact?',
                      style: TextStyle(color: Colors.grey.shade300),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await db.deleteUserAndChats(userCode);
                  onChanged?.call();
                }
              },
            ),
          ],
        ),
      );
    },
  );
}
