import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  static const _kPrimary = Color(0xFF1A4DBE);
  static const _kSurface = Color(0xFFF5F6FB);
  static const _kCard = Colors.white;
  static const _kTextPrimary = Color(0xFF111827);
  static const _kTextSecondary = Color(0xFF6B7280);

  final _sortOptions = const ['Newest', 'Low Price', 'High Price'];

  @override
  void initState() {
    super.initState();
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

  // Map display category title -> DB value stored in product.category
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
              '*, seller_profiles!product_seller_id_fkey(store_name, is_open, opening_time, closing_time, approval_status)')
          .ilike('category', _dbCategory())
          .order('id', ascending: false);

      final all = List<Map<String, dynamic>>.from(resp);

      // Only show products from approved sellers (= published)
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
      // Fallback without join
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
      if (productId != null) {
        existing = await client
            .from('cart')
            .select('id, qty')
            .eq('buyer_id', user.id)
            .eq('product_id', productId)
            .maybeSingle();
      }
      existing ??= await client
          .from('cart')
          .select('id, qty')
          .eq('buyer_id', user.id)
          .eq('product_name', productName)
          .maybeSingle();

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

  Widget _buildOpenBadge(Map<String, dynamic> p) {
    final open = _isShopOpen(p);
    final openTime = p['opening_time']?.toString() ?? '05:00';
    final closeTime = p['closing_time']?.toString() ?? '19:00';
    final color =
        open ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final label =
        open ? 'Open \u00b7 Closes ${to12Hour(closeTime)}' : 'Closed \u00b7 Opens ${to12Hour(openTime)}';
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

  Widget _buildProductCard(Map<String, dynamic> p) {
    final name = p['product_name'].toString();
    final imageUrl = p['image_url'].toString();
    final price = p['price'];
    final unit = p['unit_type'].toString();
    final storeName = p['store_name'].toString();

    return GestureDetector(
      onTap: () => _openProductDetail(p),
      child: Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: SizedBox(
                width: double.infinity,
                height: 110,
                child: _buildProductImage(imageUrl),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _kTextPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: _kTextSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      price != null ? '\u20b1$price / $unit' : '\u2014',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kPrimary),
                    ),
                    const SizedBox(height: 4),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _addToCart(p),
                        icon: const Icon(Icons.add_shopping_cart_rounded,
                            size: 14),
                        label: const Text('Add to Cart',
                            style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products =
        _isLoading ? <Map<String, dynamic>>[] : _filteredAndSorted();

    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: RefreshIndicator(
          color: _kPrimary,
          onRefresh: _fetchProducts,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // -- Header / search bar --------------------------
              Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A4DBE), Color(0xFF2A4BA0)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x221A4DBE),
                        blurRadius: 18,
                        offset: Offset(0, 8)),
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
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color:
                                  Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.chevron_left,
                                color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.category,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                        ),
                        GestureDetector(
                          onTap: _openCart,
                          child: const Icon(
                              Icons.shopping_cart_outlined,
                              color: Colors.white,
                              size: 26),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search in ${widget.category}...',
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: Colors.white70),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white70, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF173C9E),
                        hintStyle:
                            const TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // -- Sort chips ------------------------------------
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _sortOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final opt = _sortOptions[i];
                    final active = opt == _selectedSort;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedSort = opt),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color:
                              active ? _kPrimary : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: active
                                  ? _kPrimary
                                  : Colors.grey.shade300),
                        ),
                        child: Text(
                          opt,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // -- Products --------------------------------------
              if (_isLoading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: CircularProgressIndicator(color: _kPrimary),
                ))
              else if (products.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      Icon(Icons.search_off_rounded,
                          size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No products found for "$_searchQuery"'
                            : 'No products available in ${widget.category} yet.',
                        style: TextStyle(
                            fontSize: 15, color: Colors.grey[600]),
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
                GridView.builder(
                  itemCount: products.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.68,
                  ),
                  itemBuilder: (context, i) =>
                      _buildProductCard(products[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
