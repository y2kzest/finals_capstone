import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'productlist.dart';

class CategoryListPage extends StatefulWidget {
  final String category;
  final VoidCallback? onBack;

  const CategoryListPage({super.key, required this.category, this.onBack});

  @override
  State<CategoryListPage> createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  String _greetingName = 'Shopper';
  String _selectedSort = 'Popular';

  final List<String> _fishSortOptions = const [
    'Popular',
    'Low Price',
    'Small Fishes',
    'Big Fishes',
  ];
  final List<String> _defaultSortOptions = const ['Popular', 'Low Price'];

  @override
  void initState() {
    super.initState();
    _loadGreetingName();
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
      _greetingName = name![0].toUpperCase() + name.substring(1);
    });
  }

  List<_CategoryProduct> _baseProductsForCategory() {
    switch (widget.category) {
      case 'Fishes':
      case 'Meats & Fishes':
        return const [
          _CategoryProduct(name: 'Dalagang bukid', price: 230),
          _CategoryProduct(name: 'Bangus', price: 220),
          _CategoryProduct(name: 'Tilapia', price: 180),
          _CategoryProduct(name: 'Hipon', price: 350),
          _CategoryProduct(name: 'Galunggong', price: 160),
          _CategoryProduct(name: 'Pusit', price: 320),
        ];
      case 'Meats':
        return const [
          _CategoryProduct(name: 'Pork Liempo', price: 345),
          _CategoryProduct(name: 'Chicken Breast', price: 255),
          _CategoryProduct(name: 'Ground Beef', price: 390),
          _CategoryProduct(name: 'Pork Kasim', price: 310),
          _CategoryProduct(name: 'Chicken Wings', price: 240),
          _CategoryProduct(name: 'Beef Brisket', price: 420),
        ];
      case 'Vegetables':
        return const [
          _CategoryProduct(name: 'Tomato', price: 85),
          _CategoryProduct(name: 'Carrot', price: 90),
          _CategoryProduct(name: 'Cabbage', price: 70),
          _CategoryProduct(name: 'Pechay', price: 60),
          _CategoryProduct(name: 'Eggplant', price: 95),
          _CategoryProduct(name: 'Onion', price: 110),
        ];
      case 'Fruits':
        return const [
          _CategoryProduct(name: 'Mango', price: 140),
          _CategoryProduct(name: 'Banana', price: 85),
          _CategoryProduct(name: 'Apple', price: 180),
          _CategoryProduct(name: 'Orange', price: 160),
          _CategoryProduct(name: 'Papaya', price: 95),
          _CategoryProduct(name: 'Pineapple', price: 120),
        ];
      default:
        return const [
          _CategoryProduct(name: 'Delivery Assist', price: 50),
          _CategoryProduct(name: 'Packing Service', price: 35),
          _CategoryProduct(name: 'Express Checkout', price: 45),
          _CategoryProduct(name: 'Priority Support', price: 60),
        ];
    }
  }

  List<String> _activeSortOptions() {
    if (widget.category == 'Fishes' || widget.category == 'Meats & Fishes') {
      return _fishSortOptions;
    }
    return _defaultSortOptions;
  }

  List<_CategoryProduct> _productsForSort(String sort) {
    final items = List<_CategoryProduct>.from(_baseProductsForCategory());

    if (sort == 'Low Price') {
      items.sort((a, b) => a.price.compareTo(b.price));
      return items;
    }

    if (sort == 'Small Fishes') {
      final smallFishKeywords = {'dalagang', 'tilapia', 'galunggong'};
      final filtered = items.where((item) {
        final lowerName = item.name.toLowerCase();
        return smallFishKeywords.any(lowerName.contains);
      }).toList();
      return filtered.isEmpty ? items : filtered;
    }

    if (sort == 'Big Fishes') {
      final bigFishKeywords = {'bangus', 'hipon', 'pusit'};
      final filtered = items.where((item) {
        final lowerName = item.name.toLowerCase();
        return bigFishKeywords.any(lowerName.contains);
      }).toList();
      return filtered.isEmpty ? items : filtered;
    }

    return items;
  }

  void _openProductList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProductListPage()),
    );
  }

  void _showAddedMessage(String name) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$name added to cart')));
  }

  @override
  Widget build(BuildContext context) {
    final options = _activeSortOptions();
    final effectiveSort = options.contains(_selectedSort)
        ? _selectedSort
        : options.first;
    final products = _productsForSort(effectiveSort);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FB),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFF2F4FA),
                          foregroundColor: Colors.black87,
                        ),
                        icon: const Icon(Icons.chevron_left),
                        onPressed:
                            widget.onBack ??
                            () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.black87),
                        onPressed: () {},
                      ),
                      Stack(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.notifications_none,
                              color: Colors.black87,
                            ),
                            onPressed: () {},
                          ),
                          Positioned(
                            right: 7,
                            top: 7,
                            child: Container(
                              height: 14,
                              width: 14,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF5A524),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '3',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Hey, $_greetingName',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A4DBE),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: options.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final isActive = option == effectiveSort;
                        return InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () {
                            setState(() {
                              _selectedSort = option;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFFF5A524)
                                  : const Color(0xFFF2F4FA),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              option,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isActive ? Colors.white : Colors.black54,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              itemCount: products.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.72,
              ),
              itemBuilder: (context, index) {
                final product = products[index];
                return CategoryItemCard(
                  title: product.name,
                  price: '₱${product.price}',
                  onTap: _openProductList,
                  onAddTap: () => _showAddedMessage(product.name),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryItemCard extends StatelessWidget {
  final String title;
  final String price;
  final VoidCallback? onTap;
  final VoidCallback? onAddTap;

  const CategoryItemCard({
    super.key,
    required this.title,
    required this.price,
    this.onTap,
    this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4FA),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E8F1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 92,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFEDEFF5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.image_outlined, color: Color(0xFFADB4C4)),
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        price,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onAddTap,
                  borderRadius: BorderRadius.circular(999),
                  child: const CircleAvatar(
                    radius: 11,
                    backgroundColor: Color(0xFF2A4BA0),
                    child: Icon(Icons.add, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryProduct {
  final String name;
  final int price;

  const _CategoryProduct({required this.name, required this.price});
}
