import 'dart:async';
import 'dart:math';
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
  List<Map<String, dynamic>> _cartItems = [];
  bool _isLoading = true;
  bool _isCheckingOut = false;
  StreamSubscription<AuthState>? _authSub;

  static const Color _kPrimary = Color(0xFF1A4DBE);
  static const Color _kSurface = Color(0xFFF5F6FB);
  static const Color _kRed = Color(0xFFDC2626);

  static String _generatePickupCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    _loadCart();
    _authSub = supabase.auth.onAuthStateChange.listen((_) {
      if (mounted) _loadCart();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCart() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() { _cartItems = []; _isLoading = false; });
      return;
    }
    try {
      final res = await supabase
          .from('cart')
          .select()
          .eq('buyer_id', user.id)
          .order('id', ascending: false);
      if (!mounted) return;
      setState(() {
        _cartItems = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Cart load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateQty(Map<String, dynamic> item, int newQty) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final id = item['id']?.toString();
    if (id == null) return;
    if (newQty <= 0) { await _removeItem(item); return; }
    try {
      await supabase.from('cart').update({'qty': newQty}).eq('id', id).eq('buyer_id', user.id);
      await _loadCart();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _removeItem(Map<String, dynamic> item) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final id = item['id']?.toString();
    if (id == null) return;
    try {
      await supabase.from('cart').delete().eq('id', id).eq('buyer_id', user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Removed from cart'), duration: Duration(seconds: 1)),
      );
      await _loadCart();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _clearCart() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase.from('cart').delete().eq('buyer_id', user.id);
      await _loadCart();
    } catch (_) {}
  }

  Future<void> _checkout() async {
    final user = supabase.auth.currentUser;
    if (user == null || _cartItems.isEmpty) return;
    setState(() => _isCheckingOut = true);
    try {
      for (final item in _cartItems) {
        final price = _price(item['price']);
        final qty = _qty(item['qty']);
        final sellerId = item['seller_id']?.toString();
        final pickupCode = _generatePickupCode();

        final orderRes = await supabase.from('orders').insert({
          'buyer_id': user.id,
          'seller_id': sellerId,
          'product_id': item['product_id']?.toString(),
          'product_name': item['product_name'] ?? 'Item',
          'store_name': item['store_name'] ?? 'Market Stall',
          'image_url': item['image_url'],
          'price': price,
          'qty': qty,
          'unit_type': item['unit_type'] ?? 'kg',
          'total_amount': price * qty,
          'status': 'pending',
          'pickup_code': pickupCode,
        }).select('id').single();

        if (sellerId != null && sellerId.isNotEmpty) {
          await supabase.from('seller_notifications').insert({
            'seller_id': sellerId,
            'order_id': orderRes['id'],
            'title': 'New Order!',
            'body': '${item['product_name'] ?? 'Item'} x$qty - P${(price * qty).toStringAsFixed(0)}',
            'type': 'new_order',
          });
        }

        // Buyer notification
        await supabase.from('notifications').insert({
          'user_id': user.id,
          'type': 'order_placed',
          'title': 'Order Placed',
          'message': '${item['product_name'] ?? 'Item'} x$qty — P${(price * qty).toStringAsFixed(0)} order sent to ${item['store_name'] ?? 'seller'}',
          'is_read': false,
        });
      }
      await _clearCart();
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _CheckoutSuccessDialog(
          onViewOrders: () {
            Navigator.of(ctx).pop();
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersPage()));
          },
          onContinue: () => Navigator.of(ctx).pop(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout failed: $e'), backgroundColor: _kRed),
      );
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  double _price(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _qty(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 1;
  }

  String _name(Map<String, dynamic> item) {
    final n = item['product_name']?.toString().trim() ?? '';
    return n.isEmpty ? 'Market Item' : n;
  }

  String _store(Map<String, dynamic> item) {
    final s = item['store_name']?.toString().trim() ?? '';
    return s.isEmpty ? 'Market Stall' : s;
  }

  String _image(Map<String, dynamic> item) => item['image_url']?.toString().trim() ?? '';

  Map<String, List<Map<String, dynamic>>> _groupByShop(List<Map<String, dynamic>> items) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      grouped.putIfAbsent(_store(item), () => []).add(item);
    }
    return grouped;
  }

  double get _subtotal {
    double t = 0;
    for (final i in _cartItems) t += _price(i['price']) * _qty(i['qty']);
    return t;
  }

  int get _totalItems {
    int t = 0;
    for (final i in _cartItems) t += _qty(i['qty']);
    return t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2.5))
                  : _cartItems.isEmpty
                      ? _buildEmptyCart()
                      : RefreshIndicator(
                          onRefresh: _loadCart,
                          color: _kPrimary,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            children: [
                              _buildOrderSummaryHeader(),
                              const SizedBox(height: 14),
                              ..._groupByShop(_cartItems).entries.map(
                                (e) => _buildShopGroup(e.key, e.value),
                              ),
                              const SizedBox(height: 12),
                              _buildPriceBreakdown(),
                            ],
                          ),
                        ),
            ),
            if (_cartItems.isNotEmpty) _buildCheckoutBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEFF3), width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text('My Cart',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
            ),
          ),
          if (_cartItems.isNotEmpty)
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Clear Cart?'),
                    content: const Text('Remove all items from your cart?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear', style: TextStyle(color: Color(0xFFDC2626))),
                      ),
                    ],
                  ),
                );
                if (confirm == true) await _clearCart();
              },
              child: const Text('Clear All', style: TextStyle(color: Color(0xFFDC2626), fontSize: 13, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1A4DBE), Color(0xFF2A4BA0)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shopping_cart_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_totalItems item${_totalItems == 1 ? '' : 's'} in cart',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('From ${_groupByShop(_cartItems).length} shop${_groupByShop(_cartItems).length == 1 ? '' : 's'}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
          ),
          Text('P${_subtotal.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildShopGroup(String shopName, List<Map<String, dynamic>> items) {
    double shopTotal = 0;
    for (final i in items) shopTotal += _price(i['price']) * _qty(i['qty']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: _kPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: _kPrimary, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(shopName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('P${shopTotal.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kPrimary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14),
          ...items.map((item) => _buildCartItemTile(item)),
        ],
      ),
    );
  }

  Widget _buildCartItemTile(Map<String, dynamic> item) {
    final price = _price(item['price']);
    final qty = _qty(item['qty']);
    final unit = (item['unit_type'] ?? 'kg').toString();
    final imgUrl = _image(item);

    return Dismissible(
      key: ValueKey(item['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: _kRed.withValues(alpha: 0.1),
        child: const Icon(Icons.delete_rounded, color: _kRed),
      ),
      onDismissed: (_) => _removeItem(item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 60, height: 60,
                child: imgUrl.isEmpty
                    ? Container(
                        color: const Color(0xFFF1F3F9),
                        child: const Icon(Icons.image_outlined, color: Color(0xFFB6BDCC), size: 24),
                      )
                    : Image.network(imgUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFFF1F3F9),
                          child: const Icon(Icons.image_outlined, color: Color(0xFFB6BDCC), size: 24),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_name(item),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text('P${price.toStringAsFixed(0)} /$unit',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kPrimary),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4FC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _qtyButton(Icons.remove, () => _updateQty(item, qty - 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('$qty', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  _qtyButton(Icons.add, () => _updateQty(item, qty + 1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: _kPrimary),
        ),
      ),
    );
  }

  Widget _buildPriceBreakdown() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order Summary',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
          ),
          const SizedBox(height: 12),
          _summaryRow('Subtotal', 'P${_subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 6),
          _summaryRow('Items', '$_totalItems'),
          const SizedBox(height: 6),
          _summaryRow('Shops', '${_groupByShop(_cartItems).length}'),
          const Divider(height: 20),
          Row(
            children: [
              const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('P${_subtotal.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _kPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
      ],
    );
  }

  Widget _buildCheckoutBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Color(0x18000000), blurRadius: 12, offset: Offset(0, -3))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  const SizedBox(height: 2),
                  Text('P${_subtotal.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _kPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isCheckingOut ? null : _checkout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isCheckingOut
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Place Order ($_totalItems)',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4FC),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.shopping_cart_outlined, size: 40, color: Color(0xFFB6BDCC)),
          ),
          const SizedBox(height: 16),
          const Text('Your cart is empty',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
          ),
          const SizedBox(height: 6),
          const Text('Add fresh products from San Fernando Market.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.shopping_bag_outlined, size: 18),
            label: const Text('Browse Products'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kPrimary,
              side: const BorderSide(color: _kPrimary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutSuccessDialog extends StatelessWidget {
  final VoidCallback onViewOrders;
  final VoidCallback onContinue;
  const _CheckoutSuccessDialog({required this.onViewOrders, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 40),
            ),
            const SizedBox(height: 16),
            const Text('Order Placed!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your order has been sent to the seller.\nYou will be notified once it is accepted.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onViewOrders,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A4DBE),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('View My Orders', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onContinue,
              child: const Text('Continue Shopping',
                style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
