// lib/features/messages/screens/message_screen.dart  (Resident App)
//
// ── UPDATED ──────────────────────────────────────────────────────────────────
// Now shows real conversations initiated by the dispatcher for each report
// the user has filed. The user can reply back and coordinate the station visit
// for their witness statement.
//
// Firebase path: /DispatcherChats/{chatId}/
//   meta/   → chatId, reportId, reportType, userId, userName, dispatcherName,
//              lastMessage, lastMessageAt, unreadByUser, unreadByDisp
//   messages/{auto-id}/ → senderId, senderName, text, timestamp, isFromDisp
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../map/screens/map_screen.dart';
import '../../notifications/screens/notification_screen.dart';
import '../../auth/screens/settings_screen.dart';

const String _kDbUrl =
    'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

// ════════════════════════════════════════════════════════════════════════════
// Lightweight data models
// ════════════════════════════════════════════════════════════════════════════

class _ChatMeta {
  final String chatId;
  final String reportId;
  final String reportType;
  final String dispatcherName;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadByUser;

  const _ChatMeta({
    required this.chatId,
    required this.reportId,
    required this.reportType,
    required this.dispatcherName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadByUser,
  });

  factory _ChatMeta.fromMap(Map map, String chatId) => _ChatMeta(
        chatId: chatId,
        reportId: map['reportId']?.toString() ?? '',
        reportType: map['reportType']?.toString() ?? 'Emergency',
        dispatcherName: map['dispatcherName']?.toString() ?? 'Dispatcher',
        lastMessage: map['lastMessage']?.toString() ?? '',
        lastMessageAt:
            DateTime.tryParse(map['lastMessageAt']?.toString() ?? '') ??
                DateTime.now(),
        unreadByUser: (map['unreadByUser'] as num?)?.toInt() ?? 0,
      );
}

class _ChatMessage {
  final String id;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool isFromDispatcher;

  const _ChatMessage({
    required this.id,
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.isFromDispatcher,
  });

  factory _ChatMessage.fromMap(Map map, String key) => _ChatMessage(
        id: key,
        senderName: map['senderName']?.toString() ?? 'Unknown',
        text: map['text']?.toString() ?? '',
        timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        isFromDispatcher: map['isFromDisp'] == true,
      );
}

// ════════════════════════════════════════════════════════════════════════════
// MessageScreen — chat inbox
// ════════════════════════════════════════════════════════════════════════════

class MessageScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const MessageScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  int _selectedIndex = 2;
  List<_ChatMeta> _chats = [];
  bool _loading = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchChats();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _fetchChats());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchChats() async {
    try {
      final resp = await http
          .get(Uri.parse('${_kDbUrl}DispatcherChats.json'))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final raw = json.decode(resp.body);
        if (raw != null && raw is Map) {
          final chats = <_ChatMeta>[];
          for (final entry in (raw).entries) {
            final chatData = entry.value;
            if (chatData is Map && chatData['meta'] is Map) {
              final meta = chatData['meta'] as Map;
              if (meta['userId']?.toString() == widget.userId) {
                chats.add(_ChatMeta.fromMap(meta, entry.key.toString()));
              }
            }
          }
          chats.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
          if (mounted) {
            setState(() {
              _chats = chats;
              _loading = false;
            });
          }
        } else {
          if (mounted) setState(() => _loading = false);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Bottom navigation ─────────────────────────────────────────────────────

  void _onBottomNavTap(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => DashboardScreen(
                    userId: widget.userId, userName: widget.userName)));
        break;
      case 1:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => const MapScreen(userId: '', familyCode: '')));
        break;
      case 2:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const _NotifLauncher()));
        break;
      case 3:
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => SettingsScreen(
                    userId: widget.userId, userName: widget.userName)));
        break;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Messages',
                style: TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            Text('Dispatcher Communications',
                style: TextStyle(color: AppColors.grey, fontSize: 11)),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _chats.isEmpty
              ? _buildEmpty()
              : _buildChatList(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline,
                  size: 52, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text('No messages yet',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary)),
            const SizedBox(height: 8),
            const Text(
              'When a dispatcher contacts you about your emergency report, the conversation will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textLight, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _chats.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ChatListTile(
        meta: _chats[i],
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _ChatConvoScreen(
                chatId: _chats[i].chatId,
                reportType: _chats[i].reportType,
                dispatcherName: _chats[i].dispatcherName,
                userId: widget.userId,
                userName: widget.userName,
              ),
            ),
          );
          _fetchChats();
        },
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -3))
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onBottomNavTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.secondary,
        unselectedItemColor: AppColors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home, size: 28), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.map, size: 28), label: 'Map'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined, size: 28),
              label: 'Notifications'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined, size: 28), label: 'Settings'),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Chat list tile
