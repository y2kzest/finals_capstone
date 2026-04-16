import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;

  static const Color _kPrimary = Color(0xFF1A4DBE);
  static const Color _kSurface = Color(0xFFF5F6FB);

  final _tabs = const ['All', 'Pending', 'Accepted', 'Ready', 'Completed', 'Declined'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _fetchOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await supabase
          .from('orders')
          .select()
          .eq('buyer_id', user.id)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _orders = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Orders fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _filtered(String tab) {
    if (tab == 'All') return _orders;
    if (tab == 'Accepted') {
      return _orders.where((o) => o['status'] == 'preparing' || o['status'] == 'accepted').toList();
    }
    return _orders.where((o) => o['status'] == tab.toLowerCase()).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return const Color(0xFFF59E0B);
      case 'preparing': case 'accepted': return _kPrimary;
      case 'ready': return const Color(0xFF059669);
      case 'completed': return const Color(0xFF8B5CF6);
      case 'declined': return const Color(0xFFDC2626);
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending': return Icons.schedule_rounded;
      case 'preparing': case 'accepted': return Icons.restaurant_rounded;
      case 'ready': return Icons.check_circle_outline_rounded;
      case 'completed': return Icons.done_all_rounded;
      case 'declined': return Icons.cancel_rounded;
      default: return Icons.receipt_long_rounded;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending': return 'Waiting for seller';
      case 'preparing': case 'accepted': return 'Seller is preparing';
      case 'ready': return 'Ready for pickup';
      case 'completed': return 'Completed';
      case 'declined': return 'Declined by seller';
      default: return status;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  void _showPickupQR(Map<String, dynamic> order) {
    final pickupCode = order['pickup_code']?.toString() ?? '';
    final productName = order['product_name']?.toString() ?? 'Order';
    final orderId = order['id']?.toString() ?? '';
    final shortId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;

    if (pickupCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pickup code found for this order.')),
      );
      return;
    }

    // QR data: "quickcart:ORDER_ID:PICKUP_CODE"
    final qrData = 'quickcart:$orderId:$pickupCode';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF059669), size: 28),
              ),
              const SizedBox(height: 14),
              const Text('Pickup QR Code',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
              ),
              const SizedBox(height: 4),
              Text(productName,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEEEFF3)),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 180,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1A4DBE),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.key_rounded, size: 16, color: Color(0xFF1A4DBE)),
                    const SizedBox(width: 8),
                    Text(pickupCode,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: Color(0xFF1A4DBE),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text('Order #$shortId',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(height: 16),
              const Text(
                'Show this QR code to the seller\nwhen picking up your order.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.4),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              color: Colors.white,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text('My Orders',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF6B7280)),
                    onPressed: () { setState(() => _isLoading = true); _fetchOrders(); },
                  ),
                ],
              ),
            ),
            // Tabs
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: _kPrimary,
                unselectedLabelColor: const Color(0xFF9CA3AF),
                indicatorColor: _kPrimary,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                tabAlignment: TabAlignment.start,
                dividerColor: const Color(0xFFEEEFF3),
                tabs: _tabs.map((t) => Tab(text: t)).toList(),
              ),
            ),
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2.5))
                  : TabBarView(
                      controller: _tabController,
                      children: _tabs.map((tab) {
                        final orders = _filtered(tab);
                        if (orders.isEmpty) return _buildEmpty(tab);
                        return RefreshIndicator(
                          onRefresh: _fetchOrders,
                          color: _kPrimary,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                            itemCount: orders.length,
                            itemBuilder: (ctx, i) => _buildOrderCard(orders[i]),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = (order['status'] ?? 'pending').toString();
    final color = _statusColor(status);
    final productName = order['product_name']?.toString() ?? 'Order';
    final storeName = order['store_name']?.toString() ?? 'Market Stall';
    final price = order['price'] ?? 0;
    final qty = order['qty'] ?? 1;
    final priceNum = price is num ? price.toDouble() : (double.tryParse(price.toString()) ?? 0);
    final qtyNum = qty is num ? qty.toInt() : (int.tryParse(qty.toString()) ?? 1);
    final total = priceNum * qtyNum;
    final unit = (order['unit_type'] ?? 'kg').toString();
    final orderId = order['id']?.toString() ?? '';
    final shortId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
    final imgUrl = order['image_url']?.toString().trim() ?? '';
    final declinedReason = order['declined_reason']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product image
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 52, height: 52,
                    child: imgUrl.isEmpty
                        ? Container(
                            color: color.withValues(alpha: 0.1),
                            child: Icon(_statusIcon(status), color: color, size: 24),
                          )
                        : Image.network(imgUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: color.withValues(alpha: 0.1),
                              child: Icon(_statusIcon(status), color: color, size: 24),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(productName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.storefront_rounded, size: 12, color: Color(0xFF9CA3AF)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(storeName,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('P${total.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Row(
              children: [
                Icon(Icons.tag_rounded, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text('#$shortId', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(width: 12),
                Icon(Icons.shopping_bag_outlined, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text('$qtyNum x P${priceNum.toStringAsFixed(0)} /$unit',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                const Spacer(),
                Icon(Icons.access_time_rounded, size: 12, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(_formatDate(order['created_at']?.toString()),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          // QR Code button for ready orders
          if (status == 'ready') ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _showPickupQR(order),
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  label: const Text('Show Pickup QR Code',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(_statusIcon(status), size: 16, color: color),
                const SizedBox(width: 8),
                Text(_statusLabel(status),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                ),
                if (status == 'declined' && declinedReason != null && declinedReason.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('- $declinedReason',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(String tab) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.receipt_long_rounded, size: 36, color: Colors.grey[350]),
          ),
          const SizedBox(height: 16),
          Text(tab == 'All' ? 'No orders yet' : 'No ${tab.toLowerCase()} orders',
            style: TextStyle(color: Colors.grey[500], fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text('Pull down to refresh', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }
}
