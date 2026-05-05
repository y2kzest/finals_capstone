import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'productdet.dart';
import 'buyer_messages_page.dart';
import '../seller_pages/edit_store_info.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kPrimaryDark = Color(0xFF153075);
const Color _kYellow = Color(0xFFF9B023);
const Color _kSurface = Color(0xFFF5F6FB);

class SellerProfilePage extends StatefulWidget {
  final String sellerId;

  /// Optional: shown while profile data is loading
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
  double _avgRating = 0;
  int _reviewCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadProfile(), _loadProducts()]);
    await _loadReviews();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _supabase
          .from('seller_profiles')
          .select(
              'store_name, store_information_final, logo_url, cover_url, '
              'description, is_open, opening_time, closing_time, '
              'store_address, delivery_enabled, official_contact_email')
          .eq('user_id', widget.sellerId)
          .maybeSingle();
      if (mounted) setState(() => _profile = data);
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    try {
      final data = await _supabase
          .from('product')
          .select('id, name, price, retail_price, unit_type, image_url, image_urls, description')
          .eq('seller_id', widget.sellerId)
          .order('created_at', ascending: false)
          .limit(30);
      if (mounted) {
        setState(() =>
            _products = List<Map<String, dynamic>>.from(data as List));
      }
    } catch (_) {}
  }

  Future<void> _loadReviews() async {
    if (_products.isEmpty) return;
    try {
      final productIds = _products
          .map((p) => p['id'])
          .where((id) => id != null)
          .toList();
      if (productIds.isEmpty) return;
      final data = await _supabase
          .from('reviews')
          .select('rating')
          .inFilter('product_id', productIds);
      final list = List<Map<String, dynamic>>.from(data as List);
      if (mounted && list.isNotEmpty) {
        double total = 0;
        for (final r in list) {
          total += (r['rating'] as num?)?.toDouble() ?? 0;
        }
        setState(() {
          _avgRating = total / list.length;
          _reviewCount = list.length;
        });
      }
    } catch (_) {}
  }

  String _formatTime(String t) {
    try {
      final parts = t.split(':');
      int hour = int.parse(parts[0]);
      final min = parts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$min $period';
    } catch (_) {
      return t;
    }
  }

  bool _isShopOpen(String openTime, String closeTime, bool isOpen) {
    if (!isOpen) return false;
    try {
      final now = TimeOfDay.now();
      final op = openTime.split(':');
      final cl = closeTime.split(':');
      final openMin = int.parse(op[0]) * 60 + int.parse(op[1]);
      final closeMin = int.parse(cl[0]) * 60 + int.parse(cl[1]);
      final nowMin = now.hour * 60 + now.minute;
      return nowMin >= openMin && nowMin <= closeMin;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeName =
        _profile?['store_name']?.toString().trim().isNotEmpty == true
            ? _profile!['store_name'].toString()
            : _profile?['store_information_final']
                        ?.toString()
                        .trim()
                        .isNotEmpty ==
                    true
                ? _profile!['store_information_final'].toString()
                : widget.initialStoreName ?? 'Store';

    final logoUrl = _profile?['logo_url']?.toString();
    final coverUrl = _profile?['cover_url']?.toString();
    final description = _profile?['description']?.toString();
    final isOpen = _profile?['is_open'] == true;
    final openTime = _profile?['opening_time']?.toString() ?? '05:00';
    final closeTime = _profile?['closing_time']?.toString() ?? '19:00';
    final address = _profile?['store_address']?.toString();
    final email = _profile?['official_contact_email']?.toString();
    final deliveryEnabled = _profile?['delivery_enabled'] == true;
    final shopOpen = _isShopOpen(openTime, closeTime, isOpen);

    final currentUserId = _supabase.auth.currentUser?.id;
    final isOwner = currentUserId != null && currentUserId == widget.sellerId;

    return Scaffold(
      backgroundColor: _kSurface,
      body: CustomScrollView(
        slivers: [
          // ─── Slim pinned app bar only ─────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: _kPrimaryDark,
            foregroundColor: Colors.white,
            titleSpacing: 0,
            title: Text(
              storeName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      size: 20, color: Colors.white),
                ),
              ),
            ),
            actions: [
              if (isOwner)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () async {
                      final updated = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EditStoreInfoPage()),
                      );
                      if (updated == true && mounted) {
                        setState(() => _isLoading = true);
                        _loadAll();
                      }
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => openOrCreateConversation(
                      context,
                      sellerId: widget.sellerId,
                      sellerName: storeName,
                      sellerAvatarUrl: logoUrl,
                    ),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // ─── Main Content ─────────────────────────────────
          SliverToBoxAdapter(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(60),
                      child: CircularProgressIndicator(color: _kPrimary),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cover photo sits at the top of the content area
                      _buildStoreHeader(
                        storeName: storeName,
                        logoUrl: logoUrl,
                        coverUrl: coverUrl,
                        shopOpen: shopOpen,
                        openTime: openTime,
                        closeTime: closeTime,
                        deliveryEnabled: deliveryEnabled,
                      ),

                      // Stats row
                      _buildStats(),

                      // Description
                      if (description != null && description.isNotEmpty)
                        _buildDescription(description),

                      // Contact / address
                      if ((address != null && address.isNotEmpty) ||
                          (email != null && email.isNotEmpty))
                        _buildContactInfo(address: address, email: email),

                      const SizedBox(height: 4),

                      // Products section header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: Row(
                          children: [
                            const Text(
                              'Products',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: _kPrimary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${_products.length}',
                                style: const TextStyle(
                                  color: _kPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Products grid
                      _products.isEmpty
                          ? Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.inventory_2_outlined,
                                        size: 40,
                                        color: Color(0xFFD1D5DB)),
                                    SizedBox(height: 8),
                                    Text('No products yet',
                                        style: TextStyle(
                                            color: Color(0xFF9CA3AF))),
                                  ],
                                ),
                              ),
                            )
                          : Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildProductsGrid(),
                            ),

                      const SizedBox(height: 32),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Cover photo ────────────────────────────────────────────
  Widget _buildCover(String? coverUrl) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (coverUrl != null && coverUrl.isNotEmpty)
          Image.network(
            coverUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _gradientCover(),
          )
        else
          _gradientCover(),
        // Subtle gradient overlay at bottom for text readability
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.5),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _gradientCover() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A4BA0), Color(0xFF153075)],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.storefront_rounded,
            size: 70,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      );

  // ── Store header (cover + logo + info) ───────────────────
  Widget _buildStoreHeader({
    required String storeName,
    required String? logoUrl,
    required String? coverUrl,
    required bool shopOpen,
    required String openTime,
    required String closeTime,
    required bool deliveryEnabled,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            SizedBox(
              height: 160,
              width: double.infinity,
              child: _buildCover(coverUrl),
            ),
            // White info card with top padding for the logo
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 16),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              storeName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: const [
                                Icon(Icons.verified_rounded,
                                    size: 14, color: _kPrimary),
                                SizedBox(width: 4),
                                Text(
                                  'Verified Seller',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _kPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Open / Closed pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: shopOpen
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: shopOpen
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFDC2626),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              shopOpen ? 'Open Now' : 'Closed',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: shopOpen
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Operating hours
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 14, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 5),
                      Text(
                        '${_formatTime(openTime)} – ${_formatTime(closeTime)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Feature badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (deliveryEnabled)
                        _featureBadge(
                          Icons.delivery_dining_rounded,
                          'Delivery',
                          _kPrimary,
                        ),
                      _featureBadge(
                        Icons.store_mall_directory_rounded,
                        'Pickup',
                        const Color(0xFF059669),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        // Circular logo overlapping the cover/card boundary
        Positioned(
          top: 116, // 160 cover height - 44 (half of 88 logo diameter)
          left: 20,
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: logoUrl != null && logoUrl.isNotEmpty
                ? Image.network(
                    logoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _logoFallback(),
                  )
                : _logoFallback(),
          ),
        ),
      ],
    );
  }

  Widget _logoFallback() => Container(
        color: _kPrimary,
        child: const Icon(Icons.storefront_rounded,
            color: Colors.white, size: 38),
      );

  Widget _featureBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats row ─────────────────────────────────────────────
  Widget _buildStats() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _statItem(
            value: '${_products.length}',
            label: 'Products',
            icon: Icons.inventory_2_outlined,
            iconColor: _kPrimary,
          ),
          _divider(),
          _statItem(
            value:
                _avgRating > 0 ? _avgRating.toStringAsFixed(1) : '—',
            label: 'Avg Rating',
            icon: Icons.star_rounded,
            iconColor: _kYellow,
          ),
          _divider(),
          _statItem(
            value: _reviewCount > 0 ? '$_reviewCount' : '—',
            label: 'Reviews',
            icon: Icons.rate_review_outlined,
            iconColor: const Color(0xFF8B5CF6),
          ),
        ],
      ),
    );
  }

  Widget _statItem({
    required String value,
    required String label,
    required IconData icon,
    required Color iconColor,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 44,
        color: const Color(0xFFE5E7EB),
      );

  // ── About the store ───────────────────────────────────────
  Widget _buildDescription(String description) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.info_outline_rounded,
                  size: 16, color: _kPrimary),
              SizedBox(width: 6),
              Text(
                'About the Store',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6B7280),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  // ── Contact / address ─────────────────────────────────────
  Widget _buildContactInfo({String? address, String? email}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.storefront_outlined,
                  size: 16, color: _kPrimary),
              SizedBox(width: 6),
              Text(
                'Store Information',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoRow(
              Icons.location_on_rounded,
              address,
              const Color(0xFF059669),
            ),
          ],
          if (email != null && email.isNotEmpty) ...[
            const SizedBox(height: 10),
            _infoRow(Icons.email_outlined, email, _kPrimary),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF374151),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  // ── Products grid ─────────────────────────────────────────
  Widget _buildProductsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final p = _products[index];
        final imageUrl = (p['image_url'] as String?)?.trim() ?? '';
        final priceValue = p['price'];
        final unit = (p['unit_type'] ?? 'kg').toString();
        final priceText = priceValue != null ? '₱$priceValue' : '₱0';
        final name = (p['name'] ?? 'Product').toString();

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductViewPage(
                product: {...p, 'seller_id': widget.sellerId},
              ),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Image with gradient overlay at bottom
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                  child: Stack(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 120,
                        child: _buildProductImage(imageUrl),
                      ),
                      // Bottom gradient for text readability
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.45),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Info section — tight, no spacer
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  priceText,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Color(0xFF2A4BA0),
                                  ),
                                ),
                                Text(
                                  'per $unit',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF9CA3AF),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A4BA0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.add_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductImage(String url) {
    if (url.isEmpty) return _imgPlaceholder();
    if (url.startsWith('assets/')) {
      return Image.asset(url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imgPlaceholder());
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : _imgPlaceholder(),
      errorBuilder: (_, __, ___) => _imgPlaceholder(),
    );
  }

  Widget _imgPlaceholder() => Container(
        color: const Color(0xFFEEF1F8),
        child: const Center(
          child: Icon(Icons.image_outlined,
              size: 32, color: Color(0xFFB6BDCC)),
        ),
      );
}
