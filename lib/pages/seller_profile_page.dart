import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../seller_pages/edit_store_info.dart';
import '../utils/marketplace_ui.dart';
import '../utils/distance_badge.dart';
import '../utils/market_geo.dart';
import '../utils/page_transitions.dart';
import '../utils/store_map_preview.dart';
import 'buyer_messages_page.dart';
import 'productdet.dart';

enum _StorefrontSection { products, reviews, details }

class SellerProfilePage extends StatefulWidget {
  final String sellerId;
  final String? initialStoreName;

  const SellerProfilePage({
    super.key,
    required this.sellerId,
    this.initialStoreName,
  });

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _reviews = [];
  double _avgRating = 0;
  int _reviewCount = 0;
  _StorefrontSection _activeSection = _StorefrontSection.products;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      await Future.wait([_loadProfile(), _loadProducts()]);
      await _loadReviews();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _supabase
          .from('seller_profiles')
          .select(
            'store_name, store_information_final, logo_url, cover_url, '
            'description, is_open, opening_time, closing_time, '
            'store_address, delivery_enabled, official_contact_email, '
            'stall_lat, stall_lng',
          )
          .eq('user_id', widget.sellerId)
          .maybeSingle();
      if (mounted) {
        setState(() => _profile = data);
      }
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    try {
      final data = await _supabase
          .from('product')
          .select(
            'id, name, price, retail_price, unit_type, image_url, image_urls, description',
          )
          .eq('seller_id', widget.sellerId)
          .order('created_at', ascending: false)
          .limit(30);
      if (mounted) {
        setState(() {
          _products = List<Map<String, dynamic>>.from(data as List);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadReviews() async {
    if (_products.isEmpty) {
      if (mounted) {
        setState(() {
          _reviews = [];
          _avgRating = 0;
          _reviewCount = 0;
        });
      }
      return;
    }

    try {
      final productIds = _products
          .map((product) => product['id'])
          .where((productId) => productId != null)
          .toList();
      if (productIds.isEmpty) return;

      final reviewRows = await _supabase
          .from('reviews')
          .select(
            'product_id, buyer_id, reviewer_id, reviewer_name, rating, comment, created_at',
          )
          .inFilter('product_id', productIds)
          .order('created_at', ascending: false)
          .limit(80);

      final reviews = List<Map<String, dynamic>>.from(reviewRows as List);
      final reviewerIds = reviews
          .map(
            (review) =>
                review['buyer_id']?.toString() ??
                review['reviewer_id']?.toString() ??
                '',
          )
          .where((reviewerId) => reviewerId.isNotEmpty)
          .toSet()
          .toList();

      final reviewerNames = <String, String>{};
      final reviewerAvatars = <String, String>{};
      if (reviewerIds.isNotEmpty) {
        try {
          final profileRows = await _supabase
              .from('profile')
              .select('user_id, name, email, avatar_url')
              .inFilter('user_id', reviewerIds);
          for (final row in profileRows as List) {
            final reviewerId = row['user_id']?.toString() ?? '';
            if (reviewerId.isEmpty) continue;
            final name = row['name']?.toString().trim() ?? '';
            final email = row['email']?.toString().trim() ?? '';
            final avatarUrl = row['avatar_url']?.toString().trim() ?? '';
            reviewerNames[reviewerId] = name.isNotEmpty
                ? name
                : (email.isNotEmpty ? email.split('@').first : 'Buyer');
            if (avatarUrl.isNotEmpty) {
              reviewerAvatars[reviewerId] = avatarUrl;
            }
          }
        } catch (_) {}
      }

      final productNames = <String, String>{
        for (final product in _products)
          if ((product['id']?.toString() ?? '').isNotEmpty)
            product['id'].toString(): (product['name'] ?? 'Product').toString(),
      };

      double total = 0;
      for (final review in reviews) {
        final rating = (review['rating'] as num?)?.toDouble() ?? 0;
        total += rating;
        final reviewerId =
            review['buyer_id']?.toString() ??
            review['reviewer_id']?.toString() ??
            '';
        final reviewerName = review['reviewer_name']?.toString().trim() ?? '';
        review['product_name'] =
            productNames[review['product_id']?.toString() ?? ''] ?? 'Product';
        review['reviewer_avatar_url'] = reviewerAvatars[reviewerId];
        review['reviewer_display_name'] = reviewerName.isNotEmpty
            ? reviewerName
            : reviewerNames[reviewerId] ?? 'Buyer';
      }

      if (mounted) {
        setState(() {
          _reviews = reviews;
          _reviewCount = reviews.length;
          _avgRating = reviews.isNotEmpty ? total / reviews.length : 0;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reviews = [];
          _avgRating = 0;
          _reviewCount = 0;
        });
      }
    }
  }

  String _storeName() {
    final primary = _profile?['store_name']?.toString().trim() ?? '';
    if (primary.isNotEmpty) return primary;
    final secondary =
        _profile?['store_information_final']?.toString().trim() ?? '';
    if (secondary.isNotEmpty) return secondary;
    final fallback = widget.initialStoreName?.trim() ?? '';
    return fallback.isNotEmpty ? fallback : 'Store';
  }

  String _formatTime(String value) {
    try {
      final parts = value.split(':');
      var hour = int.parse(parts[0]);
      final minute = parts[1];
      final suffix = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute $suffix';
    } catch (_) {
      return value;
    }
  }

  bool _isShopOpen(String openTime, String closeTime, bool isOpen) {
    if (!isOpen) return false;
    try {
      final now = TimeOfDay.now();
      final open = openTime.split(':');
      final close = closeTime.split(':');
      final openMinutes = int.parse(open[0]) * 60 + int.parse(open[1]);
      final closeMinutes = int.parse(close[0]) * 60 + int.parse(close[1]);
      final nowMinutes = now.hour * 60 + now.minute;
      return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
    } catch (_) {
      return false;
    }
  }

  String _formatCurrency(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    if (number == number.roundToDouble()) {
      return 'P${number.toStringAsFixed(0)}';
    }
    return 'P${number.toStringAsFixed(2)}';
  }

  String _productImage(Map<String, dynamic> product) {
    final directImage = product['image_url']?.toString().trim() ?? '';
    if (directImage.isNotEmpty) return directImage;

    final imageUrls = product['image_urls'];
    if (imageUrls is List && imageUrls.isNotEmpty) {
      final first = imageUrls.first?.toString().trim() ?? '';
      if (first.isNotEmpty) return first;
    }
    return '';
  }

  Map<int, int> _ratingBreakdown() {
    final breakdown = <int, int>{for (var star = 1; star <= 5; star++) star: 0};
    for (final review in _reviews) {
      final rating = (review['rating'] as num?)?.round() ?? 0;
      if (rating >= 1 && rating <= 5) {
        breakdown[rating] = (breakdown[rating] ?? 0) + 1;
      }
    }
    return breakdown;
  }

  @override
  Widget build(BuildContext context) {
    final storeName = _storeName();
    final logoUrl = _profile?['logo_url']?.toString().trim() ?? '';
    final coverUrl = _profile?['cover_url']?.toString().trim() ?? '';
    final description = _profile?['description']?.toString().trim() ?? '';
    final address = _profile?['store_address']?.toString().trim() ?? '';
    final email = _profile?['official_contact_email']?.toString().trim() ?? '';
    final storeLat = (_profile?['stall_lat'] as num?)?.toDouble();
    final storeLng = (_profile?['stall_lng'] as num?)?.toDouble();
    final deliveryEnabled = _profile?['delivery_enabled'] == true;
    final openTime = _profile?['opening_time']?.toString() ?? '05:00';
    final closeTime = _profile?['closing_time']?.toString() ?? '19:00';
    final isOpen = _profile?['is_open'] == true;
    final shopOpen = _isShopOpen(openTime, closeTime, isOpen);
    final currentUserId = _supabase.auth.currentUser?.id;
    final isOwner = currentUserId != null && currentUserId == widget.sellerId;
    final heroPadding = MarketplaceUi.pagePadding(context, top: 8, bottom: 0);

    return Scaffold(
      backgroundColor: MarketplaceUi.surface,
      body: RefreshIndicator(
        color: MarketplaceUi.primary,
        onRefresh: _loadAll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: MarketplaceUi.primaryDark,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 60,
              automaticallyImplyLeading: false,
              leadingWidth: 58,
              leading: Padding(
                padding: const EdgeInsets.only(left: 12, top: 10, bottom: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 17,
                    ),
                  ),
                ),
              ),
              titleSpacing: 0,
              title: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    storeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Storefront',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xC8E3EDFF),
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(
                    right: 12,
                    top: 10,
                    bottom: 10,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: IconButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              if (isOwner) {
                                final updated = await Navigator.push<bool>(
                                  context,
                                  buildMarketplaceRoute(
                                    const EditStoreInfoPage(),
                                  ),
                                );
                                if (updated == true && mounted) {
                                  _loadAll();
                                }
                              } else {
                                await openOrCreateConversation(
                                  context,
                                  sellerId: widget.sellerId,
                                  sellerName: storeName,
                                  sellerAvatarUrl: logoUrl.isEmpty
                                      ? null
                                      : logoUrl,
                                );
                              }
                            },
                      icon: Icon(
                        isOwner
                            ? Icons.edit_outlined
                            : Icons.chat_bubble_outline_rounded,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: _isLoading
                  ? _buildLoadingState(context)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroSection(
                          padding: heroPadding,
                          storeName: storeName,
                          logoUrl: logoUrl,
                          coverUrl: coverUrl,
                          description: description,
                          address: address,
                          shopOpen: shopOpen,
                          openTime: openTime,
                          closeTime: closeTime,
                          deliveryEnabled: deliveryEnabled,
                          isOwner: isOwner,
                          storeLat: storeLat,
                          storeLng: storeLng,
                        ),
                        Padding(
                          padding: MarketplaceUi.pagePadding(
                            context,
                            top: 14,
                            bottom: 0,
                          ),
                          child: _buildSectionTabs(),
                        ),
                        Padding(
                          padding: MarketplaceUi.pagePadding(
                            context,
                            top: 16,
                            bottom: 24,
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _buildActiveSection(
                              context,
                              storeName: storeName,
                              description: description,
                              address: address,
                              email: email,
                              openTime: openTime,
                              closeTime: closeTime,
                              deliveryEnabled: deliveryEnabled,
                              shopOpen: shopOpen,
                              storeLat: storeLat,
                              storeLng: storeLng,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Padding(
      padding: MarketplaceUi.pagePadding(context, top: 22, bottom: 30),
      child: Column(
        children: [
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: const Color(0xFFDCE6F6),
              borderRadius: BorderRadius.circular(32),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            height: 250,
            decoration: MarketplaceUi.panel(color: const Color(0xFFF2F5FA)),
          ),
          const SizedBox(height: 18),
          Row(
            children: List.generate(
              3,
              (index) => Expanded(
                child: Container(
                  height: 54,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F5FA),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            height: 320,
            decoration: MarketplaceUi.panel(color: const Color(0xFFF2F5FA)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection({
    required EdgeInsets padding,
    required String storeName,
    required String logoUrl,
    required String coverUrl,
    required String description,
    required String address,
    required bool shopOpen,
    required String openTime,
    required String closeTime,
    required bool deliveryEnabled,
    required bool isOwner,
    double? storeLat,
    double? storeLng,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final compactLayout = screenWidth < 370;
    final coverHeight = compactLayout ? 184.0 : 208.0;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: coverHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A122347),
                  blurRadius: 24,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildCoverImage(coverUrl),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.58),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 18,
                  left: 18,
                  right: 18,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildHeroBadge(
                        icon: shopOpen
                            ? Icons.fiber_manual_record_rounded
                            : Icons.schedule_rounded,
                        label: shopOpen ? 'Open now' : 'Currently closed',
                        backgroundColor: shopOpen
                            ? const Color(0xCC059669)
                            : const Color(0xCCDC2626),
                      ),
                      _buildHeroBadge(
                        icon: Icons.schedule_rounded,
                        label:
                            '${_formatTime(openTime)} - ${_formatTime(closeTime)}',
                        backgroundColor: const Color(0x2BF8FAFC),
                      ),
                      _buildHeroBadge(
                        icon: deliveryEnabled
                            ? Icons.delivery_dining_rounded
                            : Icons.store_mall_directory_outlined,
                        label: deliveryEnabled
                            ? 'Delivery and pickup'
                            : 'Pickup ready',
                        backgroundColor: const Color(0x2BF8FAFC),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: 18,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildHeroBadge(
                        icon: Icons.inventory_2_outlined,
                        label: '${_products.length} listings',
                        backgroundColor: const Color(0x2BF8FAFC),
                      ),
                      _buildHeroBadge(
                        icon: Icons.star_rounded,
                        label: _reviewCount > 0
                            ? '${_avgRating.toStringAsFixed(1)} rating'
                            : 'New store',
                        backgroundColor: const Color(0x33F59E0B),
                      ),
                      if (storeLat != null && storeLng != null)
                        DistanceBadge(
                          storeLat: storeLat,
                          storeLng: storeLng,
                          foreground: Colors.white,
                          background: Colors.white.withValues(alpha: 0.18),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: MarketplaceUi.panel(
              color: Colors.white,
              highlighted: true,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLogo(logoUrl),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            storeName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: MarketplaceUi.textStrong,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            shopOpen
                                ? 'Open now for orders and chat'
                                : 'Closed now, but storefront is available',
                            style: TextStyle(
                              color: shopOpen
                                  ? MarketplaceUi.success
                                  : MarketplaceUi.textSubtle,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            description.isNotEmpty
                                ? description
                                : 'This storefront is ready for product questions, pricing discussions, and order coordination.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MarketplaceUi.textMuted,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildStoreInfoChip(
                      icon: shopOpen
                          ? Icons.check_circle_rounded
                          : Icons.schedule_rounded,
                      label: shopOpen
                          ? 'Open now'
                          : 'Closed · ${_formatTime(openTime)}',
                      color: shopOpen
                          ? MarketplaceUi.success
                          : MarketplaceUi.warning,
                    ),
                    _buildStoreInfoChip(
                      icon: deliveryEnabled
                          ? Icons.delivery_dining_rounded
                          : Icons.store_mall_directory_outlined,
                      label: deliveryEnabled
                          ? 'Delivery + pickup'
                          : 'Pickup only',
                      color: deliveryEnabled
                          ? MarketplaceUi.accent
                          : MarketplaceUi.primary,
                    ),
                    if (storeLat != null && storeLng != null)
                      DistanceBadge(
                        storeLat: storeLat,
                        storeLng: storeLng,
                        foreground: MarketplaceUi.primaryDark,
                        background:
                            MarketplaceUi.primary.withValues(alpha: 0.10),
                      ),
                  ],
                ),
                if (address.isNotEmpty || (storeLat != null && storeLng != null)) ...[
                  const SizedBox(height: 12),
                  _buildLocationRow(
                    address: address,
                    storeLat: storeLat,
                    storeLng: storeLng,
                    storeName: storeName,
                  ),
                ],
                const SizedBox(height: 18),
                _buildHeroActionButtons(
                  isOwner: isOwner,
                  storeName: storeName,
                  logoUrl: logoUrl,
                ),
                const SizedBox(height: 18),
                _buildHeroMetrics(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage(String coverUrl) {
    if (coverUrl.isEmpty) {
      return Container(
        decoration: BoxDecoration(gradient: MarketplaceUi.heroGradient),
        child: Center(
          child: Icon(
            Icons.storefront_rounded,
            size: 78,
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
      );
    }

    return Image.network(
      coverUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        decoration: BoxDecoration(gradient: MarketplaceUi.heroGradient),
        child: Center(
          child: Icon(
            Icons.storefront_rounded,
            size: 78,
            color: Colors.white.withValues(alpha: 0.14),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBadge({
    required IconData icon,
    required String label,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
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

  Widget _buildLogo(String logoUrl) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFDDE8FF), Color(0xFFCEDDFC)],
        ),
        border: Border.all(color: const Color(0xFFD7E2FA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl.isNotEmpty
          ? Image.network(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.storefront_rounded,
                color: MarketplaceUi.primary,
                size: 36,
              ),
            )
          : const Icon(
              Icons.storefront_rounded,
              color: MarketplaceUi.primary,
              size: 36,
            ),
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MarketplaceUi.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE3F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: MarketplaceUi.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: MarketplaceUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow({
    required String address,
    required String storeName,
    double? storeLat,
    double? storeLng,
  }) {
    final hasMap = storeLat != null && storeLng != null;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: hasMap
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoreMapFullScreen(
                    lat: storeLat,
                    lng: storeLng,
                    address: address.isEmpty ? null : address,
                    storeName: storeName,
                  ),
                ),
              )
          : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: MarketplaceUi.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCE3F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: MarketplaceUi.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.place_rounded,
                color: MarketplaceUi.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    address.isNotEmpty ? address : 'Pinned on map',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: MarketplaceUi.textStrong,
                      height: 1.35,
                    ),
                  ),
                  if (hasMap) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Text(
                          'View map',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: MarketplaceUi.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: MarketplaceUi.primary,
                          size: 13,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (hasMap)
              IconButton(
                tooltip: 'Open in maps',
                onPressed: () => launchExternalNavigation(
                  LatLng(storeLat, storeLng),
                  label: storeName,
                ),
                icon: const Icon(
                  Icons.directions_rounded,
                  color: MarketplaceUi.primary,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFDCE3F0)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroActionButtons({
    required bool isOwner,
    required String storeName,
    required String logoUrl,
  }) {
    final primaryButton = ElevatedButton.icon(
      onPressed: () async {
        if (isOwner) {
          final updated = await Navigator.push<bool>(
            context,
            buildMarketplaceRoute(const EditStoreInfoPage()),
          );
          if (updated == true && mounted) {
            _loadAll();
          }
        } else {
          await openOrCreateConversation(
            context,
            sellerId: widget.sellerId,
            sellerName: storeName,
            sellerAvatarUrl: logoUrl.isEmpty ? null : logoUrl,
          );
        }
      },
      icon: Icon(isOwner ? Icons.edit_rounded : Icons.chat_rounded, size: 18),
      label: Text(isOwner ? 'Edit storefront' : 'Message store'),
    );

    final secondaryButton = OutlinedButton.icon(
      onPressed: () {
        setState(() {
          _activeSection = _StorefrontSection.reviews;
        });
      },
      icon: const Icon(Icons.star_outline_rounded, size: 18),
      label: const Text('See reviews'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 430;
        if (stacked) {
          return Column(
            children: [
              SizedBox(width: double.infinity, child: primaryButton),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: secondaryButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: primaryButton),
            const SizedBox(width: 10),
            Expanded(child: secondaryButton),
          ],
        );
      },
    );
  }

  Widget _buildHeroMetrics() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 390) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      label: 'Products',
                      value: '${_products.length}',
                      icon: Icons.inventory_2_outlined,
                      color: MarketplaceUi.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _metricCard(
                      label: 'Rating',
                      value: _avgRating > 0
                          ? _avgRating.toStringAsFixed(1)
                          : 'New',
                      icon: Icons.star_rounded,
                      color: MarketplaceUi.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: _metricCard(
                  label: 'Reviews',
                  value: _reviewCount > 0 ? '$_reviewCount' : '0',
                  icon: Icons.rate_review_outlined,
                  color: MarketplaceUi.accent,
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _metricCard(
                label: 'Products',
                value: '${_products.length}',
                icon: Icons.inventory_2_outlined,
                color: MarketplaceUi.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                label: 'Rating',
                value: _avgRating > 0 ? _avgRating.toStringAsFixed(1) : 'New',
                icon: Icons.star_rounded,
                color: MarketplaceUi.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricCard(
                label: 'Reviews',
                value: _reviewCount > 0 ? '$_reviewCount' : '0',
                icon: Icons.rate_review_outlined,
                color: MarketplaceUi.accent,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionTabs() {
    final compact = MediaQuery.of(context).size.width < 360;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE3F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _sectionTabButton(
              label: 'Products',
              icon: Icons.grid_view_rounded,
              section: _StorefrontSection.products,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _sectionTabButton(
              label: 'Reviews',
              icon: Icons.star_rate_rounded,
              section: _StorefrontSection.reviews,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _sectionTabButton(
              label: compact ? 'Details' : 'Store details',
              icon: Icons.storefront_outlined,
              section: _StorefrontSection.details,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTabButton({
    required String label,
    required IconData icon,
    required _StorefrontSection section,
  }) {
    final isSelected = _activeSection == section;
    return InkWell(
      onTap: () => setState(() => _activeSection = section),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [MarketplaceUi.primary, MarketplaceUi.primaryDark],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : MarketplaceUi.textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : MarketplaceUi.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSection(
    BuildContext context, {
    required String storeName,
    required String description,
    required String address,
    required String email,
    required String openTime,
    required String closeTime,
    required bool deliveryEnabled,
    required bool shopOpen,
    double? storeLat,
    double? storeLng,
  }) {
    switch (_activeSection) {
      case _StorefrontSection.products:
        return _buildProductsSection(context);
      case _StorefrontSection.reviews:
        return _buildReviewsSection();
      case _StorefrontSection.details:
        return _buildDetailsSection(
          storeName: storeName,
          description: description,
          address: address,
          email: email,
          openTime: openTime,
          closeTime: closeTime,
          deliveryEnabled: deliveryEnabled,
          shopOpen: shopOpen,
          storeLat: storeLat,
          storeLng: storeLng,
        );
    }
  }

  Widget _buildProductsSection(BuildContext context) {
    if (_products.isEmpty) {
      return Container(
        key: const ValueKey('products_empty'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: MarketplaceUi.panel(),
        child: const Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 42,
              color: MarketplaceUi.textSubtle,
            ),
            SizedBox(height: 12),
            Text(
              'No products yet',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: MarketplaceUi.textStrong,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Once this seller adds items, they will appear here with pricing, imagery, and unit details.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: MarketplaceUi.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('products_section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Store products',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: MarketplaceUi.textStrong,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_products.length} listings available from this storefront.',
            style: const TextStyle(
              fontSize: 13,
              color: MarketplaceUi.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 980
                  ? 4
                  : constraints.maxWidth >= 700
                  ? 3
                  : constraints.maxWidth < 360
                  ? 1
                  : 2;
              final totalSpacing = 14.0 * (crossAxisCount - 1);
              final itemWidth =
                  (constraints.maxWidth - totalSpacing) / crossAxisCount;

              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: _products
                    .asMap()
                    .entries
                    .map(
                      (entry) => SizedBox(
                        width: itemWidth,
                        child: FadeInOnMount(
                          delay: Duration(
                            milliseconds: (entry.key * 40).clamp(0, 320),
                          ),
                          child: _productCard(entry.value),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> product) {
    final name = (product['name'] ?? 'Product').toString();
    final description = product['description']?.toString().trim() ?? '';
    final unit = (product['unit_type'] ?? 'unit').toString();
    final image = _productImage(product);
    final price = _formatCurrency(product['price']);
    final retailPriceValue = product['retail_price'];
    final retailPrice =
        retailPriceValue != null &&
            retailPriceValue.toString().trim().isNotEmpty
        ? _formatCurrency(retailPriceValue)
        : '';

    return PressableCard(
      onTap: () {
        Navigator.push(
          context,
          buildMarketplaceRoute(
            ProductViewPage(
              product: {...product, 'seller_id': widget.sellerId},
            ),
          ),
        );
      },
      child: Container(
        decoration: MarketplaceUi.panel(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: image.isEmpty
                    ? _productPlaceholder()
                    : _buildProductImage(image),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: MarketplaceUi.textStrong,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: MarketplaceUi.textMuted,
                      ),
                    )
                  else
                    const Text(
                      'Fresh listing from this storefront.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: MarketplaceUi.textMuted,
                      ),
                    ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: MarketplaceUi.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          price,
                          style: const TextStyle(
                            color: MarketplaceUi.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF3F8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'per $unit',
                          style: const TextStyle(
                            color: MarketplaceUi.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (retailPrice.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      retailPrice,
                      style: const TextStyle(
                        color: MarketplaceUi.textSubtle,
                        fontSize: 12,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage(String image) {
    if (image.startsWith('assets/')) {
      return Image.asset(
        image,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _productPlaceholder(),
      );
    }
    return Image.network(
      image,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _productPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) => _productPlaceholder(),
    );
  }

  Widget _productPlaceholder() {
    return Container(
      color: const Color(0xFFEFF3F8),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        size: 34,
        color: Color(0xFFB2BDCF),
      ),
    );
  }

  Widget _buildReviewsSection() {
    final breakdown = _ratingBreakdown();
    final maxCount = breakdown.values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );

    if (_reviews.isEmpty) {
      return Container(
        key: const ValueKey('reviews_empty'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: MarketplaceUi.panel(),
        child: const Column(
          children: [
            Icon(
              Icons.reviews_outlined,
              size: 42,
              color: MarketplaceUi.textSubtle,
            ),
            SizedBox(height: 12),
            Text(
              'No reviews yet',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: MarketplaceUi.textStrong,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Buyer ratings and written feedback will appear here after completed orders receive reviews.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: MarketplaceUi.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      key: const ValueKey('reviews_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer feedback',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: MarketplaceUi.textStrong,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$_reviewCount reviews across this seller\'s current listings.',
          style: const TextStyle(fontSize: 13, color: MarketplaceUi.textMuted),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: MarketplaceUi.panel(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _avgRating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 42,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: MarketplaceUi.textStrong,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(
                        5,
                        (index) => Icon(
                          index < _avgRating.round()
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: MarketplaceUi.warning,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Based on $_reviewCount verified ratings',
                      style: const TextStyle(
                        fontSize: 12,
                        color: MarketplaceUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    for (var star = 5; star >= 1; star--)
                      _ratingBarRow(
                        star: star,
                        count: breakdown[star] ?? 0,
                        maxCount: maxCount == 0 ? 1 : maxCount,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._reviews.map(_reviewCard),
      ],
    );
  }

  Widget _ratingBarRow({
    required int star,
    required int count,
    required int maxCount,
  }) {
    final fraction = count == 0 ? 0.0 : count / maxCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$star',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MarketplaceUi.textMuted,
              ),
            ),
          ),
          const Icon(
            Icons.star_rounded,
            size: 14,
            color: MarketplaceUi.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: const Color(0xFFE9EEF7),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  MarketplaceUi.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 22,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MarketplaceUi.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> review) {
    final reviewerName =
        review['reviewer_display_name']?.toString().trim().isNotEmpty == true
        ? review['reviewer_display_name'].toString()
        : 'Buyer';
    final productName = review['product_name']?.toString() ?? 'Product';
    final comment = review['comment']?.toString().trim() ?? '';
    final rating = (review['rating'] as num?)?.toInt() ?? 5;
    final avatarUrl = review['reviewer_avatar_url']?.toString().trim() ?? '';
    final createdAt = DateTime.tryParse(review['created_at']?.toString() ?? '');
    final dateText = createdAt == null
        ? ''
        : '${createdAt.month}/${createdAt.day}/${createdAt.year}';
    final initials = reviewerName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .take(2)
        .join()
        .toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: MarketplaceUi.panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDCE7FF), Color(0xFFCFE0FF)],
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Text(
                            initials.isEmpty ? 'B' : initials,
                            style: const TextStyle(
                              color: MarketplaceUi.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          initials.isEmpty ? 'B' : initials,
                          style: const TextStyle(
                            color: MarketplaceUi.primary,
                            fontSize: 16,
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            reviewerName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: MarketplaceUi.textStrong,
                            ),
                          ),
                        ),
                        if (dateText.isNotEmpty)
                          Text(
                            dateText,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: MarketplaceUi.textSubtle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            5,
                            (index) => Icon(
                              index < rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 15,
                              color: MarketplaceUi.warning,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: MarketplaceUi.surface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            productName,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: MarketplaceUi.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            comment.isNotEmpty
                ? comment
                : 'Buyer shared a star rating without a written comment.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: MarketplaceUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection({
    required String storeName,
    required String description,
    required String address,
    required String email,
    required String openTime,
    required String closeTime,
    required bool deliveryEnabled,
    required bool shopOpen,
    double? storeLat,
    double? storeLng,
  }) {
    return Column(
      key: const ValueKey('details_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Store details',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: MarketplaceUi.textStrong,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Quick facts, contact information, and fulfillment options for this storefront.',
          style: TextStyle(fontSize: 13, color: MarketplaceUi.textMuted),
        ),
        const SizedBox(height: 16),
        _detailCard(
          title: 'About this store',
          icon: Icons.info_outline_rounded,
          child: Text(
            description.isNotEmpty
                ? description
                : '$storeName has not added a longer storefront description yet.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: MarketplaceUi.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _detailCard(
          title: 'Store schedule',
          icon: Icons.schedule_rounded,
          child: Column(
            children: [
              _detailRow(
                icon: Icons.access_time_rounded,
                label: 'Hours',
                value: '${_formatTime(openTime)} - ${_formatTime(closeTime)}',
              ),
              const SizedBox(height: 12),
              _detailRow(
                icon: shopOpen
                    ? Icons.check_circle_rounded
                    : Icons.pause_circle_rounded,
                label: 'Current status',
                value: shopOpen ? 'Open right now' : 'Currently closed',
                color: shopOpen ? MarketplaceUi.success : MarketplaceUi.warning,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _detailCard(
          title: 'Fulfillment options',
          icon: Icons.local_shipping_outlined,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _detailChip(
                icon: Icons.store_mall_directory_outlined,
                label: 'Pickup available',
                color: MarketplaceUi.success,
              ),
              _detailChip(
                icon: Icons.delivery_dining_rounded,
                label: deliveryEnabled
                    ? 'Delivery available'
                    : 'Delivery disabled',
                color: deliveryEnabled
                    ? MarketplaceUi.primary
                    : MarketplaceUi.textSubtle,
              ),
            ],
          ),
        ),
        if (address.isNotEmpty || email.isNotEmpty) ...[
          const SizedBox(height: 14),
          _detailCard(
            title: 'Contact and location',
            icon: Icons.pin_drop_outlined,
            child: Column(
              children: [
                if (address.isNotEmpty)
                  _detailRow(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: address,
                    allowWrap: true,
                  ),
                if (address.isNotEmpty && email.isNotEmpty)
                  const SizedBox(height: 12),
                if (email.isNotEmpty)
                  _detailRow(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: email,
                    allowWrap: true,
                  ),
              ],
            ),
          ),
        ],
        if (storeLat != null && storeLng != null) ...[
          const SizedBox(height: 14),
          _detailCard(
            title: 'Find this store',
            icon: Icons.map_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StoreMapPreview(
                  lat: storeLat,
                  lng: storeLng,
                  address: address.isEmpty ? null : address,
                  storeName: storeName,
                  height: 170,
                ),
                const SizedBox(height: 10),
                Text(
                  'Tap the map to view a full-screen pin and the surrounding area.',
                  style: TextStyle(
                    fontSize: 12,
                    color: MarketplaceUi.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _detailCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MarketplaceUi.panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: MarketplaceUi.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: MarketplaceUi.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: MarketplaceUi.textStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    Color color = MarketplaceUi.primary,
    bool allowWrap = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: MarketplaceUi.textSubtle,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: allowWrap ? null : 1,
                overflow: allowWrap
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: MarketplaceUi.textStrong,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
