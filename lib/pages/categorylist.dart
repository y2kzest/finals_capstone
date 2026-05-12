import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cart_badge_service.dart';
import '../utils/helpers.dart';
import 'cart_page.dart';
import 'productdet.dart';

class CategoryListPage extends StatefulWidget {
  final String category;
  final VoidCallback? onBack;

  const CategoryListPage({super.key, required this.category, this.onBack});

  @override
  State<CategoryListPage> createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedSort = 'Newest';
  final TextEditingController _searchController = TextEditingController();

  static const _kPrimary = Color(0xFF2A4BA0);
  static const _kSurface = Color(0xFFF5F6FB);
  static const _kCard = Colors.white;
  static const _kTextPrimary = Color(0xFF111827);
  static const _kTextSecondary = Color(0xFF6B7280);

  final _sortOptions = const ['Newest', 'Low Price', 'High Price'];

  @override
  void initState() {
    super.initState();
    CartBadgeService.instance.ensureInitialized();
    _fetchProducts();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _dbCategory() {
    switch (widget.category) {
      case 'Fishes':
        return 'Fish';
      case 'Meats':
        return 'Meat';
      case 'Vegetables':
        return 'Vegetable';
      case 'Fruits':
        return 'Fruit';
      case 'Services':
        return 'Service';
      case 'Apparel':
        return 'Apparel';
      case 'Karinderya':
        return 'Karinderya';
      default:
        return widget.category;
    }
  }

  Future<void> _fetchProducts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final resp = await Supabase.instance.client
          .from('product')
          .select(
            '*, seller_profiles!product_seller_id_fkey(store_name, is_open, opening_time, closing_time, approval_status)',
          )
          .ilike('category', _dbCategory())
          .order('id', ascending: false);

      final all = List<Map<String, dynamic>>.from(resp);

      final published = all.where((p) {
        final sp = p['seller_profiles'];
        if (sp is Map) return sp['approval_status'] == 'approved';
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _products = published;
          _isLoading = false;
        });
      }
    } catch (_) {
      try {
        final resp = await Supabase.instance.client
            .from('product')
            .select()
            .ilike('category', _dbCategory())
            .order('id', ascending: false);

        if (mounted) {
          setState(() {
            _products = List<Map<String, dynamic>>.from(resp);
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> raw) {
    String storeName = 'Market Stall';
    bool sellerIsOpen = false;
    String openTime = '05:00';
    String closeTime = '19:00';
    final sp = raw['seller_profiles'];
    if (sp is Map) {
      if (sp['store_name'] != null) storeName = sp['store_name'].toString();
      sellerIsOpen = sp['is_open'] == true;
      openTime = sp['opening_time']?.toString() ?? '05:00';
      closeTime = sp['closing_time']?.toString() ?? '19:00';
    }

    return {
      'product_name':
          (raw['name'] ?? raw['product_name'] ?? 'Fresh Item').toString(),
      'store_name': storeName,
      'price': raw['price'] ?? 0,
      'image_url': (raw['image_url'] ?? '').toString().trim(),
      'category': (raw['category'] ?? '').toString(),
      'unit_type': (raw['unit_type'] ?? 'Kg').toString(),
      'id': raw['id'],
      'seller_id': raw['seller_id'] ?? raw['user_id'],
      'description': (raw['description'] ?? '').toString(),
      'is_db': true,
      'seller_is_open': sellerIsOpen,
      'opening_time': openTime,
      'closing_time': closeTime,
      'product_type': (raw['product_type'] ?? 'retail').toString(),
      'pricing_basis': (raw['pricing_basis'] ?? '').toString(),
      'prep_time': (raw['prep_time'] ?? '').toString(),
      'variants': (raw['variants'] ?? '').toString(),
      'daily_available': raw['daily_available'] ?? true,
    };
  }

  bool _isShopOpen(Map<String, dynamic> p) {
    if (p['seller_is_open'] != true) return false;
    try {
      final now = TimeOfDay.now();
      final openParts = p['opening_time'].toString().split(':');
      final closeParts = p['closing_time'].toString().split(':');
      final openMin =
          int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
      final closeMin =
          int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
      final nowMin = now.hour * 60 + now.minute;
      return nowMin >= openMin && nowMin <= closeMin;
    } catch (_) {
      return p['seller_is_open'] == true;
    }
  }

  Widget _buildOpenBadge(Map<String, dynamic> p) {
    final open = _isShopOpen(p);
    final openTime = p['opening_time']?.toString() ?? '05:00';
    final closeTime = p['closing_time']?.toString() ?? '19:00';
    final color =
        open ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final label = open
        ? 'Open \u00b7 Closes ${to12Hour(closeTime)}'
        : 'Closed \u00b7 Opens ${to12Hour(openTime)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  List<Map<String, dynamic>> _filteredAndSorted() {
    final normalized = _products.map(_normalize).toList();

    List<Map<String, dynamic>> results = normalized;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      results = normalized.where((p) {
        return p['product_name'].toString().toLowerCase().contains(q) ||
            p['store_name'].toString().toLowerCase().contains(q);
      }).toList();
    }

    switch (_selectedSort) {
      case 'Low Price':
        results.sort(
            (a, b) => (a['price'] as num).compareTo(b['price'] as num));
        break;
      case 'High Price':
        results.sort(
            (a, b) => (b['price'] as num).compareTo(a['price'] as num));
        break;
    }

    return results;
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login first.')));
      return;
    }

    final productName = product['product_name'].toString();
    final productId = product['id']?.toString();
    final sellerId = product['seller_id']?.toString();

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
        final qty = int.tryParse(existing['qty'].toString()) ?? 1;
        await client
            .from('cart')
            .update({'qty': qty + 1})
            .eq('id', existing['id'])
            .eq('buyer_id', user.id);
      } else {
        await client.from('cart').insert({
          'product_name': productName,
          'price': product['price'],
          'qty': 1,
          'buyer_id': user.id,
          'seller_id': sellerId,
          'product_id': productId,
          'image_url': product['image_url'],
          'store_name': product['store_name'],
          'unit_type': product['unit_type'],
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$productName added to cart')));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Database error: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to add item: $e')));
    }
  }

  void _openCart() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const CartPage()));
  }

  void _openProductDetail(Map<String, dynamic> product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductViewPage(product: product)),
    );
  }

  Widget _buildProductImage(String imageUrl) {
    if (imageUrl.isEmpty) return _imagePlaceholder();
    if (_isAssetPath(imageUrl)) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imagePlaceholder(),
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : _imagePlaceholder(),
      errorBuilder: (_, __, ___) => _imagePlaceholder(),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFFF1F3F9),
      child: const Center(
          child:
              Icon(Icons.image_outlined, size: 36, color: Color(0xFFB6BDCC))),
    );
  }
  bool _isAssetPath(String path) {
    return path.startsWith('assets/') || path.startsWith('images/');
  }

  Widget _buildHeroPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
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

  Widget _buildProductCard(Map<String, dynamic> p, {bool compact = false}) {
    final name = p['product_name'].toString();
    final imageUrl = p['image_url'].toString();
    final price = p['price'];
    final unit = p['unit_type'].toString();
    final isOpen = _isShopOpen(p);
    final statusColor =
        isOpen ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final categoryLabel =
      (p['category'] ?? widget.category).toString().trim();
    final imageHeight = compact ? 108.0 : 122.0;
    final titleSize = compact ? 13.0 : 14.0;
    final storeSize = compact ? 11.0 : 12.0;
    final priceSize = compact ? 13.0 : 14.0;
    final storeName = p['store_name'].toString();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openProductDetail(p),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(22),
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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                child: SizedBox(
                  width: double.infinity,
                  height: imageHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildProductImage(imageUrl),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.04),
                              Colors.black.withValues(alpha: 0.24),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 8, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                isOpen ? 'Open' : 'Closed',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: statusColor,
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: titleSize,
                                height: 1.15,
                                color: _kTextPrimary,
                              ),
                            ),
                          ),
                          if (categoryLabel.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _categoryPill(categoryLabel),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.store_mall_directory_outlined,
                            size: 13,
                            color: _kTextSecondary,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              storeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: storeSize,
                                color: _kTextSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (p['product_type'] == 'karinderya') ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B35).withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Cooked',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFD4500A),
                                ),
                              ),
                            ),
                            if ((p['prep_time'] as String).isNotEmpty) ...[
                              const SizedBox(width: 5),
                              Icon(
                                Icons.schedule_rounded,
                                size: 10,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                p['prep_time'].toString(),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      _buildOpenBadge(p),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              price != null ? '₱$price / $unit' : '—',
                              style: TextStyle(
                                fontSize: priceSize,
                                fontWeight: FontWeight.w800,
                                color: _kPrimary,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _addToCart(p),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: _kPrimary,
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
  }

  Widget _categoryPill(String label) {
    Color? color;
    switch (label.toLowerCase()) {
      case 'fish':
        color = const Color(0xFF3D5BBD);
        break;
      case 'meat':
      case 'meats':
        color = const Color(0xFFC45C36);
        break;
      case 'vegetable':
      case 'vegetables':
        color = const Color(0xFF42A815);
        break;
      case 'fruit':
      case 'fruits':
        color = const Color(0xFFD8E40F);
        break;
      case 'karinderya':
        color = const Color(0xFFCB8425);
        break;
      case 'apparel':
        color = const Color(0xFF0E2E39);
        break;
    }
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

  @override
  Widget build(BuildContext context) {
    final products =
        _isLoading ? <Map<String, dynamic>>[] : _filteredAndSorted();
    final heroSubtitle = _isLoading
        ? 'Loading fresh finds from trusted plaza vendors'
        : '${products.length} pick${products.length == 1 ? '' : 's'} in ${widget.category.toLowerCase()}';

    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: RefreshIndicator(
          color: _kPrimary,
          onRefresh: _fetchProducts,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2A4BA0), Color(0xFF153075)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x221A4DBE),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: widget.onBack ??
                              () => Navigator.of(context).maybePop(),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            child: const Icon(
                              Icons.chevron_left,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'MARKET AISLE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                widget.category,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                heroSubtitle,
                                style: const TextStyle(
                                  color: Color(0xFFDCE6FF),
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _openCart,
                          child: ValueListenableBuilder<int>(
                            valueListenable: CartBadgeService.instance.count,
                            builder: (context, cartCount, _) => Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.14),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.shopping_cart_outlined,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                if (cartCount > 0)
                                  Positioned(
                                    right: -4,
                                    top: -4,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF5A524),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '$cartCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search in ${widget.category}...',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFFF8FAFF),
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Color(0xFFE8EEFF),
                                    size: 18,
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
                          hintStyle: const TextStyle(color: Color(0xD9F3F6FF)),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildHeroPill(
                          Icons.grid_view_rounded,
                          '${products.length} results',
                        ),
                        _buildHeroPill(
                          Icons.swap_vert_rounded,
                          _selectedSort,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _sortOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final opt = _sortOptions[i];
                    final active = opt == _selectedSort;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedSort = opt),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: active ? _kPrimary : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: active ? _kPrimary : const Color(0xFFE5E7EB),
                          ),
                          boxShadow: active
                              ? const [
                                  BoxShadow(
                                    color: Color(0x1A2A4BA0),
                                    blurRadius: 12,
                                    offset: Offset(0, 6),
                                  ),
                                ]
                              : const [],
                        ),
                        child: Text(
                          opt,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: CircularProgressIndicator(color: _kPrimary),
                  ),
                )
              else if (products.isEmpty)
                Padding(
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
                            : 'No products available in ${widget.category} yet.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Text('Clear search'),
                        ),
                      ],
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gridSpacing = 12.0;
                    final cardWidth = (constraints.maxWidth - gridSpacing) / 2;
                    final compactCard = cardWidth < 182;
                    final cardHeight = compactCard ? 252.0 : 270.0;

                    return GridView.builder(
                      itemCount: products.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: gridSpacing,
                        mainAxisSpacing: 12,
                        mainAxisExtent: cardHeight,
                      ),
                      itemBuilder: (context, i) =>
                          _buildProductCard(products[i], compact: compactCard),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

