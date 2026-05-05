import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/chat_page.dart';

const Color _kPrimary = Color(0xFF1A4DBE);
const Color _kSurface = Color(0xFFF5F6FB);

/// Seller-side: list of conversations from buyers.
class SellerMessagesPage extends StatefulWidget {
  const SellerMessagesPage({super.key});

  @override
  State<SellerMessagesPage> createState() => _SellerMessagesPageState();
}

class _SellerMessagesPageState extends State<SellerMessagesPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _error;
  String? _myId;
  RealtimeChannel? _channel;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser?.id;
    _loadConversations();
    _subscribeRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _silentRefresh();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    if (_myId == null) return;
    if (_channel != null) _supabase.removeChannel(_channel!);
    _channel = _supabase
        .channel('seller_convs_$_myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) => _loadConversations(),
        )
        .subscribe();
  }

  void _refreshCurrentUser() {
    final latestUserId = _supabase.auth.currentUser?.id;
    if (latestUserId == null || latestUserId == _myId) return;
    _myId = latestUserId;
    _subscribeRealtime();
  }

  Future<void> _silentRefresh() async {
    _refreshCurrentUser();
    if (_myId == null) return;
    await _loadConversations(showLoading: false);
  }

  Future<void> _loadConversations({bool showLoading = true}) async {
    _refreshCurrentUser();
    if (_myId == null) {
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
      return;
    }
    if (mounted && showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final data = await _supabase
          .from('conversations')
          .select('id, buyer_id, last_message, last_message_at, created_at')
          .eq('seller_id', _myId!)
          .order('last_message_at', ascending: false);

      final convList = List<Map<String, dynamic>>.from(data);

      // Fetch buyer display names
      final buyerIds =
          convList.map((c) => c['buyer_id'].toString()).toSet().toList();
      Map<String, String> buyerNames = {};
      Map<String, String> buyerAvatars = {};
      if (buyerIds.isNotEmpty) {
        // Step 1: fetch name + email (always-safe columns)
        try {
          final profiles = await _supabase
              .from('profile')
              .select('user_id, name, email')
              .inFilter('user_id', buyerIds);
          for (final p in profiles as List) {
            final pName = p['name']?.toString() ?? '';
            final pEmail = p['email']?.toString() ?? '';
            final fallback =
                pEmail.isNotEmpty ? pEmail.split('@')[0] : 'Buyer';
            buyerNames[p['user_id'].toString()] =
                pName.isNotEmpty ? pName : fallback;
          }
        } catch (_) {}

        // Step 2: fetch avatar_url separately (column may not exist if migration not run)
        try {
          final avatarRows = await _supabase
              .from('profile')
              .select('user_id, avatar_url')
              .inFilter('user_id', buyerIds);
          for (final p in avatarRows as List) {
            final avatar = p['avatar_url']?.toString() ?? '';
            if (avatar.isNotEmpty) {
              buyerAvatars[p['user_id'].toString()] = avatar;
            }
          }
        } catch (_) {} // ignore if avatar_url column doesn't exist yet
      }

      for (final c in convList) {
        final bid = c['buyer_id'].toString();
        c['_buyer_name'] = buyerNames[bid] ?? 'Buyer';
        c['_buyer_avatar'] = buyerAvatars[bid] ?? '';
      }

      // Count unread per conversation
      for (final c in convList) {
        try {
          final unread = await _supabase
              .from('messages')
              .select('id')
              .eq('conversation_id', c['id'].toString())
              .neq('sender_id', _myId!)
              .eq('is_read', false);
          c['_unread'] = (unread as List).length;
        } catch (_) {
          c['_unread'] = 0;
        }
      }

      final mergedList = _mergeConversations(convList);

      if (mounted) {
        setState(() {
          _conversations = mergedList;
          if (showLoading) _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('Seller load conversations error: $e');
      if (mounted) {
        setState(() {
          if (showLoading) _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  List<Map<String, dynamic>> _mergeConversations(
      List<Map<String, dynamic>> conversations) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final conversation in conversations) {
      final buyerId = conversation['buyer_id']?.toString();
      if (buyerId == null || buyerId.isEmpty) continue;

      final currentId = conversation['id']?.toString();
      final existing = grouped[buyerId];
      if (existing == null) {
        grouped[buyerId] = {
          ...conversation,
          '_conversation_ids': currentId == null ? <String>[] : <String>[currentId],
        };
        continue;
      }

      final mergedIds = <String>{
        ...List<String>.from(existing['_conversation_ids'] as List? ?? const []),
        if (currentId != null) currentId,
      }.toList();

      final latest = _activityTime(conversation).isAfter(_activityTime(existing))
          ? conversation
          : existing;

      grouped[buyerId] = {
        ...latest,
        '_buyer_name': existing['_buyer_name'] ?? conversation['_buyer_name'],
        '_buyer_avatar': (existing['_buyer_avatar']?.toString() ?? '').isNotEmpty
            ? existing['_buyer_avatar']
            : (conversation['_buyer_avatar'] ?? ''),
        '_unread':
            (existing['_unread'] as int? ?? 0) + (conversation['_unread'] as int? ?? 0),
        '_conversation_ids': mergedIds,
      };
    }

    final mergedList = grouped.values.toList();
    mergedList.sort((a, b) => _activityTime(b).compareTo(_activityTime(a)));
    return mergedList;
  }

  DateTime _activityTime(Map<String, dynamic> conversation) {
    final lastMessageAt =
        DateTime.tryParse(conversation['last_message_at']?.toString() ?? '');
    final createdAt =
        DateTime.tryParse(conversation['created_at']?.toString() ?? '');
    return lastMessageAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final totalUnread = _conversations.fold<int>(
        0, (sum, c) => sum + ((c['_unread'] as int?) ?? 0));

    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(totalUnread),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kPrimary))
                  : RefreshIndicator(
                      color: _kPrimary,
                      onRefresh: _loadConversations,
                      child: _error != null
                          ? _errorState()
                          : _conversations.isEmpty
                              ? _emptyState()
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 8, 16, 24),
                                  itemCount: _conversations.length,
                                  itemBuilder: (_, i) =>
                                      _conversationTile(_conversations[i]),
                                ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int totalUnread) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Color(0xFF374151), size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kPrimary.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.chat_bubble_rounded,
                color: _kPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Customer Messages',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827))),
                if (_conversations.isNotEmpty)
                  Text(
                    totalUnread > 0
                        ? '$totalUnread unread message${totalUnread == 1 ? '' : 's'}'
                        : '${_conversations.length} conversation${_conversations.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 12,
                        color: totalUnread > 0
                            ? _kPrimary
                            : const Color(0xFF9CA3AF),
                        fontWeight: totalUnread > 0
                            ? FontWeight.w600
                            : FontWeight.normal),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.22),
          Center(
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: _kPrimary.withAlpha(18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded,
                      size: 42, color: _kPrimary),
                ),
                const SizedBox(height: 20),
                const Text('No customer messages yet',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF374151))),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    'Messages from buyers will\nappear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _errorState() => ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.22),
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.error_outline_rounded,
                      size: 38, color: Colors.red.shade400),
                ),
                const SizedBox(height: 20),
                const Text('Could not load messages',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF374151))),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'The messaging tables may not exist yet.\nAsk your admin to run the messaging migration.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                        height: 1.5),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _isLoading = true;
                    });
                    _loadConversations();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _conversationTile(Map<String, dynamic> conv) {
    final buyerName = conv['_buyer_name']?.toString() ?? 'Buyer';
    final buyerAvatar = conv['_buyer_avatar']?.toString() ?? '';
    final lastMsg = conv['last_message']?.toString() ?? '';
    final unread = (conv['_unread'] as int?) ?? 0;
    final lastAt = conv['last_message_at'] != null
        ? DateTime.tryParse(conv['last_message_at'].toString())
        : null;
    final timeStr = lastAt != null ? _formatTime(lastAt) : '';
    final initials = buyerName.isNotEmpty
        ? buyerName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : 'B';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: unread > 0 ? const Color(0xFFF0F4FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final conversationIds = List<String>.from(
                conv['_conversation_ids'] as List? ?? const []);
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatPage(
                  conversationId: conv['id'].toString(),
                  conversationIds: conversationIds,
                  otherName: buyerName,
                  otherAvatarUrl: buyerAvatar,
                ),
              ),
            );
            _loadConversations();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 26,
                  backgroundColor: _kPrimary.withAlpha(22),
                  backgroundImage: buyerAvatar.isNotEmpty
                      ? NetworkImage(buyerAvatar)
                      : null,
                  child: buyerAvatar.isEmpty
                      ? Text(initials,
                          style: const TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16))
                      : null,
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
                            child: Text(buyerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: unread > 0
                                        ? FontWeight.w800
                                        : FontWeight.w700,
                                    fontSize: 14,
                                    color: const Color(0xFF111827))),
                          ),
                          if (timeStr.isNotEmpty)
                            Text(timeStr,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: unread > 0
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: unread > 0
                                        ? _kPrimary
                                        : const Color(0xFF9CA3AF))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastMsg.isEmpty ? 'No messages yet' : lastMsg,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: unread > 0
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: unread > 0
                                      ? const Color(0xFF374151)
                                      : const Color(0xFF9CA3AF)),
                            ),
                          ),
                          if (unread > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _kPrimary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('$unread',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFFD1D5DB), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $period';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.month}/${dt.day}';
    }
  }
}
