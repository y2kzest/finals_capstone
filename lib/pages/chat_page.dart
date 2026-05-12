import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/marketplace_ui.dart';

/// Full-screen chat for a single conversation.
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
  String _draftText = '';
  RealtimeChannel? _channel;
  Timer? _pollTimer;
  String? _myId;

  List<String> get _conversationIds {
    return <String>{
      widget.conversationId,
      ...widget.conversationIds.where((id) => id.isNotEmpty),
    }.toList();
  }

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser?.id;
    _msgCtrl.addListener(_handleDraftChange);
    unawaited(ensureOwnProfileRow(_supabase));
    _loadMessages();
    _subscribeRealtime();
    _markRead();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_isSending) {
        _silentRefresh();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _msgCtrl.removeListener(_handleDraftChange);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  void _handleDraftChange() {
    final nextDraft = _msgCtrl.text.trim();
    if (nextDraft != _draftText && mounted) {
      setState(() => _draftText = nextDraft);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMessages() async {
    dynamic query = _supabase.from('messages').select(
      'id, sender_id, content, image_url, created_at, is_read, conversation_id',
    );

    final conversationIds = _conversationIds;
    if (conversationIds.length == 1) {
      query = query.eq('conversation_id', conversationIds.first);
    } else {
      query = query.inFilter('conversation_id', conversationIds);
    }

    final data = await query.order('created_at', ascending: true);
    final messages = List<Map<String, dynamic>>.from(data);
    messages.sort((a, b) {
      final createdAtA =
          DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final createdAtB =
          DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return createdAtA.compareTo(createdAtB);
    });
    return messages;
  }

  Future<void> _loadMessages() async {
    _myId ??= _supabase.auth.currentUser?.id;
    try {
      final data = await _fetchMessages();
      if (!mounted) return;
      setState(() {
        _messages = data;
        _isLoading = false;
        _hasError = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Load messages error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _silentRefresh() async {
    _myId ??= _supabase.auth.currentUser?.id;
    try {
      final data = await _fetchMessages();
      if (!mounted) return;
      final fetched = List<Map<String, dynamic>>.from(data);
      final existingIds = _messages.map((message) => message['id']?.toString()).toSet();
      final newMessages = fetched
          .where((message) => !existingIds.contains(message['id']?.toString()))
          .toList();
      if (newMessages.isNotEmpty) {
        setState(() => _messages.addAll(newMessages));
        _scrollToBottom();
        _markRead();
      }
    } catch (_) {}
  }

  void _subscribeRealtime() {
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }

    final conversationIds = _conversationIds.toSet();
    _channel = _supabase
        .channel('chat_${conversationIds.join('_')}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final newMsg = Map<String, dynamic>.from(payload.newRecord);
            final conversationId = newMsg['conversation_id']?.toString();
            if (conversationId == null || !conversationIds.contains(conversationId)) {
              return;
            }
            if (!mounted) return;
            setState(() {
              final exists = _messages.any((message) => message['id'] == newMsg['id']);
              if (!exists) {
                _messages.add(newMsg);
                _messages.sort((a, b) {
                  final createdAtA =
                      DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  final createdAtB =
                      DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  return createdAtA.compareTo(createdAtB);
                });
              }
            });
            _scrollToBottom();
            if (newMsg['sender_id']?.toString() != _myId) {
              _markRead();
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
    if (text.isEmpty || _myId == null || _isSending) return;

    setState(() => _isSending = true);
    _msgCtrl.clear();

    try {
      await ensureOwnProfileRow(_supabase);
      final inserted = await _supabase
          .from('messages')
          .insert({
            'conversation_id': widget.conversationId,
            'sender_id': _myId,
            'content': text,
          })
          .select(
            'id, sender_id, content, image_url, created_at, is_read, conversation_id',
          )
          .single();

      if (mounted) {
        setState(() {
          final exists = _messages.any((message) => message['id'] == inserted['id']);
          if (!exists) {
            _messages.add(Map<String, dynamic>.from(inserted));
          }
        });
        _scrollToBottom();
      }

      await _supabase.from('conversations').update({
        'last_message': text,
        'last_message_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.conversationId);
    } catch (e) {
      _msgCtrl.text = text;
      debugPrint('Send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: MarketplaceUi.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
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

      await _supabase.storage.from('chat_images').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );

      final imageUrl = _supabase.storage.from('chat_images').getPublicUrl(fileName);
      final inserted = await _supabase
          .from('messages')
          .insert({
            'conversation_id': widget.conversationId,
            'sender_id': _myId,
            'content': '',
            'image_url': imageUrl,
          })
          .select(
            'id, sender_id, content, image_url, created_at, is_read, conversation_id',
          )
          .single();

      if (mounted) {
        setState(() {
          final exists = _messages.any((message) => message['id'] == inserted['id']);
          if (!exists) {
            _messages.add(Map<String, dynamic>.from(inserted));
          }
        });
        _scrollToBottom();
      }

      await _supabase.from('conversations').update({
        'last_message': 'Photo',
        'last_message_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.conversationId);
    } catch (e) {
      debugPrint('Send image error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: $e'),
            backgroundColor: MarketplaceUi.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingImage = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  bool _isDifferentDay(Map<String, dynamic> a, Map<String, dynamic> b) {
    final first = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final second = DateTime.tryParse(b['created_at']?.toString() ?? '');
    if (first == null || second == null) return false;
    return first.year != second.year ||
        first.month != second.month ||
        first.day != second.day;
  }

  String _formatBubbleTime(DateTime? createdAt) {
    if (createdAt == null) return '';
    final local = createdAt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _formatDateDivider(DateTime dateTime) {
    final now = DateTime.now();
    final startOfNow = DateTime(now.year, now.month, now.day);
    final startOfDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final diff = startOfNow.difference(startOfDate).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.otherName.trim().isEmpty
        ? '?'
        : widget.otherName
            .trim()
            .split(' ')
            .where((part) => part.isNotEmpty)
            .map((part) => part[0])
            .take(2)
            .join()
            .toUpperCase();

    return Scaffold(
      backgroundColor: MarketplaceUi.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(initials),
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -18),
                child: Container(
                  decoration: const BoxDecoration(
                    color: MarketplaceUi.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -60,
                        right: -20,
                        child: _buildGlow(const Color(0x2243C7B8), 180),
                      ),
                      Positioned(
                        bottom: 30,
                        left: -30,
                        child: _buildGlow(const Color(0x1424439B), 220),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _buildBody(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String initials) {
    final messageCount = _messages.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MarketplaceUi.primary, MarketplaceUi.primaryDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
        boxShadow: [
          BoxShadow(
            color: Color(0x2624439B),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              foregroundColor: Colors.white,
              minimumSize: const Size(44, 44),
            ),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          ),
          const SizedBox(width: 12),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.otherAvatarUrl != null && widget.otherAvatarUrl!.isNotEmpty
                ? Image.network(
                    widget.otherAvatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Marketplace conversation',
                  style: TextStyle(
                    color: Color(0xFFD8E4FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildHeaderChip(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '$messageCount messages',
                    ),
                    _buildHeaderChip(
                      icon: Icons.flash_on_rounded,
                      label: 'Realtime sync',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _loadingState();
    }
    if (_hasError) {
      return _errorState();
    }
    return RefreshIndicator(
      key: ValueKey('chat_${_messages.length}_${_hasError ? 1 : 0}'),
      color: MarketplaceUi.primary,
      onRefresh: _loadMessages,
      child: _messages.isEmpty ? _emptyState() : _messagesList(),
    );
  }

  Widget _loadingState() {
    return ListView(
      key: const ValueKey('chat_loading'),
      padding: MarketplaceUi.pagePadding(context, top: 24, bottom: 18),
      children: List.generate(6, (index) {
        final isMine = index.isOdd;
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: MediaQuery.of(context).size.width * (isMine ? 0.56 : 0.62),
            height: 70,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: isMine ? const Color(0xFFE3EAFF) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D0F172A),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _emptyState() {
    return ListView(
      key: const ValueKey('chat_empty'),
      padding: MarketplaceUi.pagePadding(context, top: 48, bottom: 18),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: MarketplaceUi.panel(),
          child: Column(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: MarketplaceUi.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.forum_outlined,
                  size: 42,
                  color: MarketplaceUi.primary,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No messages yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: MarketplaceUi.textStrong,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start the conversation with ${widget.otherName}. Questions, order updates, and support details will stay together here.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: MarketplaceUi.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorState() {
    return ListView(
      key: const ValueKey('chat_error'),
      padding: MarketplaceUi.pagePadding(context, top: 48, bottom: 18),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: MarketplaceUi.panel(),
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: MarketplaceUi.danger.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 40,
                  color: MarketplaceUi.danger,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Could not load messages',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: MarketplaceUi.textStrong,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The messaging tables may not exist yet. Ask your admin to run the messaging migration in Supabase.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: MarketplaceUi.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _isLoading = true;
                  });
                  _loadMessages();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _messagesList() {
    return ListView.builder(
      key: ValueKey('chat_messages_${_messages.length}'),
      controller: _scrollCtrl,
      padding: MarketplaceUi.pagePadding(context, top: 22, bottom: 18),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final currentMessage = _messages[index];
        final showDate =
            index == 0 || _isDifferentDay(_messages[index - 1], currentMessage);
        return Column(
          children: [
            if (showDate) _dateDivider(currentMessage),
            _buildBubble(currentMessage),
          ],
        );
      },
    );
  }

  Widget _dateDivider(Map<String, dynamic> message) {
    final createdAt = DateTime.tryParse(message['created_at']?.toString() ?? '');
    if (createdAt == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFDCE3F0))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                _formatDateDivider(createdAt.toLocal()),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MarketplaceUi.textMuted,
                ),
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFFDCE3F0))),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> message) {
    final isMine = message['sender_id']?.toString() == _myId;
    final createdAt =
        DateTime.tryParse(message['created_at']?.toString() ?? '')?.toLocal();
    final timeText = _formatBubbleTime(createdAt);
    final imageUrl = message['image_url']?.toString().trim() ?? '';
    final content = message['content']?.toString() ?? '';
    final hasImage = imageUrl.isNotEmpty;
    final bubbleColor = isMine ? const Color(0xFF2D4FC5) : Colors.white;
    final textColor = isMine ? Colors.white : MarketplaceUi.textStrong;
    final metaColor = isMine
        ? Colors.white.withValues(alpha: 0.78)
        : MarketplaceUi.textSubtle;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * (hasImage ? 0.78 : 0.76),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(24),
              topRight: const Radius.circular(24),
              bottomLeft: Radius.circular(isMine ? 24 : 8),
              bottomRight: Radius.circular(isMine ? 8 : 24),
            ),
            border: isMine ? null : Border.all(color: const Color(0xFFE6ECF5)),
            boxShadow: [
              BoxShadow(
                color: isMine
                    ? const Color(0x1F24439B)
                    : const Color(0x100F172A),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
            gradient: isMine
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3257D1), Color(0xFF1E3FAD)],
                  )
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              hasImage ? 8 : 14,
              hasImage ? 8 : 12,
              hasImage ? 8 : 14,
              10,
            ),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (hasImage) _buildImageBubble(imageUrl),
                if (hasImage && content.isNotEmpty) const SizedBox(height: 10),
                if (content.isNotEmpty)
                  Text(
                    content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: metaColor,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 6),
                      Icon(
                        message['is_read'] == true
                            ? Icons.done_all_rounded
                            : Icons.check_rounded,
                        size: 13,
                        color: message['is_read'] == true
                            ? const Color(0xFFA8F2DC)
                            : metaColor,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageBubble(String imageUrl) {
    final bubbleWidth = MediaQuery.of(context).size.width * 0.62;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            width: bubbleWidth,
            height: 220,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: bubbleWidth,
                height: 220,
                color: const Color(0xFFEAF0FB),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: MarketplaceUi.primary,
                    strokeWidth: 2.4,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) => Container(
              width: bubbleWidth,
              height: 220,
              color: const Color(0xFFEAF0FB),
              alignment: Alignment.center,
              child: const Icon(
                Icons.broken_image_rounded,
                size: 46,
                color: MarketplaceUi.textSubtle,
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final canSend = _draftText.isNotEmpty && !_isSending && !_isSendingImage;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            InkWell(
              onTap: (_isSending || _isSendingImage) ? null : _sendImage,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: MarketplaceUi.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCE3F0)),
                ),
                child: _isSendingImage
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          color: MarketplaceUi.primary,
                          strokeWidth: 2.2,
                        ),
                      )
                    : const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: MarketplaceUi.primary,
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: MarketplaceUi.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFDCE3F0)),
                ),
                child: TextField(
                  controller: _msgCtrl,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Type a message',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: canSend ? 1 : 0.72,
              child: InkWell(
                onTap: canSend ? _send : null,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: canSend
                        ? const LinearGradient(
                            colors: [MarketplaceUi.primary, MarketplaceUi.primaryDark],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF9DB1E5), Color(0xFF87A0DE)],
                          ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: canSend
                        ? const [
                            BoxShadow(
                              color: Color(0x2624439B),
                              blurRadius: 18,
                              offset: Offset(0, 10),
                            ),
                          ]
                        : null,
                  ),
                  child: _isSending
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.3,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
