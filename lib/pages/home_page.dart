import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cart_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<dynamic> products = [];
  bool isLoading = true;
  String _selectedFilter = 'All';
  String _greetingName = 'Shopper';

  final List<String> _filters = const [
    'All',
    'Fish',
    'Meat',
    'Vegetables',
    'Fruits',
  ];

  // Define the default local asset path
  static const String _defaultAssetPath = "assets/img/kasim.jpg";

  static const List<Map<String, dynamic>> _fallbackProducts = [
    {
      'product_name': 'Fresh Tilapia',
      'store_name': 'Fish Vendor - Lane A',
      'price': 180,
      'image_url': 'assets/img/tilapia.jpg',
    },
    {
      'product_name': 'Pork Kasim',
      'store_name': 'Meat Stall - Row B',
      'price': 320,
      'image_url': 'assets/img/kasim.jpg',
    },
    {
      'product_name': 'Pork Liempo',
      'store_name': 'Meat Stall - Row B',
      'price': 360,
      'image_url': 'assets/img/Liempo.png',
    },
    {
      'product_name': 'Mixed Vegetables',
      'store_name': 'Gulayan - Central Row',
      'price': 75,
      'image_url': 'assets/img/categories/vege.jpg',
    },
    {
      'product_name': 'Seasonal Fruits',
      'store_name': 'Fruit Stand - Gate 2',
      'price': 95,
      'image_url': 'assets/img/categories/fruits.jpg',
    },
    {
      'product_name': 'Fresh Bangus',
      'store_name': 'Fish Vendor - Lane A',
      'price': 210,
      'image_url': 'assets/img/categories/fishesh.jpg',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadGreetingName();
    fetchProducts();
  }

  Future<void> _loadGreetingName() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) return;

    String? name;

    try {
      final profile = await client
          .from('profile')
          .select('name')
          .eq('user_id', user.id)
          .maybeSingle();

      final profileName = profile?['name']?.toString().trim();
      if (profileName != null && profileName.isNotEmpty) {
        name = profileName;
      }
    } catch (_) {
      // Fall back to auth metadata/email when profile row is unavailable.
    }

    name ??=
        user.userMetadata?['name']?.toString().trim() ??
        user.userMetadata?['full_name']?.toString().trim();

    final emailPrefix = user.email?.split('@').first.trim();
    if ((name == null || name.isEmpty) &&
        emailPrefix != null &&
        emailPrefix.isNotEmpty) {
      name = emailPrefix;
    }

    if (name == null || name.isEmpty || !mounted) return;

    setState(() {
      _greetingName = _formatDisplayName(name!);
    });
  }

  String _formatDisplayName(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }

  Future<void> fetchProducts() async {
    if (mounted) {
      setState(() => isLoading = true);
    }

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
    } catch (e) {
      debugPrint("FETCH ERROR → $e");
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  List<dynamic> _productsForFilter() {
    final List<Map<String, dynamic>> normalized = _normalizedProducts();

    if (_selectedFilter == 'All') return normalized;

    final keywords = <String>{};
    switch (_selectedFilter) {
      case 'Fish':
        keywords.addAll({'fish', 'tilapia', 'bangus', 'tuna', 'galunggong'});
        break;
      case 'Meat':
        keywords.addAll({'beef', 'pork', 'chicken', 'liempo', 'meat'});
        break;
      case 'Vegetables':
        keywords.addAll({'vegetable', 'tomato', 'onion', 'carrot', 'cabbage'});
        break;
      case 'Fruits':
        keywords.addAll({'fruit', 'banana', 'apple', 'mango', 'orange'});
        break;
    }

    final filtered = normalized.where((p) {
      final name = (p['product_name'] ?? '').toString().toLowerCase();
      return keywords.any(name.contains);
    }).toList();

    // Fallback keeps UI populated if product names do not contain category terms.
    return filtered.isEmpty ? normalized : filtered;
  }

  List<Map<String, dynamic>> _normalizedProducts() {
    final source = products.isEmpty ? _fallbackProducts : products;

    return List<Map<String, dynamic>>.generate(source.length, (index) {
      final item = Map<String, dynamic>.from(source[index] as Map);
      final fallback = _fallbackProducts[index % _fallbackProducts.length];

      String ensureText(String key) {
        final value = item[key]?.toString().trim();
        if (value == null || value.isEmpty) {
          return fallback[key].toString();
        }
        return value;
      }

      dynamic ensurePrice() {
        final value = item['price'];
        if (value == null || value.toString().trim().isEmpty) {
          return fallback['price'];
        }
        return value;
      }

      return {
        'product_name': ensureText('product_name'),
        'store_name': ensureText('store_name'),
        'price': ensurePrice(),
        'image_url': ensureText('image_url'),
      };
    });
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

  void _openCart() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartPage()),
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

    try {
      final existing = await client
          .from('cart')
          .select('id, qty')
          .eq('buyer_id', user.id)
          .eq('product_name', productName)
          .maybeSingle();

      if (existing != null) {
        final currentQty = int.tryParse(existing['qty'].toString()) ?? 1;
        await client
            .from('cart')
            .update({'qty': currentQty + 1})
            .eq('id', existing['id'])
            .eq('buyer_id', user.id);
      } else {
        await client.from('cart').insert({
          'product_name': productName,
          'price': price,
          'qty': 1,
          'buyer_id': user.id,
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
      ).showSnackBar(SnackBar(content: Text('Failed to add item: $e')));
    }
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A4DBE), Color(0xFF2A4BA0)],
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
              Text(
                "Hey, $_greetingName",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Row(
                children: [
                  Stack(
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
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
                          child: const Text(
                            '3',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: _openCart,
                    child: const Icon(
                      Icons.shopping_cart_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            decoration: InputDecoration(
              hintText: "Search products or store",
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Colors.white70,
              ),
              filled: true,
              fillColor: const Color(0xFF173C9E),
              hintStyle: const TextStyle(color: Colors.white70),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.white),
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
                child: _buildInfoPill(
                  label: 'WITHIN',
                  value: 'Today 5AM-7PM',
                  icon: Icons.schedule_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5A524),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Image.asset(
                      'assets/img/categories/vege.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.white.withValues(alpha: 0.25),
                        child: const Icon(
                          Icons.local_offer_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'San Fernando Market Plaza',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Fresh goods from local public market stalls',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
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
        ],
      ),
    );
  }

  Widget _buildCategoryFilters() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isActive = filter == _selectedFilter;

          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              setState(() => _selectedFilter = filter);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: isActive ? const Color(0xFF1A4DBE) : Colors.white,
                border: Border.all(
                  color: isActive
                      ? const Color(0xFF1A4DBE)
                      : Colors.grey.shade300,
                ),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () {},
          child: const Text(
            'See all',
            style: TextStyle(
              color: Color(0xFF1A4DBE),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFlashDealCard(dynamic product) {
    final imageUrl = (product['image_url'] as String?)?.trim();
    final resolvedImage = (imageUrl == null || imageUrl.isEmpty)
        ? _defaultAssetPath
        : imageUrl;

    final priceValue = product['price'];
    final priceText = priceValue != null ? "₱$priceValue /kg" : "₱0";

    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 76,
              height: 76,
              child: _buildProductImage(resolvedImage),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _productName(product, 'Market Product'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  priceText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A4DBE),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1D7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Limited Deal',
                    style: TextStyle(
                      color: Color(0xFFE48E00),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEssentialsGrid(List<dynamic> filteredProducts) {
    final essentials = filteredProducts.take(4).toList();

    if (essentials.isEmpty) {
      return const SizedBox.shrink();
    }

    return GridView.builder(
      itemCount: essentials.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.45,
      ),
      itemBuilder: (context, index) {
        final p = essentials[index];
        final imageUrl = (p['image_url'] as String?)?.trim();
        final resolvedImage = (imageUrl == null || imageUrl.isEmpty)
            ? _defaultAssetPath
            : imageUrl;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
                child: SizedBox(
                  width: 68,
                  height: double.infinity,
                  child: _buildProductImage(resolvedImage),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _productName(p, 'Fresh Item'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Restock now',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductImage(String imagePath) {
    if (_isAssetPath(imagePath)) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const ColoredBox(
          color: Color(0xFFF1F3F9),
          child: Icon(Icons.image_not_supported_outlined),
        ),
      );
    }

    return Image.network(
      imagePath,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          Image.asset(_defaultAssetPath, fit: BoxFit.cover),
    );
  }

  bool _isAssetPath(String path) {
    return path.startsWith('assets/') || path.startsWith('images/');
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _productsForFilter();
    final flashProducts = filteredProducts.take(6).toList();
    final recommendedProducts = filteredProducts.take(10).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FB),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: fetchProducts,
          color: const Color(0xFF1A4DBE),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            children: [
              _buildTopHeader(),
              const SizedBox(height: 14),
              _buildCategoryFilters(),
              const SizedBox(height: 20),
              _buildSectionHeader(
                'Flash Deals',
                'Limited picks from San Fernando market stalls',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : flashProducts.isEmpty
                    ? const Center(child: Text("No products yet."))
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: flashProducts.length,
                        itemBuilder: (context, index) {
                          return _buildFlashDealCard(flashProducts[index]);
                        },
                      ),
              ),
              const SizedBox(height: 20),
              _buildSectionHeader(
                'Recommended',
                'Popular items in the public market today',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 230,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : recommendedProducts.isEmpty
                    ? const Center(child: Text("No products yet."))
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: recommendedProducts.length,
                        itemBuilder: (context, i) {
                          final p = recommendedProducts[i];

                          final imageUrl = (p['image_url'] as String?)?.trim();
                          final resolvedImage =
                              (imageUrl == null || imageUrl.isEmpty)
                              ? _defaultAssetPath
                              : imageUrl;

                          final priceValue = p['price'];
                          final priceText = priceValue != null
                              ? "₱$priceValue /kg"
                              : "₱0";

                          return ProductCard(
                            title: _productName(p, 'Fresh Item'),
                            storeName: _storeName(p, 'San Fernando Stall'),
                            price: priceText,
                            imageUrl: resolvedImage,
                            onAddPressed: () {
                              _addToCart(p);
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 18),
              _buildSectionHeader(
                'Daily Essentials',
                'Everyday staples from trusted plaza vendors',
              ),
              const SizedBox(height: 12),
              _buildEssentialsGrid(filteredProducts),
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
  final VoidCallback onAddPressed;

  const ProductCard({
    super.key,
    required this.title,
    required this.storeName,
    required this.price,
    required this.imageUrl,
    required this.onAddPressed,
  });

  // Helper method to check if the path is likely a local asset
  bool _isAssetPath(String path) {
    return path.startsWith('assets/') || path.startsWith('images/');
  }

  @override
  Widget build(BuildContext context) {
    final Widget imageWidget = _isAssetPath(imageUrl)
        ? Image.asset(
            imageUrl,
            height: 112,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const ColoredBox(
              color: Color(0xFFF1F3F9),
              child: Center(child: Text('Asset Error')),
            ),
          )
        : Image.network(
            imageUrl,
            height: 112,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Image.asset(
              "assets/img/kasim.jpg",
              height: 112,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          );

    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageWidget,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          Text(
            storeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  price,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                ),
              ),
              InkWell(
                onTap: onAddPressed,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A4DBE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
