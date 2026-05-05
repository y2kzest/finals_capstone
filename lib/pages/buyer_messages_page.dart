import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';
import '../utils/helpers.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF4F6FB);

/// Buyer-side: list of all conversations, with ability to start a new one.
class BuyerMessagesPage extends StatefulWidget {
  const BuyerMessagesPage({super.key});

  @override
  State<BuyerMessagesPage> createState() => _BuyerMessagesPageState();
}

class _BuyerMessagesPageState extends State<BuyerMessagesPage> {
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
    unawaited(ensureOwnProfileRow(_supabase));
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
        .channel('buyer_convs_$_myId')
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
          .select(
              'id, seller_id, last_message, last_message_at, created_at')
          .eq('buyer_id', _myId!)
          .order('last_message_at', ascending: false);

      final convList = List<Map<String, dynamic>>.from(data);

      // Fetch seller names in bulk
      final sellerIds =
          convList.map((c) => c['seller_id'].toString()).toSet().toList();
      Map<String, String> sellerNames = {};
      Map<String, String?> sellerAvatars = {};
      if (sellerIds.isNotEmpty) {
        try {
          final sellers = await _supabase
              .from('seller_profiles')
              .select('user_id, store_name, logo_url')
              .inFilter('user_id', sellerIds);
          for (final s in sellers as List) {
            sellerNames[s['user_id'].toString()] =
                s['store_name']?.toString() ?? 'Seller';
            sellerAvatars[s['user_id'].toString()] =
                s['logo_url']?.toString();
          }
        } catch (_) {}
      }

      for (final c in convList) {
        final sid = c['seller_id'].toString();
        c['_seller_name'] = sellerNames[sid] ?? 'Seller';
        c['_seller_avatar'] = sellerAvatars[sid];
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
      debugPrint('Load conversations error: $e');
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
      final sellerId = conversation['seller_id']?.toString();
      if (sellerId == null || sellerId.isEmpty) continue;

      final currentId = conversation['id']?.toString();
      final existing = grouped[sellerId];
      if (existing == null) {
        grouped[sellerId] = {
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

      grouped[sellerId] = {
        ...latest,
        '_seller_name': existing['_seller_name'] ?? conversation['_seller_name'],
        '_seller_avatar': existing['_seller_avatar'] ?? conversation['_seller_avatar'],
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
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
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
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Messages',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827))),
              if (_conversations.isNotEmpty)
                Text('${_conversations.length} conversation${_conversations.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF))),
            ],
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
                const Text('No conversations yet',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF374151))),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    'Tap "Message Seller" on any product\nto start a conversation.',
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
    final sellerName = conv['_seller_name']?.toString() ?? 'Seller';
    final avatarUrl = conv['_seller_avatar']?.toString();
    final lastMsg = conv['last_message']?.toString() ?? '';
    final lastAt = conv['last_message_at'] != null
        ? DateTime.tryParse(conv['last_message_at'].toString())
        : null;
    final timeStr = lastAt != null ? _formatTime(lastAt) : '';
    final initials = sellerName.isNotEmpty
        ? sellerName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : 'S';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
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
                  otherName: sellerName,
                  otherAvatarUrl: avatarUrl,
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
                Stack(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kPrimary.withAlpha(22),
                        image: avatarUrl != null && avatarUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(avatarUrl),
                                fit: BoxFit.cover)
                            : null,
                      ),
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? Center(
                              child: Text(initials,
                                  style: const TextStyle(
                                      color: _kPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16)))
                          : null,
                    ),
                    // Online dot
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
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
                            child: Text(sellerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: Color(0xFF111827))),
                          ),
                          if (timeStr.isNotEmpty)
                            Text(timeStr,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF9CA3AF))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lastMsg.isEmpty ? 'No messages yet' : lastMsg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: lastMsg.isEmpty
                                ? const Color(0xFFD1D5DB)
                                : const Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
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

/// Helper: open or create a conversation between the current buyer and a seller,
/// then navigate to ChatPage. Call this from any product page.
Future<void> openOrCreateConversation(
  BuildContext context, {
  required String sellerId,
  required String sellerName,
  String? productId,
  String? sellerAvatarUrl,
}) async {
  final supabase = Supabase.instance.client;
  final buyerId = supabase.auth.currentUser?.id;
  if (buyerId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please log in to send a message.')),
    );
    return;
  }
  if (buyerId == sellerId) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You cannot message your own store.')),
    );
    return;
  }

  try {
    await ensureOwnProfileRow(supabase);

    // Reuse the newest existing conversation if legacy duplicates exist.
    final existingList = await supabase
        .from('conversations')
      .select('id, last_message_at, created_at')
        .eq('buyer_id', buyerId)
        .eq('seller_id', sellerId)
      .order('last_message_at', ascending: false)
      .order('created_at', ascending: false);
    final existing = existingList.isNotEmpty ? existingList.first : null;
    final conversationIds = existingList
      .map((row) => row['id']?.toString())
      .whereType<String>()
      .toSet()
      .toList();

    String convId;
    if (existing != null) {
      convId = existing['id'].toString();
    } else {
      final inserted = await supabase
          .from('conversations')
          .insert({
            'buyer_id': buyerId,
            'seller_id': sellerId,
          })
          .select('id')
          .single();
      convId = inserted['id'].toString();
      conversationIds.add(convId);
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          conversationId: convId,
          conversationIds: conversationIds,
          otherName: sellerName,
          otherAvatarUrl: sellerAvatarUrl,
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open conversation: $e')),
    );
  }
}
