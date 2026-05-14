import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/helpers.dart';
import '../utils/marketplace_ui.dart';
import '../utils/message_support.dart';
import 'chat_page.dart';

/// Buyer-side: list of all buyer-to-seller conversations.
class BuyerMessagesPage extends StatefulWidget {
  const BuyerMessagesPage({super.key});

  @override
  State<BuyerMessagesPage> createState() => _BuyerMessagesPageState();
}

class _BuyerMessagesPageState extends State<BuyerMessagesPage> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _error;
  String? _myId;
  RealtimeChannel? _channel;
  Timer? _pollTimer;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _myId = _supabase.auth.currentUser?.id;
    unawaited(ensureOwnProfileRow(_supabase));
    _searchController.addListener(_handleSearchChange);
    _loadConversations();
    _subscribeRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _silentRefresh();
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChange);
    _searchController.dispose();
    _pollTimer?.cancel();
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  void _handleSearchChange() {
    final nextValue = _searchController.text.trim().toLowerCase();
    if (nextValue != _searchQuery && mounted) {
      setState(() => _searchQuery = nextValue);
    }
  }

  void _subscribeRealtime() {
    if (_myId == null) return;
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    _channel = _supabase
        .channel('buyer_convs_$_myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) => _loadConversations(showLoading: false),
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

  Future<int> _countUnreadMessages(String conversationId) async {
    if (_myId == null) return 0;
    try {
      final unread = await _supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', _myId!)
          .eq('is_read', false);
      return (unread as List).length;
    } catch (_) {
      return 0;
    }
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
          .select('id, seller_id, last_message, last_message_at, created_at')
          .eq('buyer_id', _myId!)
          .order('last_message_at', ascending: false);

      final convList = List<Map<String, dynamic>>.from(data);
      final adminIds = await fetchAdminUserIds(_supabase);
      if (adminIds.isNotEmpty) {
        convList.removeWhere(
          (conversation) =>
              adminIds.contains(conversation['seller_id']?.toString()),
        );
      }

      final sellerIds = convList
          .map((conversation) => conversation['seller_id']?.toString())
          .whereType<String>()
          .where((sellerId) => sellerId.isNotEmpty)
          .toSet()
          .toList();

      final sellerNames = <String, String>{};
      final sellerAvatars = <String, String?>{};
      if (sellerIds.isNotEmpty) {
        try {
          final sellers = await _supabase
              .from('seller_profiles')
              .select('user_id, store_name, logo_url')
              .inFilter('user_id', sellerIds);
          for (final seller in sellers as List) {
            final sellerId = seller['user_id']?.toString();
            if (sellerId == null || sellerId.isEmpty) continue;
            sellerNames[sellerId] =
                seller['store_name']?.toString().trim().isNotEmpty == true
                ? seller['store_name'].toString()
                : 'Seller';
            sellerAvatars[sellerId] = seller['logo_url']?.toString();
          }
        } catch (_) {}
      }

      for (final conversation in convList) {
        final sellerId = conversation['seller_id']?.toString();
        if (sellerId != null && sellerId.isNotEmpty) {
          conversation['_seller_name'] = sellerNames[sellerId] ?? 'Seller';
          conversation['_seller_avatar'] = sellerAvatars[sellerId];
        }
        final conversationId = conversation['id']?.toString();
        conversation['_unread'] = conversationId == null || conversationId.isEmpty
            ? 0
            : await _countUnreadMessages(conversationId);
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
    List<Map<String, dynamic>> conversations,
  ) {
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
        '_unread':
            (existing['_unread'] as int? ?? 0) +
            (conversation['_unread'] as int? ?? 0),
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

  List<Map<String, dynamic>> _visibleConversations() {
    if (_searchQuery.isEmpty) return _conversations;
    return _conversations.where((conversation) {
      final sellerName =
          conversation['_seller_name']?.toString().toLowerCase() ?? '';
      final lastMessage =
          conversation['last_message']?.toString().toLowerCase() ?? '';
      return sellerName.contains(_searchQuery) ||
          lastMessage.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibleConversations = _visibleConversations();
    final totalUnread = visibleConversations.fold<int>(
      0,
      (sum, conversation) => sum + ((conversation['_unread'] as int?) ?? 0),
    );

    return Scaffold(
      backgroundColor: MarketplaceUi.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeroHeader(
              conversationCount: visibleConversations.length,
              totalUnread: totalUnread,
            ),
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
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: _isLoading
                        ? _loadingState()
                        : RefreshIndicator(
                            key: ValueKey(
                              'buyer_messages_${_error ?? visibleConversations.length}',
                            ),
                            color: MarketplaceUi.primary,
                            onRefresh: _loadConversations,
                            child: _error != null
                                ? _errorState()
                                : visibleConversations.isEmpty
                                ? _emptyState()
                                : ListView(
                                    padding: MarketplaceUi.pagePadding(
                                      context,
                                      top: 24,
                                      bottom: 28,
                                    ),
                                    children: [
                                      ...visibleConversations.asMap().entries.map(
                                            (entry) => AppearOnMount(
                                              delay: staggerDelay(
                                                entry.key,
                                                step: 40,
                                                maxMs: 280,
                                              ),
                                              child: _conversationTile(entry.value),
                                            ),
                                          ),
                                    ],
                                  ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader({
    required int conversationCount,
    required int totalUnread,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 38),
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
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: const Icon(
                  Icons.forum_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Consumer-to-Vendor conversations',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFFDCE6FF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (totalUnread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$totalUnread unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildHeroMetric(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Conversations',
                  value: '$conversationCount',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHeroMetric(
                  icon: Icons.mark_chat_unread_rounded,
                  label: 'Unread',
                  value: '$totalUnread',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Search sellers or recent messages',
                hintStyle: const TextStyle(color: Color(0xD9F3F6FF)),
                filled: true,
                fillColor: Colors.transparent,
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: _searchController.clear,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                      )
                    : const Icon(
                        Icons.tune_rounded,
                        color: Color(0xFFC9D6FB),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFDCE6FF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingState() {
    return ListView(
      key: const ValueKey('buyer_loading'),
      padding: MarketplaceUi.pagePadding(context, top: 24, bottom: 28),
      children: [
        ...List.generate(5, (_) => _loadingTile()),
      ],
    );
  }

  Widget _loadingTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: MarketplaceUi.panel(),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EDF6),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EDF6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F3F8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F3F8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      key: const ValueKey('buyer_empty'),
      padding: MarketplaceUi.pagePadding(context, top: 24, bottom: 28),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          decoration: MarketplaceUi.panel(),
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: MarketplaceUi.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 42,
                  color: MarketplaceUi.primary,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No conversations yet',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: MarketplaceUi.textStrong,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap Message Seller on any product to start a conversation and keep track of your orders in one place.',
                textAlign: TextAlign.center,
                style: TextStyle(
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
      key: const ValueKey('buyer_error'),
      padding: MarketplaceUi.pagePadding(context, top: 24, bottom: 28),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          decoration: MarketplaceUi.panel(),
          child: Column(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: MarketplaceUi.danger.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 38,
                  color: MarketplaceUi.danger,
                ),
              ),
              const SizedBox(height: 20),
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
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _isLoading = true;
                  });
                  _loadConversations();
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

  Widget _conversationTile(Map<String, dynamic> conversation) {
    final sellerName = conversation['_seller_name']?.toString() ?? 'Seller';
    final avatarUrl = conversation['_seller_avatar']?.toString();
    final lastMessage = conversation['last_message']?.toString() ?? '';
    final unread = (conversation['_unread'] as int?) ?? 0;
    final lastAt = conversation['last_message_at'] != null
        ? DateTime.tryParse(conversation['last_message_at'].toString())
        : null;
    final timeText = lastAt != null ? _formatTime(lastAt) : '';
    final isRecentlyActive =
        lastAt != null && DateTime.now().difference(lastAt).inMinutes < 30;
    final accentColor = unread > 0
        ? MarketplaceUi.primary
        : isRecentlyActive
        ? MarketplaceUi.accent
        : MarketplaceUi.textSubtle;
    final statusText = unread > 0
        ? '$unread unread'
        : isRecentlyActive
        ? 'Active recently'
        : 'Seller chat';
    final previewText = lastMessage.isEmpty
        ? 'Start the conversation from any product page.'
        : lastMessage;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PressableCard(
        onTap: () async {
          final conversationIds = List<String>.from(
            conversation['_conversation_ids'] as List? ?? const [],
          );
          await Navigator.push(
            context,
            buildMarketplaceRoute(
              ChatPage(
                conversationId: conversation['id'].toString(),
                conversationIds: conversationIds,
                otherName: sellerName,
                otherAvatarUrl: avatarUrl,
              ),
            ),
          );
          _loadConversations(showLoading: false);
        },
        child: Container(
          decoration: MarketplaceUi.panel(
            color: unread > 0 ? const Color(0xFFF8FAFF) : Colors.white,
            highlighted: unread > 0,
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Stack(
                children: [
                  _buildAvatar(name: sellerName, imageUrl: avatarUrl),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isRecentlyActive
                            ? MarketplaceUi.success
                            : const Color(0xFFD7DEE9),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sellerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: unread > 0
                                  ? FontWeight.w900
                                  : FontWeight.w800,
                              color: MarketplaceUi.textStrong,
                            ),
                          ),
                        ),
                        if (timeText.isNotEmpty)
                          Text(
                            timeText,
                            style: TextStyle(
                              fontSize: 11,
                              color: unread > 0
                                  ? MarketplaceUi.primary
                                  : MarketplaceUi.textSubtle,
                              fontWeight: unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      previewText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: unread > 0
                            ? MarketplaceUi.textStrong
                            : MarketplaceUi.textMuted,
                        fontWeight: unread > 0
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  if (unread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: MarketplaceUi.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 22),
                  const SizedBox(height: 12),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: MarketplaceUi.textSubtle,
                    size: 16,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar({required String name, String? imageUrl}) {
    final initials = name
        .trim()
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .take(2)
        .join()
        .toUpperCase();

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFE7EEFF), Color(0xFFD8E4FF)],
        ),
        border: Border.all(color: const Color(0xFFD6E1FA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null && imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  initials.isEmpty ? 'S' : initials,
                  style: const TextStyle(
                    color: MarketplaceUi.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                initials.isEmpty ? 'S' : initials,
                style: const TextStyle(
                  color: MarketplaceUi.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inDays == 0) {
      final hour = dateTime.hour > 12
          ? dateTime.hour - 12
          : (dateTime.hour == 0 ? 12 : dateTime.hour);
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = dateTime.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    }
    if (diff.inDays == 1) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dateTime.weekday - 1];
    }
    return '${dateTime.month}/${dateTime.day}';
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

    String conversationId;
    if (existing != null) {
      conversationId = existing['id'].toString();
    } else {
      final inserted = await supabase
          .from('conversations')
          .insert({'buyer_id': buyerId, 'seller_id': sellerId})
          .select('id')
          .single();
      conversationId = inserted['id'].toString();
      conversationIds.add(conversationId);
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      buildMarketplaceRoute(
        ChatPage(
          conversationId: conversationId,
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
