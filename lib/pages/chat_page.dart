import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);

/// Full-screen chat for a single conversation.
/// [conversationId] — the conversations.id
/// [otherName]      — display name of the other party
/// [otherAvatarUrl] — optional avatar
class ChatPage extends StatefulWidget {
  final String conversationId;
  final List<String> conversationIds;
  final String otherName;
  final String? otherAvatarUrl;

  const ChatPage({
    super.key,
    required this.conversationId,
    this.conversationIds = const [],
    required this.otherName,
    this.otherAvatarUrl,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _supabase = Supabase.instance.client;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isSendingImage = false;
  bool _hasError = false;
  late final RealtimeChannel _channel;
  Timer? _pollTimer;
  String? _myId;

  List<String> get _conversationIds {
    return <String>{
      widget.conversationId,
      ...widget.conversationIds.where((id) => id.isNotEmpty),
    }.toList();
  }

  Future<List<Map<String, dynamic>>> _fetchMessages() async {
    dynamic query = _supabase
        .from('messages')
        .select('id, sender_id, content, image_url, created_at, is_read, conversation_id');

    final conversationIds = _conversationIds;
    if (conversationIds.length == 1) {
      query = query.eq('conversation_id', conversationIds.first);
    } else {
      query = query.inFilter('conversation_id', conversationIds);
    }

    final data = await query.order('created_at', ascending: true);
    final messages = List<Map<String, dynamic>>.from(data);
    messages.sort((a, b) {
      final createdAtA = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final createdAtB = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return createdAtA.compareTo(createdAtB);
    });
    return messages;
  }

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser?.id;
    unawaited(ensureOwnProfileRow(_supabase));
    _loadMessages();
    _subscribeRealtime();
    _markRead();
    // Fallback polling — ensures messages appear even when Realtime is not set up
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_isSending) _silentRefresh();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _supabase.removeChannel(_channel);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    _myId ??= _supabase.auth.currentUser?.id;
    try {
      final data = await _fetchMessages();
      if (mounted) {
        setState(() {
          _messages = data;
          _isLoading = false;
          _hasError = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Load messages error: $e');
      if (mounted) setState(() { _isLoading = false; _hasError = true; });
    }
  }

  /// Silent background refresh — merges new messages without resetting the list
  Future<void> _silentRefresh() async {
    _myId ??= _supabase.auth.currentUser?.id;
    try {
      final data = await _fetchMessages();
      if (!mounted) return;
      final fetched = List<Map<String, dynamic>>.from(data);
      final existingIds = _messages.map((m) => m['id']?.toString()).toSet();
      final newMsgs = fetched.where((m) => !existingIds.contains(m['id'])).toList();
      if (newMsgs.isNotEmpty) {
        setState(() => _messages.addAll(newMsgs));
        _scrollToBottom();
        _markRead();
      }
    } catch (_) {}
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('chat_${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            final newMsg = Map<String, dynamic>.from(payload.newRecord);
            if (mounted) {
              setState(() {
                // Deduplicate: sender already added it optimistically
                final exists = _messages.any((m) => m['id'] == newMsg['id']);
                if (!exists) _messages.add(newMsg);
              });
              _scrollToBottom();
              if (newMsg['sender_id']?.toString() != _myId) _markRead();
            }
          },
        )
        .subscribe();
  }

  Future<void> _markRead() async {
    _myId ??= _supabase.auth.currentUser?.id;
    if (_myId == null) return;
    try {
      dynamic query = _supabase
          .from('messages')
          .update({'is_read': true})
          .neq('sender_id', _myId!);

      final conversationIds = _conversationIds;
      if (conversationIds.length == 1) {
        query = query.eq('conversation_id', conversationIds.first);
      } else {
        query = query.inFilter('conversation_id', conversationIds);
      }

      await query;
    } catch (_) {}
  }

  Future<void> _send() async {
    _myId ??= _supabase.auth.currentUser?.id;
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _myId == null) return;
    setState(() => _isSending = true);
    _msgCtrl.clear();
    try {
      await ensureOwnProfileRow(_supabase);

      // Insert and get the full inserted row back
      final inserted = await _supabase
          .from('messages')
          .insert({
            'conversation_id': widget.conversationId,
            'sender_id': _myId,
            'content': text,
          })
          .select('id, sender_id, content, image_url, created_at, is_read')
          .single();

      // Add directly to UI — don't wait for Realtime (handles broken Realtime)
      if (mounted) {
        setState(() {
          final exists = _messages.any((m) => m['id'] == inserted['id']);
          if (!exists) _messages.add(Map<String, dynamic>.from(inserted));
        });
        _scrollToBottom();
      }

      // Update last_message on the conversation
      await _supabase.from('conversations').update({
        'last_message': text,
        'last_message_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.conversationId);
    } catch (e) {
      // Restore the typed text since send failed
      _msgCtrl.text = text;
      debugPrint('Send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendImage() async {
    _myId ??= _supabase.auth.currentUser?.id;
    if (_myId == null || _isSendingImage) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (picked == null || !mounted) return;

    setState(() => _isSendingImage = true);
    try {
      await ensureOwnProfileRow(_supabase);
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final fileName = '${_myId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

      await _supabase.storage
          .from('chat_images')
          .uploadBinary(fileName, bytes,
              fileOptions: FileOptions(contentType: mimeType, upsert: true));

      final imageUrl = _supabase.storage
          .from('chat_images')
          .getPublicUrl(fileName);

      final inserted = await _supabase
          .from('messages')
          .insert({
            'conversation_id': widget.conversationId,
            'sender_id': _myId,
            'content': '',
            'image_url': imageUrl,
          })
          .select('id, sender_id, content, image_url, created_at, is_read')
          .single();

      if (mounted) {
        setState(() {
          final exists = _messages.any((m) => m['id'] == inserted['id']);
          if (!exists) _messages.add(Map<String, dynamic>.from(inserted));
        });
        _scrollToBottom();
      }

      await _supabase.from('conversations').update({
        'last_message': '📷 Image',
        'last_message_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.conversationId);
    } catch (e) {
      debugPrint('Send image error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingImage = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.otherName.isNotEmpty
        ? widget.otherName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: const Color(0xFFEEF2FF),
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(40),
                image: widget.otherAvatarUrl != null &&
                        widget.otherAvatarUrl!.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(widget.otherAvatarUrl!),
                        fit: BoxFit.cover)
                    : null,
              ),
              child: widget.otherAvatarUrl == null ||
                      widget.otherAvatarUrl!.isEmpty
                  ? Center(
                      child: Text(initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.otherName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.white)),
                  const Text('Online',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          fontWeight: FontWeight.w400)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: _kPrimary))
                : _hasError
                    ? _errorState()
                    : RefreshIndicator(
                        color: _kPrimary,
                        onRefresh: _loadMessages,
                        child: _messages.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.45,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: _kPrimary.withAlpha(18),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                            Icons.chat_bubble_outline_rounded,
                                            size: 34,
                                            color: _kPrimary),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text('No messages yet',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              color: Color(0xFF374151))),
                                      const SizedBox(height: 6),
                                      const Text('Say hello! 👋',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF9CA3AF))),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final showDate = i == 0 ||
                                  _isDifferentDay(_messages[i - 1], _messages[i]);
                              return Column(
                                children: [
                                  if (showDate) _dateDivider(_messages[i]),
                                  _buildBubble(_messages[i]),
                                ],
                              );
                            },
                          ),
                      ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded,
                  size: 34, color: Colors.red.shade400),
            ),
            const SizedBox(height: 16),
            const Text('Could not load messages',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Color(0xFF374151))),
            const SizedBox(height: 8),
            const Text(
              'The messaging tables may not exist yet.\nAsk your admin to run the messaging SQL migration in Supabase.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF), height: 1.5),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() { _hasError = false; _isLoading = true; });
                _loadMessages();
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isDifferentDay(
      Map<String, dynamic> a, Map<String, dynamic> b) {
    final da = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final db = DateTime.tryParse(b['created_at']?.toString() ?? '');
    if (da == null || db == null) return false;
    return da.year != db.year || da.month != db.month || da.day != db.day;
  }

  Widget _dateDivider(Map<String, dynamic> msg) {
    final dt = DateTime.tryParse(msg['created_at']?.toString() ?? '');
    if (dt == null) return const SizedBox.shrink();
    final now = DateTime.now();
    String label;
    final diff = now.difference(dt).inDays;
    if (diff == 0) {
      label = 'Today';
    } else if (diff == 1) {
      label = 'Yesterday';
    } else {
      const months = [
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'
      ];
      label = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFDDE1F0))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500)),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFFDDE1F0))),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> msg) {
    final isMe = msg['sender_id']?.toString() == _myId;
    final createdAt = msg['created_at'] != null
        ? DateTime.tryParse(msg['created_at'].toString())?.toLocal()
        : null;
    final hour = createdAt?.hour ?? 0;
    final minute = createdAt?.minute ?? 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final timeStr = createdAt != null
        ? '${displayHour.toString()}:${minute.toString().padLeft(2, '0')} $period'
        : '';
    final imageUrl = msg['image_url']?.toString();

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? _kPrimary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: imageUrl != null && imageUrl.isNotEmpty
            ? Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      width: MediaQuery.of(context).size.width * 0.6,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : SizedBox(
                              width: MediaQuery.of(context).size.width * 0.6,
                              height: 160,
                              child: const Center(
                                  child: CircularProgressIndicator(
                                      color: _kPrimary, strokeWidth: 2)),
                            ),
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_rounded,
                          size: 48,
                          color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(timeStr,
                      style: TextStyle(
                          fontSize: 10,
                          color: isMe
                              ? Colors.white.withAlpha(178)
                              : const Color(0xFF9CA3AF))),
                ],
              )
            : Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(msg['content']?.toString() ?? '',
                      style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                          fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(timeStr,
                      style: TextStyle(
                          fontSize: 10,
                          color: isMe
                              ? Colors.white.withAlpha(178)
                              : const Color(0xFF9CA3AF))),
                ],
              ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              onTap: (_isSendingImage || _isSending) ? null : _sendImage,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDDE1F0)),
                ),
                child: _isSendingImage
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            color: _kPrimary, strokeWidth: 2))
                    : const Icon(Icons.image_rounded,
                        color: _kPrimary, size: 22),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                maxLines: null,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Type a message…',
                  hintStyle:
                      const TextStyle(color: Color(0xFFADB5BD), fontSize: 14),
                  filled: true,
                  fillColor: _kSurface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isSending ? null : _send,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _kPrimary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _isSending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
