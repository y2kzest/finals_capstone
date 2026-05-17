import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/marketplace_ui.dart' show AppearOnMount, ShimmerBox, staggerDelay;
import 'productdet.dart';

const _kPrimary = Color(0xFF2A4BA0);
const _kPrimaryDark = Color(0xFF153075);
const _kAccent = Color(0xFFF5A524);
const _kSurface = Color(0xFFF5F6FB);

/// Wishlist as a 2-column visual grid, modeled after how modern shopping
/// apps surface saved items (Amazon Lists, Pinterest, IKEA app). Each card
/// is image-forward with a quick-action overlay so the screen reads as a
/// gallery the buyer scans, not a transactional list.
class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  final Set<String> _removingIds = {};
  _SortOrder _sort = _SortOrder.recent;

  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    final curved = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutCubic,
    );
    _entryFade = Tween<double>(begin: 0, end: 1).animate(curved);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(curved);
    _loadWishlist();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWishlist() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await Supabase.instance.client
          .from('wishlist')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
        _entryCtrl.forward(from: 0);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _entryCtrl.forward(from: 0);
      }
    }
  }

  Future<void> _removeFromWishlist(String productId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _removingIds.add(productId));
    try {
      await Supabase.instance.client
          .from('wishlist')
          .delete()
          .eq('user_id', user.id)
          .eq('product_id', productId);
      if (mounted) {
        setState(() {
          _items.removeWhere((i) => i['product_id'] == productId);
          _removingIds.remove(productId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Removed from wishlist'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: _kPrimaryDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _removingIds.remove(productId));
    }
  }

  Future<void> _openProduct(String productId) async {
    try {
      final product = await Supabase.instance.client
          .from('product')
          .select(
            '*, seller_profiles!product_seller_id_fkey(approval_status)',
          )
          .eq('id', productId)
          .maybeSingle();
      if (!mounted) return;
      if (product == null) return;
      final sp = product['seller_profiles'];
      final sellerStatus = sp is Map
          ? sp['approval_status']?.toString().toLowerCase()
          : null;
      if (sellerStatus == 'suspended' || sellerStatus == 'rejected') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This store is currently unavailable.')),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductViewPage(product: product)),
      );
      _loadWishlist();
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _sortedItems {
    final copy = [..._items];
    switch (_sort) {
      case _SortOrder.priceLow:
        copy.sort(
          (a, b) => _priceOf(a).compareTo(_priceOf(b)),
        );
      case _SortOrder.priceHigh:
        copy.sort(
          (a, b) => _priceOf(b).compareTo(_priceOf(a)),
        );
      case _SortOrder.recent:
        // Already ordered by created_at desc from the query.
        break;
    }
    return copy;
  }

  double _priceOf(Map<String, dynamic> item) =>
      (item['price'] as num?)?.toDouble() ?? 0;

  String _formatPrice(dynamic price) =>
      ((price as num?)?.toDouble() ?? 0).toStringAsFixed(2);

  /// Compute a grid delegate sized to the actual viewport so cards never
  /// overflow. The card has an aspect-1.05 image and a fixed-height details
  /// strip (~104px including padding, store row, price row). Using a fixed
  /// `mainAxisExtent: 248` previously caused overlap on wider phones because
  /// the image grew while the height stayed clamped.
  SliverGridDelegate _gridDelegateFor(double available) {
    const spacing = 12.0;
    final crossAxisCount = available >= 720
        ? 4
        : available >= 540
            ? 3
            : 2;
    final cardWidth =
        (available - spacing * (crossAxisCount - 1)) / crossAxisCount;
    final imageHeight = cardWidth / 1.05;
    const detailsHeight = 104.0;
    final extent = imageHeight + detailsHeight;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: spacing,
      mainAxisSpacing: 14,
      mainAxisExtent: extent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: _loadWishlist,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildHeader(),
            if (_isLoading)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final grid = _gridDelegateFor(constraints.crossAxisExtent);
                    return SliverGrid.builder(
                      gridDelegate: grid,
                      itemCount: 4,
                      itemBuilder: (_, _) => _buildSkeletonCard(),
                    );
                  },
                ),
              )
            else if (_items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: FadeTransition(
                  opacity: _entryFade,
                  child: SlideTransition(
                    position: _entrySlide,
                    child: _buildEmptyState(),
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildSortBar(),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final grid = _gridDelegateFor(constraints.crossAxisExtent);
                    return SliverGrid.builder(
                      gridDelegate: grid,
                      itemCount: _sortedItems.length,
                      itemBuilder: (context, index) {
                        final item = _sortedItems[index];
                        return AppearOnMount(
                          delay: staggerDelay(index, step: 45),
                          child: _buildWishlistCard(item),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final count = _items.length;
    final countLabel = _isLoading
        ? 'LOADING'
        : '$count ${count == 1 ? "SAVED ITEM" : "SAVED ITEMS"}';
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 212,
      backgroundColor: _kPrimary,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.maybePop(context),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
        background: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(28)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Gradient backdrop
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kPrimary, _kPrimaryDark],
                  ),
                ),
              ),
              // Large translucent heart — the visual anchor that gives the
              // hero its identity without competing with the foreground text.
              Positioned(
                right: -34,
                top: 10,
                child: Icon(
                  Icons.favorite_rounded,
                  size: 178,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
              // Warm accent orb so the banner doesn't read as a flat block.
              Positioned(
                left: -42,
                bottom: -52,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kAccent.withValues(alpha: 0.18),
                  ),
                ),
              ),
              // Tiny dot accent for a touch of rhythm.
              Positioned(
                left: 88,
                top: 28,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              // Foreground content
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 62, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.26),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            color: Color(0xFFFFB4B4),
                            size: 13,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            countLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'My Wishlist',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Everything you love, ready when you are.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
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

  // ── Sort bar ──────────────────────────────────────────────────────────

  Widget _buildSortBar() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _sortChip('Most recent', _SortOrder.recent, Icons.access_time_rounded),
          const SizedBox(width: 8),
          _sortChip(
            'Lowest price',
            _SortOrder.priceLow,
            Icons.arrow_downward_rounded,
          ),
          const SizedBox(width: 8),
          _sortChip(
            'Highest price',
            _SortOrder.priceHigh,
            Icons.arrow_upward_rounded,
          ),
        ],
      ),
    );
  }

  Widget _sortChip(String label, _SortOrder order, IconData icon) {
    final selected = _sort == order;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _sort = order),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _kPrimary : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? _kPrimary : const Color(0xFFE5EAF5),
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x332A4BA0),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: selected ? Colors.white : _kPrimaryDark,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Wishlist card (grid) ──────────────────────────────────────────────

  Widget _buildWishlistCard(Map<String, dynamic> item) {
    final imageUrl = item['image_url']?.toString() ?? '';
    final name = item['product_name']?.toString() ?? 'Product';
    final price = item['price'];
    final storeName = item['store_name']?.toString() ?? '';
    final productId = item['product_id']?.toString() ?? '';
    final isRemoving = _removingIds.contains(productId);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: isRemoving ? 0.4 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8EDF6)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isRemoving ? null : () => _openProduct(productId),
            splashColor: const Color(0x222A4BA0),
            highlightColor: const Color(0x112A4BA0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image area
                AspectRatio(
                  aspectRatio: 1.05,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ProductImage(url: imageUrl),
                      // Top-right heart action sits on the image
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _RemoveHeartButton(
                          onPressed: isRemoving
                              ? null
                              : () => _removeFromWishlist(productId),
                        ),
                      ),
                      // Subtle bottom gradient — keeps store text legible
                      // when the image is bright.
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.center,
                              colors: [
                                Color(0x33000000),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (storeName.isNotEmpty)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          right: 8,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.store_mall_directory_rounded,
                                      size: 10,
                                      color: _kPrimaryDark,
                                    ),
                                    const SizedBox(width: 4),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 110,
                                      ),
                                      child: Text(
                                        storeName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: _kPrimaryDark,
                                        ),
                                      ),
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
                // Details strip
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '₱${_formatPrice(price)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: _kPrimaryDark,
                              ),
                            ),
                          ),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: _kPrimary,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x332A4BA0),
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
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
      ),
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────

  Widget _buildSkeletonCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EDF6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.05,
            child: ShimmerBox(
              height: double.infinity,
              width: double.infinity,
              borderRadius: BorderRadius.zero,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(
                  height: 12,
                  width: double.infinity,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 6),
                ShimmerBox(
                  height: 10,
                  width: 90,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ShimmerBox(
                      height: 14,
                      width: 70,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    const Spacer(),
                    ShimmerBox(
                      height: 28,
                      width: 28,
                      borderRadius: BorderRadius.circular(8),
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

  // ── Empty state ───────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEEF2FF),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x142A4BA0),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: _kPrimary,
                    size: 36,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Nothing saved yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the heart on a product to start building your wishlist.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFF6B7280),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => Navigator.maybePop(context),
              style: FilledButton.styleFrom(
                backgroundColor: _kPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.storefront_rounded, size: 18),
              label: const Text(
                'Browse the plaza',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Models / helpers ────────────────────────────────────────────────────

enum _SortOrder { recent, priceLow, priceHigh }

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _PlaceholderImage();
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _PlaceholderImage(),
      errorBuilder: (_, _, _) => const _PlaceholderImage(),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF1F3F9),
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          color: Color(0xFFB6BDCC),
          size: 32,
        ),
      ),
    );
  }
}

class _RemoveHeartButton extends StatefulWidget {
  const _RemoveHeartButton({this.onPressed});
  final VoidCallback? onPressed;

  @override
  State<_RemoveHeartButton> createState() => _RemoveHeartButtonState();
}

class _RemoveHeartButtonState extends State<_RemoveHeartButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onPressed == null) return;
    if (mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        scale: _pressed ? 0.9 : 1,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed,
            splashColor: const Color(0x33EF4444),
            highlightColor: const Color(0x14EF4444),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.95),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F0F172A),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.favorite_rounded,
                color: enabled
                    ? const Color(0xFFEF4444)
                    : const Color(0xFFB6BDCC),
                size: 17,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
