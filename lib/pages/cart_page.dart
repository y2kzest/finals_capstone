import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'orders_page.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final supabase = Supabase.instance.client;
  late Future<List<dynamic>> _cartFuture;
  StreamSubscription<AuthState>? _authSubscription;

  static const Color _kPrimaryBlue = Color(0xFF1A4DBE);

  @override
  void initState() {
    super.initState();
    _cartFuture = loadCartItems();
    _authSubscription = supabase.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      _refreshCart();
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<List<dynamic>> loadCartItems() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await supabase
          .from('cart')
          .select()
          .eq('buyer_id', user.id)
          .order('id', ascending: false);

      return response;
    } catch (e) {
      // Surface a lightweight error to the UI while keeping the page usable
      debugPrint('Cart load error: $e');
      return [];
    }
  }

  Future<void> _refreshCart() async {
    setState(() {
      _cartFuture = loadCartItems();
    });
    await _cartFuture;
  }

  Future<void> _deleteCartItem(Map<String, dynamic> item) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final rowId = item['id']?.toString();

    try {
      if (rowId == null || rowId.isEmpty) {
        throw Exception('Missing cart row id.');
      }

      final deleted = await supabase
          .from('cart')
          .delete()
          .eq('id', rowId)
          .eq('buyer_id', user.id)
          .select('id');

      if (deleted.isEmpty) {
        throw Exception('No cart row was removed.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Item removed from cart')));
      await _refreshCart();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to remove item. Please check cart permissions/policies. ($e)',
          ),
        ),
      );
    }
  }

  Future<void> _updateQuantity(Map<String, dynamic> item, int nextQty) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final rowId = item['id']?.toString();

    if (nextQty <= 0) {
      await _deleteCartItem(item);
      return;
    }

    try {
      if (rowId == null || rowId.isEmpty) {
        throw Exception('Missing cart row id.');
      }

      final updated = await supabase
          .from('cart')
          .update({'qty': nextQty})
          .eq('id', rowId)
          .eq('buyer_id', user.id)
          .select('id, qty');

      if (updated.isEmpty) {
        throw Exception('No cart row was updated.');
      }

      await _refreshCart();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to update quantity. Please check cart permissions/policies. ($e)',
          ),
        ),
      );
    }
  }

  double _itemPrice(dynamic rawPrice) {
    if (rawPrice is num) return rawPrice.toDouble();
    return double.tryParse(rawPrice?.toString() ?? '') ?? 0;
  }

  int _itemQty(dynamic rawQty) {
    if (rawQty is int) return rawQty;
    return int.tryParse(rawQty?.toString() ?? '') ?? 1;
  }

  String _itemName(Map<String, dynamic> item) {
    final name = item['product_name']?.toString().trim();
    if (name == null || name.isEmpty) return 'Market Item';
    return name;
  }

  String _itemStore(Map<String, dynamic> item) {
    final store = item['store_name']?.toString().trim();
    if (store == null || store.isEmpty) return 'San Fernando Stall';
    return store;
  }

  String _itemImage(Map<String, dynamic> item) {
    final image = item['image_url']?.toString().trim();
    if (image == null || image.isEmpty) return 'assets/img/kasim.jpg';
    return image;
  }

  bool _isAssetPath(String path) {
    return path.startsWith('assets/') || path.startsWith('images/');
  }

  Widget _buildProductImage(String imagePath) {
    if (_isAssetPath(imagePath)) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const ColoredBox(
          color: Color(0xFFEDEFF5),
          child: Icon(Icons.image_not_supported_outlined),
        ),
      );
    }

    return Image.network(
      imagePath,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          Image.asset('assets/img/kasim.jpg', fit: BoxFit.cover),
    );
  }

  Widget _buildQuantityControl(Map<String, dynamic> item) {
    final qty = _itemQty(item['qty']);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4FC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => _updateQuantity(item, qty - 1),
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.remove, size: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$qty',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          InkWell(
            onTap: () => _updateQuantity(item, qty + 1),
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.add, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(Map<String, dynamic> item) {
    final price = _itemPrice(item['price']);
    final qty = _itemQty(item['qty']);
    final subtotal = price * qty;

    return Dismissible(
      key: ValueKey(item['id'] ?? '${_itemName(item)}-$qty'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _deleteCartItem(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.14),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: _buildProductImage(_itemImage(item)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _itemName(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _itemStore(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '₱${subtotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: _kPrimaryBlue,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      _buildQuantityControl(item),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupByShop(
    List<Map<String, dynamic>> items,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final shop = _itemStore(item);
      grouped.putIfAbsent(shop, () => <Map<String, dynamic>>[]).add(item);
    }
    return grouped;
  }

  double _shopSubtotal(List<Map<String, dynamic>> items) {
    double total = 0;
    for (final item in items) {
      total += _itemPrice(item['price']) * _itemQty(item['qty']);
    }
    return total;
  }

  int _shopItemCount(List<Map<String, dynamic>> items) {
    int total = 0;
    for (final item in items) {
      total += _itemQty(item['qty']);
    }
    return total;
  }

  int _totalSelectedItems(List<dynamic> items) {
    int total = 0;
    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw as Map);
      total += _itemQty(item['qty']);
    }
    return total;
  }

  Widget _buildShopSection(String shopName, List<Map<String, dynamic>> items) {
    final shopSubtotal = _shopSubtotal(items);
    final shopItemCount = _shopItemCount(items);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F4FA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: _kPrimaryBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$shopName  >',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'Edit',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$shopItemCount item(s)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'Shop total: ₱${shopSubtotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          for (final item in items) _buildCartItem(item),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE9EDF7)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.local_offer_outlined,
                  size: 16,
                  color: Colors.orange,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Shop voucher available',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: Colors.black38),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE9EDF7)),
            ),
            child: const Row(
              children: [
                Icon(Icons.local_mall_outlined, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Add more from this shop for bundle deals',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: Colors.black38),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 100),
        Center(
          child: Icon(
            Icons.shopping_cart_outlined,
            size: 68,
            color: Color(0xFF9EA9C6),
          ),
        ),
        SizedBox(height: 12),
        Center(
          child: Text(
            'Your cart is empty',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(height: 6),
        Center(
          child: Text(
            'Add fresh products from San Fernando Market Plaza.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(List<dynamic> items) {
    double subtotal = 0;
    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw as Map);
      subtotal += _itemPrice(item['price']) * _itemQty(item['qty']);
    }

    final selectedCount = _totalSelectedItems(items);
    final deliveryFee = items.isEmpty ? 0 : 35;
    final total = subtotal + deliveryFee;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'Subtotal',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const Spacer(),
              Text(
                '₱${subtotal.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                'Delivery',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const Spacer(),
              Text(
                '₱${deliveryFee.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '₱${total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _kPrimaryBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: items.isEmpty
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const OrdersPage()),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Check Out ($selectedCount)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FB),
      appBar: AppBar(
        title: const Text(
          'My Cart',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _cartFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final rawItems = snapshot.data ?? [];
          final items = rawItems
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final groupedItems = _groupByShop(items);

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshCart,
                  color: _kPrimaryBlue,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: items.isEmpty
                        ? _buildEmptyCart()
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: groupedItems.entries
                                .map(
                                  (entry) =>
                                      _buildShopSection(entry.key, entry.value),
                                )
                                .toList(),
                          ),
                  ),
                ),
              ),
              _buildSummaryCard(items),
            ],
          );
        },
      ),
    );
  }
}
