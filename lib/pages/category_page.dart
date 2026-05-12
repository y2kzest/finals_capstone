import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cart_badge_service.dart';
import 'cart_page.dart';
import 'categorylist.dart';

class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  String? selectedCategory; // null = show grid; not null = show CategoryList
  String _greetingName = 'Shopper';

  final List<Map<String, String>> _categories = const [
    {
      'title': 'Fishes',
      'subtitle': 'Daily sea catch',
      'image': 'assets/img/categories/fishesh.jpg',
      'badge': 'Fresh',
    },
    {
      'title': 'Meats',
      'subtitle': 'Premium cuts',
      'image': 'assets/img/categories/meats.jpg',
      'badge': 'Top',
    },
    {
      'title': 'Vegetables',
      'subtitle': 'Farm harvest',
      'image': 'assets/img/categories/vege.jpg',
      'badge': 'Green',
    },
    {
      'title': 'Fruits',
      'subtitle': 'Sweet picks',
      'image': 'assets/img/categories/fruits.jpg',
      'badge': 'New',
    },
    {
      'title': 'Apparel',
      'subtitle': 'Shirts & more',
      'image': 'assets/img/appareljpeg.jpg',
      'badge': 'New',
    },
    {
      'title': 'Karinderya',
      'subtitle': 'Cooked meals & ulam',
      'image': 'assets/img/karindirya.jpg',
      'badge': 'Hot',
    },
  ];

  @override
  void initState() {
    super.initState();
    CartBadgeService.instance.ensureInitialized();
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

  void _openCart() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartPage()),
    );
  }

  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
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
              Text(
                'Hey, $_greetingName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: _openCart,
                    child: ValueListenableBuilder<int>(
                      valueListenable: CartBadgeService.instance.count,
                      builder: (context, cartCount, _) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            Icons.shopping_cart_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                          if (cartCount > 0)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 16,
                                height: 16,
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
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Shop',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w400,
            ),
          ),
          const Text(
            'By Category',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              height: 1.0,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.local_offer_outlined, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Save up to 50% in selected categories today',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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

  @override
  Widget build(BuildContext context) {
    // When user selects a category
    if (selectedCategory != null) {
      return CategoryListPage(
        category: selectedCategory!,
        onBack: () => setState(() => selectedCategory = null),
      );
    }

    // Default category grid
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FB),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            _buildHeroHeader(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.flash_on_rounded,
                          color: Color(0xFFF9B023),
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Trending now',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.local_shipping_outlined,
                          color: Color(0xFF2A4BA0),
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Fast delivery',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _SectionEyebrow(label: 'MARKET AISLES'),
                      SizedBox(height: 10),
                      Text(
                        'Browse Categories',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Choose where you want to shop today',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2A4BA0),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFFE5EAF5)),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See all',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              itemCount: _categories.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, index) {
                final item = _categories[index];
                return CategoryCard(
                  title: item['title']!,
                  subtitle: item['subtitle']!,
                  badge: item['badge']!,
                  imagePath: item['image']!,
                  onTap: () =>
                      setState(() => selectedCategory = item['title']!),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String badge;
  final String imagePath;
  final VoidCallback? onTap;

  const CategoryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.imagePath,
    this.onTap,
  });

  @override
  State<CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<CategoryCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.985 : (_hovered ? 1.01 : 1.0);
    final yOffset = _pressed ? 2.0 : (_hovered ? -4.0 : 0.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        scale: scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          transform: Matrix4.translationValues(0, yOffset, 0),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onTap,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
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
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(18),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.asset(
                                    widget.imagePath,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              color: const Color(0xFFEAEFF9),
                                              alignment: Alignment.center,
                                              child: Text(
                                                widget.title,
                                                style: const TextStyle(
                                                  color: Color(0xFF8A95AD),
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.06),
                                          Colors.black.withValues(alpha: 0.22),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                widget.badge,
                                style: const TextStyle(
                                  color: Color(0xFF6A4700),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A4BA0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionEyebrow extends StatelessWidget {
  final String label;

  const _SectionEyebrow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE7EEFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Color(0xFF2A4BA0),
        ),
      ),
    );
  }
}
