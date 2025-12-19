import 'package:bluetooth_chat_app/data/models/message.dart';
import 'package:bluetooth_chat_app/ui/chat_page/widget/message_bubble.dart';
import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/services/mesh_service.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:flutter/material.dart';

class ChatPage extends StatefulWidget {
  final String userName;
  final String userId;

  const ChatPage({super.key, required this.userName, required this.userId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _myId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final myId = await AppIdentifier.getId();
    final db = DBHelper();
    final rawMsgs =
        await db.getChatMsgs(widget.userId, myUserCode: myId);
    final loaded = rawMsgs.map((m) {
      final text = (m['msg'] as String?) ?? '';
      final isMe = m['isReceived'] == 0;
      final sendDateStr = (m['sendDate'] as String?) ??
          DateTime.now().toIso8601String();
      final time = DateTime.tryParse(sendDateStr) ?? DateTime.now();
      return Message(text: text, isMe: isMe, time: time);
    }).toList();

    if (!mounted) return;
    setState(() {
      _myId = myId;
      _messages.clear();
      _messages.addAll(loaded);
    });
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_myId == null) return;

    final msg = Message(text: text, isMe: true, time: DateTime.now());

    setState(() {
      _messages.add(msg);
    });

    _controller.clear();

    // Persist + enqueue for mesh forwarding.
    MeshService.instance.sendNewMessage(
      myUserCode: _myId!,
      targetUserCode: widget.userId,
      plainText: text,
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: const Color(0xFF1F1F1F),
        iconTheme: const IconThemeData(color: Colors.greenAccent),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.greenAccent,
              child: Icon(Icons.person, color: Colors.black),
            ),
            const SizedBox(width: 8),
            Text(widget.userName, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return buildMessageBubble(msg, context);
              },
            ),
          ),
          _buildInputField(),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF1F1F1F),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Message',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
              ),
              minLines: 1,
              maxLines: 4,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: CircleAvatar(
              backgroundColor: Colors.greenAccent.shade400,
              child: const Icon(Icons.send, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
