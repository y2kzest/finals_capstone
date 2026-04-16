import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import 'cart_page.dart';
import 'productdet.dart';

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
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _banners = [];

  final List<String> _filters = const [
    'All',
    'Fish',
    'Meat',
    'Vegetables',
    'Fruits',
    'Apparel',
  ];

  @override
  void initState() {
    super.initState();
    _loadGreetingName();
    fetchProducts();
    _fetchNotifications();
    _fetchBanners();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        setState(() => _notifications = List<Map<String, dynamic>>.from(resp));
      }
    } catch (_) {
      // notifications table may not exist yet
    }
  }

  Future<void> _fetchBanners() async {
    try {
      final resp = await Supabase.instance.client
          .from('seller_profiles')
          .select('store_name, banner_url, logo_url, category, opening_time, closing_time, is_open')
          .not('banner_url', 'is', null)
          .eq('approval_status', 'approved')
          .limit(10);
      if (mounted) {
        setState(() => _banners = List<Map<String, dynamic>>.from(resp));
      }
    } catch (_) {
      // banner_url column may not exist yet
    }
  }

  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Text('Notifications',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_notifications.any((n) => n['is_read'] != true))
                      TextButton(
                        onPressed: () async {
                          final client = Supabase.instance.client;
                          final user = client.auth.currentUser;
                          if (user == null) return;
                          try {
                            await client.from('notifications')
                                .update({'is_read': true})
                                .eq('user_id', user.id);
                            _fetchNotifications();
                          } catch (_) {}
                        },
                        child: const Text('Mark all read',
                            style: TextStyle(color: Color(0xFF1A4DBE), fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_off_outlined, size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('No notifications yet', style: TextStyle(color: Colors.grey[500], fontSize: 15)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _notifications.length,
                        itemBuilder: (context, i) {
                          final n = _notifications[i];
                          final isRead = n['is_read'] == true;
                          final type = n['type']?.toString() ?? '';
                          final message = n['message']?.toString() ?? 'Notification';
                          final title = n['title']?.toString() ?? _notifTitle(type);
                          String dateStr = '';
                          try {
                            final dt = DateTime.parse(n['created_at'].toString()).toLocal();
                            final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
                            final amPm = dt.hour >= 12 ? 'PM' : 'AM';
                            dateStr = '${dt.month}/${dt.day} $h:${dt.minute.toString().padLeft(2, '0')} $amPm';
                          } catch (_) {}

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isRead ? Colors.white : const Color(0xFFF0F4FF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: isRead ? const Color(0xFFF3F4F6) : const Color(0xFFD4DEFF)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38, height: 38,
                                  decoration: BoxDecoration(
                                    color: _notifColor(type).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(_notifIcon(type), color: _notifColor(type), size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title,
                                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                                              color: isRead ? const Color(0xFF6B7280) : const Color(0xFF111827))),
                                      const SizedBox(height: 4),
                                      Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280),
                                          height: 1.3)),
                                      if (dateStr.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                                      ],
                                    ],
                                  ),
                                ),
                                if (!isRead)
                                  Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6),
                                      decoration: const BoxDecoration(color: Color(0xFF1A4DBE), shape: BoxShape.circle)),
                              ],
                            ),
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

  String _notifTitle(String type) {
    switch (type) {
      case 'seller_approved': return 'Seller Approved';
      case 'seller_rejected': return 'Application Denied';
      case 'order_placed': return 'New Order';
      case 'order_ready': return 'Order Ready';
      default: return 'Notification';
    }
  }

  IconData _notifIcon(String type) {
    switch (type) {
      case 'seller_approved': return Icons.verified_rounded;
      case 'seller_rejected': return Icons.cancel_rounded;
      case 'order_placed': return Icons.shopping_bag_rounded;
      case 'order_ready': return Icons.check_circle_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _notifColor(String type) {
    switch (type) {
      case 'seller_approved': return const Color(0xFF059669);
      case 'seller_rejected': return const Color(0xFFDC2626);
      case 'order_placed': return const Color(0xFF1A4DBE);
      case 'order_ready': return const Color(0xFF8B5CF6);
      default: return const Color(0xFFF59E0B);
    }
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
      // Join with seller_profiles to get store name + shop hours
      final response = await Supabase.instance.client
          .from('product')
          .select('*, seller_profiles!product_seller_id_fkey(store_name, is_open, opening_time, closing_time)')
          .order('id', ascending: false);

      if (!mounted) return;
      setState(() {
        products = response;
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
        return name.contains(q) || store.contains(q) || cat.contains(q) || desc.contains(q);
      }).toList();
    }

    if (_selectedFilter == 'All') return results;

    // Map filter labels to DB category values + keyword fallbacks
    final categoryMap = <String, String>{
      'Fish': 'fish',
      'Meat': 'meat',
      'Vegetables': 'vegetable',
      'Fruits': 'fruit',
      'Apparel': 'apparel',
    };
    final keywords = <String>{};
    switch (_selectedFilter) {
      case 'Fish':
        keywords.addAll({'fish', 'tilapia', 'bangus', 'tuna', 'galunggong'});
        break;
      case 'Meat':
        keywords.addAll({'beef', 'pork', 'chicken', 'liempo', 'meat', 'kasim'});
        break;
      case 'Vegetables':
        keywords.addAll({'vegetable', 'tomato', 'onion', 'carrot', 'cabbage', 'mixed'});
        break;
      case 'Fruits':
        keywords.addAll({'fruit', 'banana', 'apple', 'mango', 'orange', 'seasonal'});
        break;
      case 'Apparel':
        keywords.addAll({'shirt', 'shoes', 'apparel', 'clothing', 'pants', 'dress'});
        break;
    }

    final categoryValue = categoryMap[_selectedFilter]?.toLowerCase() ?? '';

    final filtered = results.where((p) {
      // Match by DB category field first (most reliable for seller products)
      final cat = (p['category'] ?? '').toString().toLowerCase();
      if (cat.isNotEmpty && cat.contains(categoryValue)) return true;
      // Fallback: keyword match on product name
      final name = (p['product_name'] ?? '').toString().toLowerCase();
      return keywords.any(name.contains);
    }).toList();

    return filtered;
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
      if (joined is Map) {
        if (joined['store_name'] != null) storeName = joined['store_name'].toString();
        sellerIsOpen = joined['is_open'] == true;
        sellerOpenTime = joined['opening_time']?.toString() ?? '05:00';
        sellerCloseTime = joined['closing_time']?.toString() ?? '19:00';
      }

      combined.add({
        'product_name': (raw['name'] ?? raw['product_name'] ?? 'Fresh Item').toString(),
        'store_name': storeName,
        'price': raw['price'] ?? 0,
        'image_url': (raw['image_url'] != null && raw['image_url'].toString().trim().isNotEmpty)
            ? raw['image_url'].toString()
            : '',  // empty = show placeholder
        'category': (raw['category'] ?? '').toString(),
        'unit_type': (raw['unit_type'] ?? 'Kg').toString(),
        'id': raw['id'],
        'seller_id': raw['seller_id'] ?? raw['user_id'],
        'description': (raw['description'] ?? '').toString(),
        'is_db': true,
        'seller_is_open': sellerIsOpen,
        'opening_time': sellerOpenTime,
        'closing_time': sellerCloseTime,
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

  /// Returns true if the seller's shop is currently open (manual toggle + within hours)
  bool _isShopOpen(dynamic product) {
    if (product['is_db'] != true) return true; // fallback products are always "open"
    final isOpen = product['seller_is_open'] == true;
    if (!isOpen) return false;
    try {
      final now = TimeOfDay.now();
      final openParts = (product['opening_time'] ?? '05:00').toString().split(':');
      final closeParts = (product['closing_time'] ?? '19:00').toString().split(':');
      final openMin = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
      final closeMin = int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
      final nowMin = now.hour * 60 + now.minute;
      return nowMin >= openMin && nowMin <= closeMin;
    } catch (_) {
      return isOpen;
    }
  }

  Widget _buildOpenClosedBadge(dynamic product) {
    if (product['is_db'] != true) return const SizedBox.shrink();
    final open = _isShopOpen(product);
    final openTime = (product['opening_time'] ?? '05:00').toString();
    final closeTime = (product['closing_time'] ?? '19:00').toString();
    // Format display like Google Maps: "Closed · Opens 5:00 AM"
    String label;
    Color color;
    if (open) {
      color = const Color(0xFF059669);
      label = 'Open \u00b7 Closes ${to12Hour(closeTime)}';
    } else {
      color = const Color(0xFFDC2626);
      label = 'Closed \u00b7 Opens ${to12Hour(openTime)}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void _openCart() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartPage()),
    );
  }

  void _openProductDetail(dynamic product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductViewPage(product: Map<String, dynamic>.from(product)),
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
            controller: _searchController,
            onChanged: (value) {
              setState(() => _searchQuery = value.trim());
            },
            decoration: InputDecoration(
              hintText: "Search products or store",
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Colors.white70,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
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
          if (_banners.isNotEmpty)
            Column(
              children: [
                SizedBox(
                  height: 130,
                  child: PageView.builder(
                    itemCount: _banners.length,
                    controller: PageController(viewportFraction: 1.0),
                    itemBuilder: (context, index) {
                      final banner = _banners[index];
                      final storeName = banner['store_name'] ?? 'Store';
                      final bannerUrl = banner['banner_url'] as String?;
                      final logoUrl = banner['logo_url'] as String?;
                      final category = banner['category'] ?? '';
                      final isOpen = banner['is_open'] == true;
                      final openTime = banner['opening_time']?.toString() ?? '05:00';
                      final closeTime = banner['closing_time']?.toString() ?? '19:00';
                      // Determine if currently within operating hours
                      bool isWithinHours = false;
                      try {
                        final now = TimeOfDay.now();
                        final openParts = openTime.split(':');
                        final closeParts = closeTime.split(':');
                        final openMinutes = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
                        final closeMinutes = int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
                        final nowMinutes = now.hour * 60 + now.minute;
                        isWithinHours = nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
                      } catch (_) {}
                      final shopOpen = isOpen && isWithinHours;
                      return Container(
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: const Color(0xFF1A4DBE),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (bannerUrl != null)
                              Image.network(
                                bannerUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(),
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
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                          errorBuilder: (_, __, ___) => Container(
                                            color: Colors.white24,
                                            child: const Icon(Icons.storefront, color: Colors.white),
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
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.storefront, color: Colors.white),
                                    ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.white24,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              category.toString(),
                                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: shopOpen ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    shopOpen ? Icons.circle : Icons.circle,
                                                    size: 7,
                                                    color: Colors.white,
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    shopOpen ? 'Open' : 'Closed',
                                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${to12Hour(openTime)} \u2013 ${to12Hour(closeTime)}',
                                              style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                                            ),
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
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          // Always show static Marketplaza banner
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
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFFF5A524),
                    ),
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
    final imageUrl = (product['image_url'] as String?)?.trim() ?? '';
    final resolvedImage = imageUrl;

    final priceValue = product['price'];
    final unit = (product['unit_type'] ?? 'kg').toString();
    final priceText = priceValue != null ? "₱$priceValue /$unit" : "₱0";
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
                const SizedBox(height: 3),
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
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, index) {
        final p = essentials[index];
        final resolvedImage = (p['image_url'] as String?)?.trim() ?? '';

        return GestureDetector(
          onTap: () => _openProductDetail(p),
          child: Container(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 110,
                    child: _buildProductImage(resolvedImage),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
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
                        const SizedBox(height: 2),
                        Text(
                          p['price'] != null ? '₱${p['price']}' : 'Restock now',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A4DBE),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
        child: Icon(
          Icons.image_outlined,
          size: 36,
          color: Color(0xFFB6BDCC),
        ),
      ),
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
    final bool hasResults = filteredProducts.isNotEmpty;

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
              const SizedBox(height: 16),
              if (!hasResults && !isLoading)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      Icon(Icons.search_off_rounded, size: 56, color: Colors.grey[400]),
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
                            _selectedFilter = 'All';
                          });
                        },
                        child: const Text('Clear filters'),
                      ),
                    ],
                  ),
                ),
              if (hasResults) ...[
              _buildSectionHeader(
                'Flash Deals',
                'Limited picks from San Fernando market stalls',
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 110,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : flashProducts.isEmpty
                    ? const Center(child: Text("No products yet."))
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: flashProducts.length,
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () => _openProductDetail(flashProducts[index]),
                            child: _buildFlashDealCard(flashProducts[index]),
                          );
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
                height: 260,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : recommendedProducts.isEmpty
                    ? const Center(child: Text("No products yet."))
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: recommendedProducts.length,
                        itemBuilder: (context, i) {
                          final p = recommendedProducts[i];

                          final resolvedImage =
                              (p['image_url'] as String?)?.trim() ?? '';

                          final priceValue = p['price'];
                          final unit = (p['unit_type'] ?? 'kg').toString();
                          final priceText = priceValue != null
                              ? "₱$priceValue /$unit"
                              : "₱0";

                          return GestureDetector(
                            onTap: () => _openProductDetail(p),
                            child: ProductCard(
                              title: _productName(p, 'Fresh Item'),
                              storeName: _storeName(p, 'San Fernando Stall'),
                              price: priceText,
                              imageUrl: resolvedImage,
                              description: (p['description'] ?? '').toString(),
                              isShopOpen: _isShopOpen(p),
                              shopHoursLabel: p['is_db'] == true
                                  ? (_isShopOpen(p)
                                      ? 'Open · Closes ${p['closing_time'] ?? '19:00'}'
                                      : 'Closed · Opens ${p['opening_time'] ?? '05:00'}')
                                  : null,
                              onAddPressed: () {
                                _addToCart(p);
                              },
                            ),
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
          if (shopHoursLabel != null) ...[
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: isShopOpen
                    ? const Color(0xFF059669).withValues(alpha: 0.1)
                    : const Color(0xFFDC2626).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                shopHoursLabel!,
                style: TextStyle(
                  color: isShopOpen ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
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