// ════════════════════════════════════════════════════════════════════════════

class _ChatListTile extends StatelessWidget {
  final _ChatMeta meta;
  final VoidCallback onTap;

  const _ChatListTile({required this.meta, required this.onTap});

  Color _typeColor() {
    switch (meta.reportType.toLowerCase()) {
      case 'crime':
        return const Color(0xFF1565C0);
      case 'fire':
        return const Color(0xFFE53935);
      case 'medical':
        return const Color(0xFF8E24AA);
      case 'flood':
        return const Color(0xFF00838F);
      case 'accident':
        return const Color(0xFFEF6C00);
      default:
        return AppColors.primary;
    }
  }

  String _typeEmoji() {
    switch (meta.reportType.toLowerCase()) {
      case 'crime':
        return '🚨';
      case 'fire':
        return '🔥';
      case 'medical':
        return '🏥';
      case 'flood':
        return '🌊';
      case 'accident':
        return '🚗';
      default:
        return '⚠️';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor();
    final hasUnread = meta.unreadByUser > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hasUnread ? color.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasUnread ? color.withOpacity(0.3) : const Color(0xFFE8EDF5),
            width: hasUnread ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(_typeEmoji(), style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${meta.reportType} Report',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                hasUnread ? FontWeight.w800 : FontWeight.w600,
                            color: AppColors.secondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _relativeTime(meta.lastMessageAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: hasUnread ? color : AppColors.grey,
                          fontWeight:
                              hasUnread ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.support_agent,
                          size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(meta.dispatcherName,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta.lastMessage.isEmpty
                              ? 'Conversation started'
                              : meta.lastMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color: hasUnread
                                ? AppColors.secondary
                                : AppColors.textLight,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${meta.unreadByUser}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.grey, size: 18),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays == 1) return 'Yesterday';
    return DateFormat('MMM dd').format(dt);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _ChatConvoScreen — full conversation (user side)
// ════════════════════════════════════════════════════════════════════════════

class _ChatConvoScreen extends StatefulWidget {
  final String chatId;
  final String reportType;
  final String dispatcherName;
  final String userId;
  final String userName;

  const _ChatConvoScreen({
    required this.chatId,
    required this.reportType,
    required this.dispatcherName,
    required this.userId,
    required this.userName,
  });

  @override
  State<_ChatConvoScreen> createState() => _ChatConvoScreenState();
}

class _ChatConvoScreenState extends State<_ChatConvoScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  List<_ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;

  static const List<String> _suggestions = [
    '✅ I can come to the station tomorrow.',
    '📅 What time should I be there?',
    '📍 Can you send the station address?',
    '⏰ I am available at 9:00 AM.',
    '⏰ I am available at 2:00 PM.',
    '🙏 Thank you, I will be there.',
  ];

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _markRead();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _fetchMessages());
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    try {
      final resp = await http
          .get(Uri.parse(
              '${_kDbUrl}DispatcherChats/${widget.chatId}/messages.json'))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final raw = json.decode(resp.body);
        if (raw != null && raw is Map) {
          final msgs = (raw)
              .entries
              .map(
                  (e) => _ChatMessage.fromMap(e.value as Map, e.key.toString()))
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          if (mounted) {
            setState(() {
              _messages = msgs;
              _loading = false;
            });
          }
          _scrollToBottom();
        } else {
          if (mounted) setState(() => _loading = false);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead() async {
    try {
      await http
          .patch(
            Uri.parse('${_kDbUrl}DispatcherChats/${widget.chatId}/meta.json'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'unreadByUser': 0}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _inputCtrl.clear();
    setState(() => _sending = true);

    try {
      final now = DateTime.now();
      await http
          .post(
            Uri.parse(
                '${_kDbUrl}DispatcherChats/${widget.chatId}/messages.json'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'senderId': widget.userId,
              'senderName': widget.userName,
              'text': trimmed,
              'timestamp': now.toIso8601String(),
              'isFromDisp': false,
            }),
          )
          .timeout(const Duration(seconds: 10));

      await http
          .patch(
            Uri.parse('${_kDbUrl}DispatcherChats/${widget.chatId}/meta.json'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'lastMessage': trimmed.length > 60
                  ? '${trimmed.substring(0, 60)}…'
                  : trimmed,
              'lastMessageAt': now.toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 5));

      _incrementDispUnread();
    } catch (_) {}

    setState(() => _sending = false);
    _fetchMessages();
  }

  Future<void> _incrementDispUnread() async {
    try {
      final url =
          '${_kDbUrl}DispatcherChats/${widget.chatId}/meta/unreadByDisp.json';
      final r =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      final cur = (json.decode(r.body) as num?)?.toInt() ?? 0;
      await http
          .put(Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(cur + 1))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color get _typeColor {
    switch (widget.reportType.toLowerCase()) {
      case 'crime':
        return const Color(0xFF1565C0);
      case 'fire':
        return const Color(0xFFE53935);
      case 'medical':
        return const Color(0xFF8E24AA);
      case 'flood':
        return const Color(0xFF00838F);
      case 'accident':
        return const Color(0xFFEF6C00);
      default:
        return AppColors.primary;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                _buildNoticeBanner(),
                Expanded(child: _buildMessageList()),
                _buildSuggestions(),
                _buildInputBar(),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _typeColor.withOpacity(0.12),
            child: const Icon(Icons.support_agent,
                size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.dispatcherName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.secondary),
                    overflow: TextOverflow.ellipsis),
                const Text('Police Dispatcher · LifeGuard360',
                    style: TextStyle(fontSize: 10, color: AppColors.grey)),
              ],
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFE8EDF5)),
      ),
    );
  }

  Widget _buildNoticeBanner() {
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _typeColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _typeColor.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.gavel, color: _typeColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The dispatcher may request you to visit the Panabo City Police Station as a witness for your ${widget.reportType} report.',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textLight, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48, color: AppColors.grey.withOpacity(0.35)),
            const SizedBox(height: 12),
            const Text('No messages yet',
                style: TextStyle(fontSize: 14, color: AppColors.grey)),
            const SizedBox(height: 6),
            const Text('The dispatcher will reach out soon.',
                style: TextStyle(fontSize: 11, color: AppColors.textLight)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg = _messages[i];
        final showDate =
            i == 0 || !_sameDay(_messages[i - 1].timestamp, msg.timestamp);
        return Column(
          children: [
            if (showDate) _buildDateSep(msg.timestamp),
            _buildBubble(msg),
          ],
        );
      },
    );
  }

  Widget _buildDateSep(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFE8EDF5))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(_dateHeader(dt),
                style: const TextStyle(fontSize: 10, color: AppColors.grey)),
          ),
          const Expanded(child: Divider(color: Color(0xFFE8EDF5))),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final isMe = !msg.isFromDispatcher;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: _typeColor.withOpacity(0.12),
              child: const Icon(Icons.support_agent,
                  size: 14, color: AppColors.primary),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(msg.senderName,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.grey)),
                  ),
                Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.primary : AppColors.lightGrey,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: Text(msg.text,
                      style: TextStyle(
                          fontSize: 13,
                          color: isMe ? Colors.white : AppColors.secondary,
                          height: 1.45)),
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(DateFormat('hh:mm a').format(msg.timestamp),
                      style:
                          const TextStyle(fontSize: 9, color: AppColors.grey)),
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary.withOpacity(0.15),
              child: Text(
                widget.userName.isNotEmpty
                    ? widget.userName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EDF5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('QUICK REPLIES',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppColors.grey,
                    letterSpacing: 1.2)),
          ),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _send(_suggestions[i]),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.22)),
                  ),
                  child: Text(
                    _suggestions[i].length > 30
                        ? '${_suggestions[i].substring(0, 30)}…'
                        : _suggestions[i],
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EDF5))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _inputCtrl,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Type a message…',
                    hintStyle: TextStyle(color: AppColors.grey, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: _send,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : () => _send(_inputCtrl.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _sending
                      ? AppColors.primary.withOpacity(0.5)
                      : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateHeader(DateTime dt) {
    final now = DateTime.now();
    if (_sameDay(dt, now)) return 'Today';
    if (_sameDay(dt, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return DateFormat('MMM dd, yyyy').format(dt);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _NotifLauncher  (unchanged)
// ════════════════════════════════════════════════════════════════════════════

class _NotifLauncher extends StatefulWidget {
  const _NotifLauncher();

  @override
  State<_NotifLauncher> createState() => _NotifLauncherState();
}

class _NotifLauncherState extends State<_NotifLauncher> {
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? '';
    final familyCode = prefs.getString('familyCode') ?? '';
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NotificationScreen(userId: userId, familyCode: familyCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
