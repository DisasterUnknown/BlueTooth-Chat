import 'package:bluetooth_chat_app/ui/chat_page/chat_page.dart';
import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:flutter/material.dart';

Widget buildChatList() {
  return FutureBuilder<String>(
    future: AppIdentifier.getId(),
    builder: (context, myIdSnapshot) {
      if (!myIdSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final db = DBHelper();
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: db.getAllUsers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data!;
          if (users.isEmpty) {
            return const Center(
              child: Text(
                'No users yet. Tap + to add one.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final name = (user['name'] as String?) ?? 'Unknown';
              final userCode = user['userCode'] as String? ?? '';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.greenAccent.shade400,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  userCode,
                  style: TextStyle(color: Colors.grey.shade400),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder:
                          (context, animation, secondaryAnimation) =>
                              ChatPage(userName: name, userId: userCode),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                        const begin = Offset(1.0, 0.0);
                        const end = Offset.zero;
                        const curve = Curves.ease;

                        final tween = Tween(
                          begin: begin,
                          end: end,
                        ).chain(CurveTween(curve: curve));

                        return SlideTransition(
                          position: animation.drive(tween),
                          child: child,
                        );
                      },
                    ),
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
