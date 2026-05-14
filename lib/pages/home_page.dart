import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/buyer_location_service.dart';
import '../services/cart_badge_service.dart';
import '../services/pickup_preference_service.dart';
import '../utils/helpers.dart';
import '../utils/marketplace_ui.dart' show AppearOnMount, ShimmerBox, staggerDelay;
import '../utils/page_transitions.dart';
import 'cart_page.dart';
import 'orders_page.dart';
import 'productdet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<dynamic> products = [];
  bool isLoading = true;
  String _greetingName = 'Shopper';
  String? _avatarUrl;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  // Active filter chips
  bool _filterOpenNow = false;
  bool _filterDelivery = false;
  String _filterCategory = ''; // empty = all
  double _filterMaxPrice = 0; // 0 = no cap
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _banners = [];
  late final PageController _bannerController;
  int _activeBannerIndex = 0;
  Timer? _bannerAutoplay;
  RealtimeChannel? _notifChannel;
  final Set<String> _seenNotifIds = {};

  TimeOfDay _parsePickupTime(String time) {
    final normalized = time.trim().toLowerCase();
    if (normalized.contains('morning')) return const TimeOfDay(hour: 9, minute: 0);
    if (normalized.contains('afternoon')) return const TimeOfDay(hour: 14, minute: 0);
    if (normalized.contains('evening')) return const TimeOfDay(hour: 18, minute: 0);
    if (normalized.contains('all day') || normalized.contains('tomorrow')) {
      return const TimeOfDay(hour: 10, minute: 0);
    }
    try {
      final parts = time.split(' ');
      final hm = parts[0].split(':');
      int hour = int.parse(hm[0]);
      final minute = int.parse(hm[1]);
      final isPm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
      if (isPm && hour != 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return TimeOfDay.now();
    }
  }

  String _formatPickupTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  @override
  void initState() {
    super.initState();
    _bannerController = PageController(viewportFraction: 0.96);
    _searchFocusNode.addListener(_handleSearchFocusChange);
    CartBadgeService.instance.ensureInitialized();
    PickupPreferenceService.instance.ensureInitialized();
    // Warm the buyer-location cache early so opening a store map renders
    // the route polyline on the very first frame instead of after a network
    // round-trip.
    BuyerLocationService.instance.getPoint();
    _ensureProfile();
    _loadGreetingName();
    fetchProducts();
    _fetchNotifications();
    _fetchBanners();
    _subscribeToNotifications();
  }

  void _subscribeToNotifications() {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    _notifChannel?.unsubscribe();
    _notifChannel = client
        .channel('public:notifications:user_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final id = row['id']?.toString();
            if (id == null || _seenNotifIds.contains(id)) return;
            _seenNotifIds.add(id);
            if (mounted) {
              setState(() => _notifications.insert(0, row));
              _showNotificationToast(row);
            }
          },
        )
        ..subscribe();
  }

  void _showNotificationToast(Map<String, dynamic> n) {
    if (!mounted) return;
    final title = (n['title']?.toString().trim().isNotEmpty == true)
        ? n['title'].toString()
        : _notifTitle(n['type']?.toString() ?? '');
    final message = n['message']?.toString() ?? '';
    final accent = _notifColor(n['type']?.toString() ?? '');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _notifIcon(n['type']?.toString() ?? ''),
                  color: accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Colors.white,
                      ),
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFE5E7EB),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () => _handleNotificationTap(n),
          ),
        ),
      );
  }

  void _handleSearchFocusChange() {
    if (mounted) setState(() {});
  }

  Future<void> _ensureProfile() async {
    await ensureOwnProfileRow(Supabase.instance.client);
  }

  Future<void> _showPickupWindowSheet() async {
    final current = PickupPreferenceService.instance.currentValue;
    final initial = _parsePickupTime(current);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Preferred pickup time',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null) return;
    await PickupPreferenceService.instance.save(_formatPickupTime(picked));
  }

  @override
  void dispose() {
    _bannerAutoplay?.cancel();
    _bannerController.dispose();
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _notifChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> n) async {
    final id = n['id']?.toString();
    final type = n['type']?.toString() ?? '';

    // Mark this notification as read.
    if (id != null && id.isNotEmpty && n['is_read'] != true) {
      try {
        await Supabase.instance.client
            .from('notifications')
            .update({'is_read': true})
            .eq('id', id);
        if (mounted) {
          setState(() {
            final i = _notifications.indexWhere((x) => x['id']?.toString() == id);
            if (i >= 0) _notifications[i] = {..._notifications[i], 'is_read': true};
          });
        }
      } catch (_) {}
    }

    if (!mounted) return;

    // Order-related notifications open the Orders page.
    const orderTypes = {
      'order_placed',
      'order_pending_payment',
      'order_accepted',
      'order_ready',
      'order_out_for_delivery',
      'order_completed',
      'order_declined',
      'order_cancelled',
      'payment_received',
    };
    if (orderTypes.contains(type)) {
      Navigator.of(context).pop(); // close the notifications sheet
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OrdersPage()),
      );
    }
  }

  Future<void> _fetchNotifications() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      final resp = await client
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(20);
      if (mounted) {
        final rows = List<Map<String, dynamic>>.from(resp);
        // Seed seen IDs so existing rows don't trigger a popup when the
        // realtime channel first connects.
        _seenNotifIds
          ..clear()
          ..addAll(rows
              .map((r) => r['id']?.toString())
              .whereType<String>());
        setState(() => _notifications = rows);
      }
    } catch (_) {
      // notifications table may not exist yet
    }
  }

  Future<void> _fetchBanners() async {
    try {
      final resp = await Supabase.instance.client
          .from('seller_profiles')
          .select(
            'user_id, store_name, banner_url, logo_url, category, opening_time, closing_time, is_open, delivery_enabled, created_at',
          )
          .not('banner_url', 'is', null)
          .eq('approval_status', 'approved')
          .order('created_at', ascending: false)
          .limit(10);
      if (mounted) {
        setState(() => _banners = List<Map<String, dynamic>>.from(resp));
        _restartBannerAutoplay();
      }
    } catch (_) {
      // banner_url column may not exist yet
    }
  }

  void _restartBannerAutoplay() {
    _bannerAutoplay?.cancel();
    if (_banners.length < 2) return;
    _bannerAutoplay = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _banners.isEmpty || !_bannerController.hasClients) {
        return;
      }
      final next = (_activeBannerIndex + 1) % _banners.length;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8F9FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── Handle + header ──
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.notifications_rounded,
                            size: 22,
                            color: Color(0xFF2A4BA0),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Notifications',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_notifications.any((n) => n['is_read'] != true))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A4BA0),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_notifications.where((n) => n['is_read'] != true).length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (_notifications.any((n) => n['is_read'] != true))
                            TextButton(
                              onPressed: () async {
                                final client = Supabase.instance.client;
                                final user = client.auth.currentUser;
                                if (user == null) return;
                                try {
                                  await client
                                      .from('notifications')
                                      .update({'is_read': true})
                                      .eq('user_id', user.id);
                                  _fetchNotifications();
                                } catch (_) {}
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                foregroundColor: const Color(0xFF2A4BA0),
                              ),
                              child: const Text(
                                'Mark all read',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ── List ──
              Expanded(
                child: _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 52,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No notifications yet',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Order updates will appear here',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: _notifications.length,
                        itemBuilder: (context, i) {
                          final n = _notifications[i];
                          final isRead = n['is_read'] == true;
                          final type = n['type']?.toString() ?? '';
                          final message = n['message']?.toString() ?? '';
                          final title =
                              n['title']?.toString().isNotEmpty == true
                              ? n['title'].toString()
                              : _notifTitle(type);
                          final accent = _notifColor(type);

                          // Date label grouping
                          String dateLabel = '';
                          String timeStr = '';
                          try {
                            final dt = DateTime.parse(
                              n['created_at'].toString(),
                            ).toLocal();
                            final now = DateTime.now();
                            final today = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            );
                            final yesterday = today.subtract(
                              const Duration(days: 1),
                            );
                            final dtDay = DateTime(dt.year, dt.month, dt.day);
                            if (dtDay == today) {
                              dateLabel = 'Today';
                            } else if (dtDay == yesterday) {
                              dateLabel = 'Yesterday';
                            } else {
                              dateLabel = '${_monthName(dt.month)} ${dt.day}';
                            }
                            final h = dt.hour == 0
                                ? 12
                                : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
                            final amPm = dt.hour >= 12 ? 'PM' : 'AM';
                            timeStr =
                                '$h:${dt.minute.toString().padLeft(2, '0')} $amPm';
                          } catch (_) {}

                          // Show date separator when date changes
                          final showSeparator =
                              i == 0 ||
                              (() {
                                try {
                                  final prev = DateTime.parse(
                                    _notifications[i - 1]['created_at']
                                        .toString(),
                                  ).toLocal();
                                  final curr = DateTime.parse(
                                    n['created_at'].toString(),
                                  ).toLocal();
                                  return DateTime(
                                        prev.year,
                                        prev.month,
                                        prev.day,
                                      ) !=
                                      DateTime(curr.year, curr.month, curr.day);
                                } catch (_) {
                                  return false;
                                }
                              })();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showSeparator && dateLabel.isNotEmpty) ...[
                                if (i != 0) const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: Colors.grey[300],
                                          height: 1,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        child: Text(
                                          dateLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey[500],
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: Colors.grey[300],
                                          height: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isRead
                                      ? Colors.white
                                      : const Color(0xFFF0F4FF),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isRead
                                        ? const Color(0xFFEEF0F5)
                                        : accent.withValues(alpha: 0.3),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x08000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _handleNotificationTap(n),
                                    child: IntrinsicHeight(
                                      child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Left accent bar
                                      Container(
                                        width: 4,
                                        decoration: BoxDecoration(
                                          color: isRead
                                              ? Colors.transparent
                                              : accent,
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(14),
                                            bottomLeft: Radius.circular(14),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            12,
                                            12,
                                            12,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Icon bubble
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: accent.withValues(
                                                    alpha: 0.12,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Icon(
                                                  _notifIcon(type),
                                                  color: accent,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              // Text content
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            title,
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontSize: 14,
                                                              color: isRead
                                                                  ? const Color(
                                                                      0xFF6B7280,
                                                                    )
                                                                  : const Color(
                                                                      0xFF111827,
                                                                    ),
                                                            ),
                                                          ),
                                                        ),
                                                        if (timeStr
                                                            .isNotEmpty) ...[
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Text(
                                                            timeStr,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: Colors
                                                                  .grey[400],
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ],
                                                        if (!isRead) ...[
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Container(
                                                            width: 8,
                                                            height: 8,
                                                            margin:
                                                                const EdgeInsets.only(
                                                                  top: 4,
                                                                ),
                                                            decoration:
                                                                BoxDecoration(
                                                                  color: accent,
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                    if (message.isNotEmpty) ...[
                                                      const SizedBox(height: 5),
                                                      Text(
                                                        message,
                                                        style: const TextStyle(
                                                          fontSize: 13,
                                                          color: Color(
                                                            0xFF4B5563,
                                                          ),
                                                          height: 1.4,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthName(int month) {
    const names = [
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
    return names[(month - 1).clamp(0, 11)];
  }

  String _notifTitle(String type) {
    switch (type) {
      case 'seller_approved':
        return 'Seller Approved';
      case 'seller_rejected':
        return 'Application Denied';
      case 'order_placed':
        return 'New Order';
      case 'order_ready':
        return 'Order Ready';
      default:
        return 'Notification';
    }
  }

  IconData _notifIcon(String type) {
    switch (type) {
      case 'seller_approved':
        return Icons.verified_rounded;
      case 'seller_rejected':
        return Icons.cancel_rounded;
      case 'order_placed':
        return Icons.shopping_bag_rounded;
      case 'order_ready':
        return Icons.check_circle_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _notifColor(String type) {
    switch (type) {
      case 'seller_approved':
        return const Color(0xFF059669);
      case 'seller_rejected':
        return const Color(0xFFDC2626);
      case 'order_placed':
        return const Color(0xFF2A4BA0);
      case 'order_ready':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Future<void> _loadGreetingName() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) return;

    String? name;

    String? avatar;

    try {
      final profile = await client
          .from('profile')
          .select('name, avatar_url')
          .eq('user_id', user.id)
          .maybeSingle();

      final profileName = profile?['name']?.toString().trim();
      if (profileName != null && profileName.isNotEmpty) {
        name = profileName;
      }
      final profileAvatar = profile?['avatar_url']?.toString().trim();
      if (profileAvatar != null && profileAvatar.isNotEmpty) {
        avatar = profileAvatar;
      }
    } catch (_) {
      // Fall back to auth metadata/email when profile row is unavailable.
    }

    name ??=
        user.userMetadata?['name']?.toString().trim() ??
        user.userMetadata?['full_name']?.toString().trim();

    avatar ??= user.userMetadata?['avatar_url']?.toString().trim();

    final emailPrefix = user.email?.split('@').first.trim();
    if ((name == null || name.isEmpty) &&
        emailPrefix != null &&
        emailPrefix.isNotEmpty) {
      name = emailPrefix;
    }

    if (!mounted) return;
    if (name == null || name.isEmpty) {
      if (avatar != null && avatar.isNotEmpty && _avatarUrl != avatar) {
        setState(() => _avatarUrl = avatar);
      }
      return;
    }

    setState(() {
      _greetingName = _formatDisplayName(name!);
      _avatarUrl = avatar;
    });
  }

  String _formatDisplayName(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }

  /// Filters out products whose seller has been suspended (or rejected) by an
  /// admin. Products with no joined `seller_profiles` row are kept so legacy
  /// listings don't silently disappear.
  List<dynamic> _hideSuspendedSellerProducts(dynamic raw) {
    final list = raw is List ? raw : const <dynamic>[];
    return list.where((item) {
      if (item is! Map) return true;
      final sp = item['seller_profiles'];
      if (sp is! Map) return true;
      final status = sp['approval_status']?.toString().toLowerCase();
      return status != 'suspended' && status != 'rejected';
    }).toList();
  }

  Future<void> fetchProducts() async {
    if (mounted) {
      setState(() => isLoading = true);
    }

    try {
      // Join with seller_profiles so we can hide products whose seller has
      // been suspended by an admin. We also surface store name + hours +
      // delivery flag for the cards.
      final response = await Supabase.instance.client
          .from('product')
          .select(
            '*, seller_profiles!product_seller_id_fkey(store_name, is_open, opening_time, closing_time, delivery_enabled, approval_status)',
          )
          .order('id', ascending: false);

      if (!mounted) return;
      setState(() {
        products = _hideSuspendedSellerProducts(response);
        isLoading = false;
      });
    } catch (e) {
      // Fallback: try without the join in case FK doesn't exist yet
      debugPrint("FETCH WITH JOIN FAILED → $e — retrying plain select");
      try {
        final response = await Supabase.instance.client
            .from('product')
            .select()
            .order('id', ascending: false);

        if (!mounted) return;
        setState(() {
          products = response;
          isLoading = false;
        });
      } catch (e2) {
        debugPrint("FETCH ERROR → $e2");
        if (!mounted) return;
        setState(() => isLoading = false);
      }
    }
  }

  List<dynamic> _productsForFilter() {
    final List<Map<String, dynamic>> normalized = _normalizedProducts();

    // Apply search query first
    List<Map<String, dynamic>> results = normalized;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      results = normalized.where((p) {
        final name = (p['product_name'] ?? '').toString().toLowerCase();
        final store = (p['store_name'] ?? '').toString().toLowerCase();
        final cat = (p['category'] ?? '').toString().toLowerCase();
        final desc = (p['description'] ?? '').toString().toLowerCase();
        return name.contains(q) ||
            store.contains(q) ||
            cat.contains(q) ||
            desc.contains(q);
      }).toList();
    }

    // Filter chips
    if (_filterOpenNow) results = results.where(_isShopOpen).toList();
    if (_filterDelivery) {
      results = results.where((p) => p['delivery_enabled'] == true).toList();
    }
    if (_filterCategory.isNotEmpty) {
      results = results
          .where(
            (p) =>
                (p['category'] ?? '').toString().toLowerCase() ==
                _filterCategory.toLowerCase(),
          )
          .toList();
    }
    if (_filterMaxPrice > 0) {
      results = results.where((p) {
        final price = double.tryParse(p['price']?.toString() ?? '') ?? 0;
        return price <= _filterMaxPrice;
      }).toList();
    }

    return results;
  }

  List<Map<String, dynamic>> _normalizedProducts() {
    final List<Map<String, dynamic>> combined = [];

    for (final item in products) {
      final raw = Map<String, dynamic>.from(item as Map);

      // Extract joined seller_profiles data
      String storeName = 'Market Stall';
      bool sellerIsOpen = false;
      String sellerOpenTime = '05:00';
      String sellerCloseTime = '19:00';
      final joined = raw['seller_profiles'];
      bool sellerDeliveryEnabled = false;
      if (joined is Map) {
        if (joined['store_name'] != null) {
          storeName = joined['store_name'].toString();
        }
        sellerIsOpen = joined['is_open'] == true;
        sellerOpenTime = joined['opening_time']?.toString() ?? '05:00';
        sellerCloseTime = joined['closing_time']?.toString() ?? '19:00';
        sellerDeliveryEnabled = joined['delivery_enabled'] == true;
      }

      combined.add({
        'product_name': (raw['name'] ?? raw['product_name'] ?? 'Fresh Item')
            .toString(),
        'store_name': storeName,
        'price': raw['price'] ?? 0,
        'image_url':
            (raw['image_url'] != null &&
                raw['image_url'].toString().trim().isNotEmpty)
            ? raw['image_url'].toString()
            : '', // empty = show placeholder
        'category': (raw['category'] ?? '').toString(),
        'unit_type': (raw['unit_type'] ?? 'Kg').toString(),
        'id': raw['id'],
        'seller_id': raw['seller_id'] ?? raw['user_id'],
        'description': (raw['description'] ?? '').toString(),
        'is_db': true,
        'seller_is_open': sellerIsOpen,
        'opening_time': sellerOpenTime,
        'closing_time': sellerCloseTime,
        'delivery_enabled': sellerDeliveryEnabled,
        'product_type': (raw['product_type'] ?? 'retail').toString(),
        'pricing_basis': (raw['pricing_basis'] ?? '').toString(),
        'prep_time': (raw['prep_time'] ?? '').toString(),
        'variants': (raw['variants'] ?? '').toString(),
        'daily_available': raw['daily_available'] ?? true,
        'image_urls': raw['image_urls'],
        'retail_price': raw['retail_price'],
      });
    }

    return combined;
  }

  String _productName(dynamic product, [String fallback = 'Fresh Item']) {
    final value = product['product_name']?.toString().trim();
    if (value == null || value.isEmpty) return fallback;
    return value;
  }

  String _storeName(dynamic product, [String fallback = 'San Fernando Stall']) {
    final value = product['store_name']?.toString().trim();
    if (value == null || value.isEmpty) return fallback;
    return value;
  }

  String _categoryLabel(dynamic product) {
    final raw = product['category']?.toString().trim() ?? '';
    if (raw.isNotEmpty) return raw;
    final productType = product['product_type']?.toString();
    if (productType == 'karinderya') return 'Karinderya';
    return '';
  }

  Color? _categoryColor(String label) {
    switch (label.toLowerCase()) {
      case 'fish':
        return const Color(0xFF3D5BBD);
      case 'meat':
      case 'meats':
        return const Color(0xFFC45C36);
      case 'vegetable':
      case 'vegetables':
        return const Color(0xFF42A815);
      case 'fruit':
      case 'fruits':
        return const Color(0xFFD8E40F);
      case 'karinderya':
        return const Color(0xFFCB8425);
      case 'apparel':
        return const Color(0xFF0E2E39);
      default:
        return null;
    }
  }

  /// Returns true if the seller's shop is currently open (manual toggle + within hours)
  bool _isShopOpen(dynamic product) {
    if (product['is_db'] != true) {
      return true; // fallback products are always "open"
    }
    final isOpen = product['seller_is_open'] == true;
    if (!isOpen) return false;
    try {
      final now = TimeOfDay.now();
      final openParts = (product['opening_time'] ?? '05:00').toString().split(
        ':',
      );
      final closeParts = (product['closing_time'] ?? '19:00').toString().split(
        ':',
      );
      final openMin = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
      final closeMin = int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
      final nowMin = now.hour * 60 + now.minute;
      return nowMin >= openMin && nowMin <= closeMin;
    } catch (_) {
      return isOpen;
    }
  }

  int _todayPickScore(dynamic product) {
    var score = 0;
    if (_isShopOpen(product)) score += 5;
    if (product['delivery_enabled'] == true) score += 2;
    final imageUrl = product['image_url']?.toString().trim() ?? '';
    if (imageUrl.isNotEmpty) score += 1;
    final price = double.tryParse(product['price']?.toString() ?? '') ?? 0;
    if (price > 0 && price <= 250) score += 1;
    return score;
  }

  void _openCart() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartPage()),
    );
  }

  Widget _buildOpenClosedBadge(dynamic product) {
    if (product['is_db'] != true) return const SizedBox.shrink();
    final open = _isShopOpen(product);
    final openTime = (product['opening_time'] ?? '05:00').toString();
    final closeTime = (product['closing_time'] ?? '19:00').toString();
    String label;
    Color color;
    if (open) {
      color = const Color(0xFF059669);
      label = 'Open · Closes ${to12Hour(closeTime)}';
    } else {
      color = const Color(0xFFDC2626);
      label = 'Closed · Opens ${to12Hour(openTime)}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDeliveryBadge(dynamic product) {
    if (product['is_db'] != true) return const SizedBox.shrink();
    final delivery = product['delivery_enabled'] == true;
    final color = delivery
        ? const Color(0xFF2A4BA0)
        : const Color(0xFFB45309);
    final icon =
        delivery ? Icons.delivery_dining_rounded : Icons.storefront_rounded;
    final label = delivery ? 'Delivery' : 'Pickup only';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayPickMetaRow(dynamic product) {
    final open = _isShopOpen(product);
    final openTime = (product['opening_time'] ?? '05:00').toString();
    final closeTime = (product['closing_time'] ?? '19:00').toString();
    final deliveryEnabled = product['delivery_enabled'] == true;
    final statusColor = open
        ? const Color(0xFF059669)
        : const Color(0xFFDC2626);
    final statusLabel = open
        ? 'Open till ${to12Hour(closeTime)}'
        : 'Opens ${to12Hour(openTime)}';

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 12, color: statusColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _FulfillmentChip(deliveryEnabled: deliveryEnabled),
      ],
    );
  }

  void _openProductDetail(dynamic product) {
    Navigator.push(
      context,
      fadeSlideRoute(
        (_) => ProductViewPage(product: Map<String, dynamic>.from(product)),
      ),
    );
  }

  void _showAddMessage(String productName) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$productName added to cart')));
  }

  Future<void> _addToCart(dynamic product) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    final productName = _productName(product, 'Fresh Item');
    final price = product['price'];
    final sellerId = product['seller_id']?.toString();
    final productId = product['id']?.toString();
    final imageUrl = product['image_url']?.toString();
    final storeName = _storeName(product, 'Market Stall');
    final unitType = (product['unit_type'] ?? 'kg').toString();

    if (sellerId != null && sellerId == user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You can't order from your own shop."),
        ),
      );
      return;
    }

    try {
      Map<String, dynamic>? existing;
      if (productId != null && productId.isNotEmpty) {
        var query = client
            .from('cart')
            .select('id, qty')
            .eq('buyer_id', user.id)
            .eq('product_id', productId);
        if (sellerId != null && sellerId.isNotEmpty) {
          query = query.eq('seller_id', sellerId);
        }
        existing = await query.maybeSingle();
      }

      if (existing == null) {
        var fallback = client
            .from('cart')
            .select('id, qty')
            .eq('buyer_id', user.id)
            .eq('product_name', productName);
        if (sellerId != null && sellerId.isNotEmpty) {
          fallback = fallback.eq('seller_id', sellerId);
        }
        existing = await fallback.maybeSingle();
      }

      if (existing != null) {
        final currentQty = int.tryParse(existing['qty'].toString()) ?? 1;
        await client
            .from('cart')
            .update({'qty': currentQty + 1})
            .eq('id', existing['id']);
      } else {
        await client.from('cart').insert({
          'product_name': productName,
          'price': price,
          'qty': 1,
          'buyer_id': user.id,
          'seller_id': sellerId,
          'product_id': productId,
          'image_url': imageUrl,
          'store_name': storeName,
          'unit_type': unitType,
        });
      }

      if (!mounted) return;
      _showAddMessage(productName);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Database error: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildFilterBar() {
    final allNorm = _normalizedProducts();
    final categories =
        allNorm
            .map((p) => (p['category'] ?? '').toString().trim())
            .where((category) => category.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final bool anyActive =
        _filterOpenNow ||
        _filterDelivery ||
        _filterCategory.isNotEmpty ||
        _filterMaxPrice > 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (anyActive)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: const Text('Clear'),
                avatar: const Icon(
                  Icons.restart_alt_rounded,
                  size: 16,
                  color: Color(0xFF2A4BA0),
                ),
                onPressed: () {
                  setState(() {
                    _filterOpenNow = false;
                    _filterDelivery = false;
                    _filterCategory = '';
                    _filterMaxPrice = 0;
                  });
                },
                backgroundColor: const Color(0xFFEAF0FF),
                labelStyle: const TextStyle(
                  color: Color(0xFF2A4BA0),
                  fontWeight: FontWeight.w700,
                ),
                side: const BorderSide(color: Color(0xFFD7E2FF)),
              ),
            ),
          FilterChip(
            label: const Text('Open now'),
            selected: _filterOpenNow,
            onSelected: (value) => setState(() => _filterOpenNow = value),
            selectedColor: const Color(0xFF059669).withValues(alpha: 0.12),
            checkmarkColor: const Color(0xFF059669),
            labelStyle: TextStyle(
              color: _filterOpenNow
                  ? const Color(0xFF065F46)
                  : const Color(0xFF374151),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            side: BorderSide(
              color: _filterOpenNow
                  ? const Color(0xFF059669)
                  : Colors.grey.shade300,
            ),
          ),
          const SizedBox(width: 6),
          FilterChip(
            label: const Text('Delivery'),
            selected: _filterDelivery,
            onSelected: (value) => setState(() => _filterDelivery = value),
            selectedColor: const Color(0xFF153075).withValues(alpha: 0.12),
            checkmarkColor: const Color(0xFF153075),
            labelStyle: TextStyle(
              color: _filterDelivery
                  ? const Color(0xFF153075)
                  : const Color(0xFF374151),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            side: BorderSide(
              color: _filterDelivery
                  ? const Color(0xFF2A4BA0)
                  : Colors.grey.shade300,
            ),
          ),
          const SizedBox(width: 6),
          ...([100.0, 250.0, 500.0].map((cap) {
            final selected = _filterMaxPrice == cap;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text('Under ₱${cap.toInt()}'),
                selected: selected,
                onSelected: (value) =>
                    setState(() => _filterMaxPrice = value ? cap : 0),
                selectedColor: const Color(0xFFF9B023).withValues(alpha: 0.2),
                checkmarkColor: const Color(0xFF92620A),
                labelStyle: TextStyle(
                  color: selected
                      ? const Color(0xFF92620A)
                      : const Color(0xFF374151),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected
                      ? const Color(0xFFF9B023)
                      : Colors.grey.shade300,
                ),
              ),
            );
          })),
          ...categories.map((category) {
            final selected = _filterCategory == category;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(category),
                selected: selected,
                onSelected: (value) =>
                    setState(() => _filterCategory = value ? category : ''),
                selectedColor: const Color(0xFF153075).withValues(alpha: 0.12),
                checkmarkColor: const Color(0xFF153075),
                labelStyle: TextStyle(
                  color: selected
                      ? const Color(0xFF153075)
                      : const Color(0xFF374151),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected
                      ? const Color(0xFF153075)
                      : Colors.grey.shade300,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTopHeader() {
    final searchFocused = _searchFocusNode.hasFocus;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A4BA0), Color(0xFF153075)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    _buildGreetingAvatar(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Welcome back',
                            style: TextStyle(
                              color: Color(0xFFC9D4F2),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Hey, $_greetingName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: _showNotificationsSheet,
                    child: Stack(
                      children: [
                        const Icon(
                          Icons.notifications_none_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        if (_notifications.any((n) => n['is_read'] != true))
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 16,
                              height: 16,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF5A524),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${_notifications.where((n) => n['is_read'] != true).length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: _openCart,
                    child: ValueListenableBuilder<int>(
                      valueListenable: CartBadgeService.instance.count,
                      builder: (context, cartCount, _) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(
                              Icons.shopping_cart_outlined,
                              color: Colors.white,
                              size: 28,
                            ),
                            if (cartCount > 0)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF5A524),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$cartCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Search the plaza',
            style: TextStyle(
              color: Color(0xFFDCE6FF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: searchFocused
                  ? const Color(0x40FFFFFF)
                  : const Color(0x2EFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: searchFocused
                    ? const Color(0xB3FFFFFF)
                    : const Color(0x42FFFFFF),
                width: searchFocused ? 1.4 : 1,
              ),
              boxShadow: searchFocused
                  ? const [
                      BoxShadow(
                        color: Color(0x33264FB2),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (value) {
                setState(() => _searchQuery = value.trim());
              },
              decoration: InputDecoration(
                hintText: 'Search products or store',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFFF8FAFF),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Color(0xFFE8EEFF),
                          size: 20,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : const Icon(
                        Icons.tune_rounded,
                        color: Color(0xFFC9D6FB),
                        size: 20,
                      ),
                filled: true,
                fillColor: Colors.transparent,
                hintStyle: const TextStyle(
                  color: Color(0xD9F3F6FF),
                  fontWeight: FontWeight.w500,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInfoPill(
                  label: 'PICK UP',
                  value: 'San Fernando Market Plaza',
                  icon: Icons.location_on_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _showPickupWindowSheet,
                  child: ValueListenableBuilder<String>(
                    valueListenable:
                        PickupPreferenceService.instance.preferredPickup,
                    builder: (context, pickupWindow, _) => _buildInfoPill(
                      label: 'WITHIN',
                      value: pickupWindow,
                      icon: Icons.schedule_outlined,
                      isInteractive: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_banners.isNotEmpty)
            Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5A524).withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFF5A524).withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFCB6B),
                            size: 13,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'FEATURED',
                            style: TextStyle(
                              color: Color(0xFFFFD99A),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Featured Stores',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    Text(
                      '${_banners.length}',
                      style: const TextStyle(
                        color: Color(0xFFC9D4F2),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 130,
                  child: PageView.builder(
                    itemCount: _banners.length,
                    controller: _bannerController,
                    padEnds: false,
                    onPageChanged: (index) {
                      if (mounted) setState(() => _activeBannerIndex = index);
                    },
                    itemBuilder: (context, index) {
                      final banner = _banners[index];
                      final storeName = banner['store_name'] ?? 'Store';
                      final bannerUrl = banner['banner_url'] as String?;
                      final logoUrl = banner['logo_url'] as String?;
                      final category = banner['category'] ?? '';
                      final isOpen = banner['is_open'] == true;
                      final openTime =
                          banner['opening_time']?.toString() ?? '05:00';
                      final closeTime =
                          banner['closing_time']?.toString() ?? '19:00';
                      final deliveryEnabled =
                          banner['delivery_enabled'] == true;
                      bool isWithinHours = false;
                      try {
                        final now = TimeOfDay.now();
                        final openParts = openTime.split(':');
                        final closeParts = closeTime.split(':');
                        final openMinutes =
                            int.parse(openParts[0]) * 60 +
                            int.parse(openParts[1]);
                        final closeMinutes =
                            int.parse(closeParts[0]) * 60 +
                            int.parse(closeParts[1]);
                        final nowMinutes = now.hour * 60 + now.minute;
                        isWithinHours =
                            nowMinutes >= openMinutes &&
                            nowMinutes <= closeMinutes;
                      } catch (_) {}
                      final shopOpen = isOpen && isWithinHours;

                      return AnimatedScale(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        scale: _activeBannerIndex == index ? 1 : 0.97,
                        child: Container(
                          margin: EdgeInsets.only(
                            right: index == _banners.length - 1 ? 0 : 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: const Color(0xFF2A4BA0),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x260F172A),
                                blurRadius: 16,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (bannerUrl != null)
                                Image.network(
                                  bannerUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox(),
                                ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.65),
                                      Colors.black.withValues(alpha: 0.1),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    if (logoUrl != null)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: Image.network(
                                            logoUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                Container(
                                                  color: Colors.white24,
                                                  child: const Icon(
                                                    Icons.storefront,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: Colors.white24,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.storefront,
                                          color: Colors.white,
                                        ),
                                      ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            storeName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w900,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          if (category.toString().isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white24,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                category.toString(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: shopOpen
                                                      ? const Color(0xFF059669)
                                                      : const Color(0xFFDC2626),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.circle,
                                                      size: 7,
                                                      color: Colors.white,
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      shopOpen
                                                          ? 'Open'
                                                          : 'Closed',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${to12Hour(openTime)} – ${to12Hour(closeTime)}',
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              if (deliveryEnabled) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 7,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white24,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .delivery_dining_rounded,
                                                        size: 11,
                                                        color: Colors.white,
                                                      ),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'Delivery',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_banners.length, (index) {
                    final isActive = _activeBannerIndex == index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: double.infinity,
              height: 130,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/img/categories/Marketplaza.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        Container(color: const Color(0xFFF5A524)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.60),
                          Colors.black.withValues(alpha: 0.10),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'San Fernando Market Plaza',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Fresh goods from local public market stalls',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
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

  Widget _buildGreetingAvatar() {
    final url = _avatarUrl;
    final initials = _greetingName.trim().isEmpty
        ? '?'
        : _greetingName.trim()[0].toUpperCase();
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: (url != null && url.isNotEmpty)
          ? Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _avatarFallback(initials),
              errorBuilder: (_, _, _) => _avatarFallback(initials),
            )
          : _avatarFallback(initials),
    );
  }

  Widget _avatarFallback(String initials) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildInfoPill({
    required String label,
    required String value,
    required IconData icon,
    bool isInteractive = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isInteractive
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInteractive
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (isInteractive) ...[
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white70,
              size: 12,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String subtitle, {
    String? eyebrow,
    VoidCallback? onSeeAll,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7EEFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    eyebrow,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Color(0xFF2A4BA0),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.02,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2A4BA0),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE5EAF5)),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('See all', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
      ],
    );
  }

  void _openFullProductList(String title, List<dynamic> products) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _HomeProductsListPage(
          title: title,
          products: products,
          onTapProduct: _openProductDetail,
          onAddToCart: _addToCart,
          productNameOf: (p) => _productName(p, 'Fresh Item'),
          storeNameOf: (p) => _storeName(p, 'Market Stall'),
          categoryLabelOf: _categoryLabel,
          categoryColorOf: _categoryColor,
          isShopOpenOf: _isShopOpen,
        ),
      ),
    );
  }

  Widget _buildTodayPickCard(dynamic product) {
    final imageUrl = (product['image_url'] as String?)?.trim() ?? '';
    final resolvedImage = imageUrl;
    final priceValue = product['price'];
    final unit = (product['unit_type'] ?? 'kg').toString();
    final priceText = priceValue != null ? '₱$priceValue /$unit' : '₱0';
    final isOpen = _isShopOpen(product);
    final categoryLabel = _categoryLabel(product);

    return SizedBox(
      width: 244,
      child: PressableCard(
        onTap: () => _openProductDetail(product),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          margin: const EdgeInsets.only(right: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE8EDF6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: SizedBox(
                  height: 112,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildProductImage(resolvedImage),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.05),
                              Colors.black.withValues(alpha: 0.28),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7B731),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'TODAY\'S PICK',
                            style: TextStyle(
                              color: Color(0xFF6A4700),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: isOpen
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isOpen ? 'Open now' : 'Closed',
                                style: TextStyle(
                                  color: isOpen
                                      ? const Color(0xFF065F46)
                                      : const Color(0xFF991B1B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _productName(product, 'Market Product'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        if (categoryLabel.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          CategoryPill(
                            label: categoryLabel,
                            color: _categoryColor(categoryLabel),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.store_mall_directory_outlined,
                          size: 13,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            _storeName(product, 'Market Stall'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildTodayPickMetaRow(product),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            priceText,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF153075),
                            ),
                          ),
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A4BA0),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x332A4BA0),
                                blurRadius: 12,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEssentialsGrid(List<dynamic> filteredProducts) {
    if (filteredProducts.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Scale up to 3+ columns on tablets/desktop so cards stay readable
        // without becoming oversized on wide layouts.
        final crossAxisCount = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 540
                ? 3
                : 2;
        const gridSpacing = 12.0;
        final cardWidth =
            (constraints.maxWidth - gridSpacing * (crossAxisCount - 1)) /
                crossAxisCount;
        final compactCard = cardWidth < 190;
        final ultraCompactCard = cardWidth < 170;
        final imageHeight = ultraCompactCard
            ? 100.0
            : (compactCard ? 106.0 : 114.0);
        final horizontalPadding = compactCard ? 10.0 : 12.0;
        final topPadding = compactCard ? 8.0 : 10.0;
        final bottomPadding = compactCard ? 10.0 : 12.0;
        final titleFontSize = compactCard ? 13.0 : 14.0;
        final storeFontSize = compactCard ? 11.0 : 12.0;
        final sectionGap = compactCard ? 6.0 : 8.0;
        final priceFontSize = compactCard ? 13.0 : 14.0;
        final addButtonSize = compactCard ? 32.0 : 34.0;
        final addIconSize = compactCard ? 16.0 : 18.0;
        final cardHeight = ultraCompactCard
            ? 254.0
            : (compactCard ? 264.0 : 260.0);

        return GridView.builder(
          itemCount: filteredProducts.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: gridSpacing,
            mainAxisSpacing: 12,
            mainAxisExtent: cardHeight,
          ),
          itemBuilder: (context, index) {
            final product = filteredProducts[index];
            final resolvedImage =
                (product['image_url'] as String?)?.trim() ?? '';
            final priceValue = product['price'];
            final unit = (product['unit_type'] ?? 'kg').toString();
            final priceText = priceValue != null ? '₱$priceValue /$unit' : '₱0';
            final categoryLabel = _categoryLabel(product);

            return AppearOnMount(
              delay: staggerDelay(index, step: 40, maxMs: 320),
              child: PressableCard(
              onTap: () => _openProductDetail(product),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE8EDF6)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: imageHeight,
                        child: _buildProductImage(resolvedImage),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          topPadding,
                          horizontalPadding,
                          bottomPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _productName(product, 'Fresh Item'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: titleFontSize,
                                      height: 1.15,
                                      color: const Color(0xFF111827),
                                    ),
                                  ),
                                ),
                                if (categoryLabel.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  CategoryPill(
                                    label: categoryLabel,
                                    color: _categoryColor(categoryLabel),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _storeName(product, 'Market Stall'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: storeFontSize,
                                color: const Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: sectionGap),
                            _buildOpenClosedBadge(product),
                            const SizedBox(height: 4),
                            _buildDeliveryBadge(product),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    priceText,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF111827),
                                      fontSize: priceFontSize,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _addToCart(product),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: addButtonSize,
                                    height: addButtonSize,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF2A4BA0),
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(12),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.add_rounded,
                                      color: Colors.white,
                                      size: addIconSize,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _todayPickShimmerRow() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: 4,
      itemBuilder: (context, _) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: SizedBox(
          width: 244,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(
                height: 112,
                width: double.infinity,
                borderRadius: BorderRadius.circular(20),
              ),
              const SizedBox(height: 12),
              ShimmerBox(
                height: 14,
                width: 160,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 8),
              ShimmerBox(
                height: 12,
                width: 120,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 14),
              ShimmerBox(
                height: 18,
                width: 90,
                borderRadius: BorderRadius.circular(999),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recommendedShimmerRow() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: 4,
      itemBuilder: (context, _) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: SizedBox(
          width: 182,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8EDF6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(
                  height: 112,
                  width: double.infinity,
                  borderRadius: BorderRadius.circular(14),
                ),
                const SizedBox(height: 12),
                ShimmerBox(
                  height: 13,
                  width: 130,
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 8),
                ShimmerBox(
                  height: 11,
                  width: 90,
                  borderRadius: BorderRadius.circular(999),
                ),
                const Spacer(),
                ShimmerBox(
                  height: 16,
                  width: 70,
                  borderRadius: BorderRadius.circular(999),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage(String imagePath) {
    if (imagePath.isEmpty) return _imagePlaceholder();

    if (_isAssetPath(imagePath)) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _imagePlaceholder(),
      );
    }

    return Image.network(
      imagePath,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _imagePlaceholder();
      },
      errorBuilder: (context, error, stackTrace) => _imagePlaceholder(),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFFF1F3F9),
      child: const Center(
        child: Icon(Icons.image_outlined, size: 36, color: Color(0xFFB6BDCC)),
      ),
    );
  }

  bool _isAssetPath(String path) {
    return path.startsWith('assets/') || path.startsWith('images/');
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _productsForFilter();
    final todayPickProducts = [...filteredProducts]
      ..sort((a, b) => _todayPickScore(b).compareTo(_todayPickScore(a)));
    final visibleTodayPicks = todayPickProducts.take(6).toList();
    final recommendedProducts = filteredProducts.take(10).toList();
    final bool hasResults = filteredProducts.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FB),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: fetchProducts,
          color: const Color(0xFF2A4BA0),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            children: [
              _buildTopHeader(),
              const SizedBox(height: 14),
              _buildFilterBar(),
              const SizedBox(height: 10),
              if (!hasResults && !isLoading)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 56,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No products found for "$_searchQuery"'
                            : 'No products available yet.\nCheck back soon!',
                        style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        child: const Text('Clear filters'),
                      ),
                    ],
                  ),
                ),
              if (hasResults) ...[
                _buildSectionHeader(
                  'Today\'s Picks',
                  'Fresh finds from open stalls and ready-to-go vendors',
                  eyebrow: 'FRESH NOW',
                  onSeeAll: () => _openFullProductList(
                    "Today's Picks",
                    todayPickProducts,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 248,
                  child: isLoading
                      ? _todayPickShimmerRow()
                      : visibleTodayPicks.isEmpty
                      ? const Center(child: Text("No products yet."))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: visibleTodayPicks.length,
                          itemBuilder: (context, index) {
                            return AppearOnMount(
                              delay: staggerDelay(index, step: 60),
                              child: _buildTodayPickCard(
                                visibleTodayPicks[index],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 28),
                _buildSectionHeader(
                  'Recommended',
                  'Popular finds shoppers are browsing around the plaza',
                  eyebrow: 'FOR YOU',
                  onSeeAll: () => _openFullProductList(
                    'Recommended',
                    filteredProducts,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 308,
                  child: isLoading
                      ? _recommendedShimmerRow()
                      : recommendedProducts.isEmpty
                      ? const Center(child: Text("No products yet."))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: recommendedProducts.length,
                          itemBuilder: (context, i) {
                            final p = recommendedProducts[i];
                            final categoryLabel = _categoryLabel(p);

                            final resolvedImage =
                                (p['image_url'] as String?)?.trim() ?? '';

                            final priceValue = p['price'];
                            final unit = (p['unit_type'] ?? 'kg').toString();
                            final priceText = priceValue != null
                                ? "₱$priceValue /$unit"
                                : "₱0";

                            return AppearOnMount(
                              delay: staggerDelay(i, step: 55),
                              child: ProductCard(
                              title: _productName(p, 'Fresh Item'),
                              storeName: _storeName(p, 'San Fernando Stall'),
                              price: priceText,
                              imageUrl: resolvedImage,
                              description: (p['description'] ?? '').toString(),
                              categoryLabel: categoryLabel,
                              categoryColor: _categoryColor(categoryLabel),
                              isShopOpen: _isShopOpen(p),
                              shopHoursLabel: p['is_db'] == true
                                  ? (_isShopOpen(p)
                                        ? 'Open · Closes ${p['closing_time'] ?? '19:00'}'
                                        : 'Closed · Opens ${p['opening_time'] ?? '05:00'}')
                                  : null,
                              onTap: () => _openProductDetail(p),
                              onAddPressed: () {
                                _addToCart(p);
                              },
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 28),
                _buildSectionHeader(
                  'Daily Essentials',
                  'Everyday staples from trusted plaza vendors',
                  eyebrow: 'STAPLES',
                  onSeeAll: () => _openFullProductList(
                    'Daily Essentials',
                    filteredProducts,
                  ),
                ),
                const SizedBox(height: 14),
                _buildEssentialsGrid(filteredProducts),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  final String title;
  final String storeName;
  final String price;
  final String imageUrl;
  final String description;
  final String categoryLabel;
  final Color? categoryColor;
  final VoidCallback? onTap;
  final VoidCallback onAddPressed;
  final bool isShopOpen;
  final String? shopHoursLabel;

  const ProductCard({
    super.key,
    required this.title,
    required this.storeName,
    required this.price,
    required this.imageUrl,
    this.description = '',
    this.categoryLabel = '',
    this.categoryColor,
    this.onTap,
    required this.onAddPressed,
    this.isShopOpen = true,
    this.shopHoursLabel,
  });

  // Helper method to check if the path is likely a local asset
  bool _isAssetPath(String path) {
    return path.startsWith('assets/') || path.startsWith('images/');
  }

  Widget _placeholder() {
    return Container(
      height: 112,
      width: double.infinity,
      color: const Color(0xFFF1F3F9),
      child: const Center(
        child: Icon(Icons.image_outlined, size: 36, color: Color(0xFFB6BDCC)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget imageWidget = imageUrl.isEmpty
        ? _placeholder()
        : _isAssetPath(imageUrl)
        ? Image.asset(
            imageUrl,
            height: 112,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _placeholder(),
          )
        : Image.network(
            imageUrl,
            height: 112,
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _placeholder();
            },
            errorBuilder: (context, error, stackTrace) => _placeholder(),
          );

    return SizedBox(
      width: 182,
      child: PressableCard(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(right: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE8EDF6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    imageWidget,
                    if (shopHoursLabel != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: isShopOpen
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isShopOpen ? 'Open' : 'Closed',
                                style: TextStyle(
                                  color: isShopOpen
                                      ? const Color(0xFF065F46)
                                      : const Color(0xFF991B1B),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.15,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  if (categoryLabel.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    CategoryPill(
                      label: categoryLabel,
                      color: categoryColor,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                storeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (description.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
              if (shopHoursLabel != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isShopOpen
                        ? const Color(0xFF059669).withValues(alpha: 0.1)
                        : const Color(0xFFDC2626).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    shopHoursLabel!,
                    style: TextStyle(
                      color: isShopOpen
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      price,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                        fontSize: 15,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onAddPressed,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2A4BA0),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CategoryPill extends StatelessWidget {
  final String label;
  final Color? color;

  const CategoryPill({super.key, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? Colors.white;
    final textColor = color == null
        ? const Color(0xFF1F2937)
        : (baseColor.computeLuminance() > 0.6
            ? const Color(0xFF1F2937)
            : Colors.white);
    final borderColor = color == null
        ? const Color(0xFFE5E7EB)
        : baseColor.withValues(alpha: 0.8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: textColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    required this.borderRadius,
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _pressed = false;
  bool _hovered = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (_hovered == value || !mounted) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.985 : (_hovered ? 1.01 : 1.0);
    final translateY = _pressed ? 2.0 : (_hovered ? -4.0 : 0.0);

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        scale: scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, translateY, 0),
          child: Material(
            color: Colors.transparent,
            borderRadius: widget.borderRadius,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: widget.borderRadius,
              splashColor: const Color(0x142A4BA0),
              highlightColor: const Color(0x0A2A4BA0),
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen grid view used by the "See all" buttons on the home page.
/// Renders the same product cards as the home grid so the experience feels
/// continuous when the user drills in from a section.
class _HomeProductsListPage extends StatelessWidget {
  const _HomeProductsListPage({
    required this.title,
    required this.products,
    required this.onTapProduct,
    required this.onAddToCart,
    required this.productNameOf,
    required this.storeNameOf,
    required this.categoryLabelOf,
    required this.categoryColorOf,
    required this.isShopOpenOf,
  });

  final String title;
  final List<dynamic> products;
  final void Function(dynamic product) onTapProduct;
  final void Function(dynamic product) onAddToCart;
  final String Function(dynamic product) productNameOf;
  final String Function(dynamic product) storeNameOf;
  final String Function(dynamic product) categoryLabelOf;
  final Color? Function(String label) categoryColorOf;
  final bool Function(dynamic product) isShopOpenOf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: products.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing here yet — check back soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= 720
                    ? 4
                    : constraints.maxWidth >= 540
                        ? 3
                        : 2;
                return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
              itemCount: products.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 260,
              ),
              itemBuilder: (context, index) {
                final product = products[index];
                final imageUrl =
                    (product['image_url'] as String?)?.trim() ?? '';
                final priceValue = product['price'];
                final unit = (product['unit_type'] ?? 'kg').toString();
                final priceText =
                    priceValue != null ? '₱$priceValue /$unit' : '₱0';
                final categoryLabel = categoryLabelOf(product);
                final isOpen = isShopOpenOf(product);

                return AppearOnMount(
                  delay: staggerDelay(index, step: 35, maxMs: 280),
                  child: PressableCard(
                  onTap: () => onTapProduct(product),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE8EDF6)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x120F172A),
                          blurRadius: 18,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: 114,
                            child: _ProductThumb(imageUrl: imageUrl),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        productNameOf(product),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                    ),
                                    if (categoryLabel.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      CategoryPill(
                                        label: categoryLabel,
                                        color: categoryColorOf(categoryLabel),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  storeNameOf(product),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isOpen
                                        ? const Color(0xFFE6F6EC)
                                        : const Color(0xFFFDECEC),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: isOpen
                                              ? const Color(0xFF1F9D4D)
                                              : const Color(0xFFD23B3B),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        isOpen ? 'Open' : 'Closed',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: isOpen
                                              ? const Color(0xFF1F6F3A)
                                              : const Color(0xFFA12121),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        priceText,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF111827),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => onAddToCart(product),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        width: 34,
                                        height: 34,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF2A4BA0),
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(12),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.add_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                );
              },
            );
              },
            ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.imageUrl});

  final String imageUrl;

  bool _isAsset(String p) => p.startsWith('assets/') || p.startsWith('images/');

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
          color: const Color(0xFFF1F3F9),
          child: const Center(
            child: Icon(
              Icons.image_outlined,
              size: 36,
              color: Color(0xFFB6BDCC),
            ),
          ),
        );

    if (imageUrl.isEmpty) return placeholder();
    if (_isAsset(imageUrl)) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder(),
      errorBuilder: (_, _, _) => placeholder(),
    );
  }
}

/// Pill chip showing whether a shop supports delivery or is pickup-only.
class _FulfillmentChip extends StatelessWidget {
  const _FulfillmentChip({required this.deliveryEnabled});

  final bool deliveryEnabled;

  @override
  Widget build(BuildContext context) {
    final color = deliveryEnabled
        ? const Color(0xFF2A4BA0)
        : const Color(0xFFB45309);
    final icon = deliveryEnabled
        ? Icons.delivery_dining_rounded
        : Icons.storefront_rounded;
    final label = deliveryEnabled ? 'Delivery' : 'Pickup only';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
