import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../utils/delivery_route_preview.dart';
import '../utils/market_geo.dart';
import 'pick_location_page.dart';

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

  static const Color _kPrimary = Color(0xFF2A4BA0);
  static const Color _kSurface = Color(0xFFF5F6FB);

  final _tabs = const ['All', 'Pending', 'Accepted', 'Ready', 'Completed', 'Declined', 'Cancelled'];

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

  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString();
    if (orderId == null) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Order?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please provide a reason (optional):',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. Changed my mind, ordered by mistake...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Order')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );
    if (confirmed != true) { reasonCtrl.dispose(); return; }
    try {
      await supabase.from('orders').update({
        'status': 'cancelled',
        'cancelled_by': 'buyer',
        'cancel_reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);
      if (mounted) {
        setState(() => _isLoading = true);
        _fetchOrders();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order cancelled.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    reasonCtrl.dispose();
  }

  Future<void> _repinOrder(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString();
    if (orderId == null) return;
    final existingLat = (order['delivery_lat'] as num?)?.toDouble();
    final existingLng = (order['delivery_lng'] as num?)?.toDouble();
    final initialPoint = (existingLat != null && existingLng != null)
        ? LatLng(existingLat, existingLng)
        : null;

    final picked = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => PickLocationPage(
          title: 'Pin this Order',
          initialPoint: initialPoint,
          initialAddress: order['delivery_address']?.toString(),
        ),
      ),
    );
    if (picked == null) return;

    try {
      await supabase.from('orders').update({
        'delivery_lat': picked['lat'],
        'delivery_lng': picked['lng'],
        'delivery_address': picked['address'],
      }).eq('id', orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location updated. The seller can now see your pin.'),
            backgroundColor: _kPrimary,
          ),
        );
        setState(() => _isLoading = true);
        _fetchOrders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update pin: $e')),
        );
      }
    }
  }

  Future<void> _backfillDeliveryCoords(
    List<Map<String, dynamic>> orders,
    String userId,
  ) async {
    final pending = orders.where((o) {
      final type = (o['order_type']?.toString() ?? 'pickup');
      final addr = o['delivery_address']?.toString().trim() ?? '';
      return type == 'delivery' &&
          addr.isNotEmpty &&
          (o['delivery_lat'] == null || o['delivery_lng'] == null);
    }).toList();
    if (pending.isEmpty) return;

    try {
      final addrs = await supabase
          .from('delivery_addresses')
          .select('address, lat, lng')
          .eq('user_id', userId)
          .not('lat', 'is', null)
          .not('lng', 'is', null);

      final pinned = <String, Map<String, double>>{};
      for (final a in (addrs as List)) {
        final text = a['address']?.toString().trim().toLowerCase();
        final lat = (a['lat'] as num?)?.toDouble();
        final lng = (a['lng'] as num?)?.toDouble();
        if (text == null || text.isEmpty || lat == null || lng == null) continue;
        pinned[text] = {'lat': lat, 'lng': lng};
      }
      if (pinned.isEmpty) return;

      for (final o in pending) {
        final key = o['delivery_address']?.toString().trim().toLowerCase();
        if (key == null) continue;
        final match = pinned[key];
        if (match == null) continue;
        try {
          await supabase.from('orders').update({
            'delivery_lat': match['lat'],
            'delivery_lng': match['lng'],
          }).eq('id', o['id']);
          o['delivery_lat'] = match['lat'];
          o['delivery_lng'] = match['lng'];
        } catch (e) {
          debugPrint('Backfill failed for order ${o['id']}: $e');
        }
      }
    } catch (e) {
      debugPrint('Backfill load failed: $e');
    }
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
      final orders = List<Map<String, dynamic>>.from(res);

      // Batch-fetch seller profiles to get addresses for orders that don't have them stored
      final sellerIds = orders
          .map((o) => o['seller_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final Map<String, Map<String, dynamic>> sellerInfo = {};
      if (sellerIds.isNotEmpty) {
        try {
          final profiles = await supabase
              .from('seller_profiles')
              .select('user_id, store_address, stall_lat, stall_lng')
              .inFilter('user_id', sellerIds);
          for (final p in profiles as List) {
            sellerInfo[p['user_id'].toString()] = {
              'store_address': p['store_address']?.toString(),
              'stall_lat': (p['stall_lat'] as num?)?.toDouble(),
              'stall_lng': (p['stall_lng'] as num?)?.toDouble(),
            };
          }
        } catch (_) {}
      }

      // Merge: prefer value stored on the order; fall back to live seller profile.
      // Legacy orders won't have store_lat/lng snapshots yet — fill those in too.
      for (final o in orders) {
        final sid = o['seller_id']?.toString();
        final info = sid != null ? sellerInfo[sid] : null;
        if ((o['store_address'] == null || o['store_address'].toString().isEmpty) &&
            info?['store_address'] != null) {
          o['store_address'] = info!['store_address'];
        }
        if (o['store_lat'] == null && info?['stall_lat'] != null) {
          o['store_lat'] = info!['stall_lat'];
        }
        if (o['store_lng'] == null && info?['stall_lng'] != null) {
          o['store_lng'] = info!['stall_lng'];
        }
      }

      // Backfill delivery_lat/lng on any delivery orders that were placed
      // before the buyer pinned an address. We match the saved
      // `delivery_addresses` row by address text and write the coords back to
      // the order row so the seller's map view picks it up too.
      await _backfillDeliveryCoords(orders, user.id);

      if (!mounted) return;
      setState(() {
        _orders = orders;
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
    if (tab == 'Cancelled') return _orders.where((o) => o['status'] == 'cancelled').toList();
    return _orders.where((o) => o['status'] == tab.toLowerCase()).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return const Color(0xFFF59E0B);
      case 'preparing': case 'accepted': return _kPrimary;
      case 'ready': return const Color(0xFF059669);
      case 'completed': return const Color(0xFF8B5CF6);
      case 'declined': return const Color(0xFFDC2626);
      case 'cancelled': return const Color(0xFF9CA3AF);
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
      case 'cancelled': return Icons.block_rounded;
      default: return Icons.receipt_long_rounded;
    }
  }

  String _statusLabel(String status, {bool isDelivery = false}) {
    switch (status) {
      case 'pending': return 'Waiting for seller';
      case 'preparing': case 'accepted':
        return isDelivery ? 'Seller is preparing your order' : 'Seller is preparing';
      case 'ready':
        return isDelivery ? 'Out for delivery' : 'Ready for pickup';
      case 'completed': return 'Completed';
      case 'declined': return 'Declined by seller';
      case 'cancelled': return 'Cancelled by you';
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
                    color: Color(0xFF2A4BA0),
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
                    const Icon(Icons.key_rounded, size: 16, color: Color(0xFF2A4BA0)),
                    const SizedBox(width: 8),
                    Text(pickupCode,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: Color(0xFF2A4BA0),
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
    final storeAddress = order['store_address']?.toString() ?? '';
    final addressLine = storeAddress;
    final orderType = order['order_type']?.toString() ?? 'pickup';
    final deliveryAddress = order['delivery_address']?.toString() ?? '';
    final isDelivery = orderType == 'delivery';
    final pickupTime = order['pickup_time']?.toString() ?? '';
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
    final storeLat = (order['store_lat'] as num?)?.toDouble();
    final storeLng = (order['store_lng'] as num?)?.toDouble();
    final deliveryLat = (order['delivery_lat'] as num?)?.toDouble();
    final deliveryLng = (order['delivery_lng'] as num?)?.toDouble();
    final textScale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);
    final actionHeight = 40 + ((textScale - 1) * 16);
    final compactHeight = 36 + ((textScale - 1) * 12);

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
                            errorBuilder: (_, _, _) => Container(
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
                      if (addressLine.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF9CA3AF)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(addressLine,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDelivery
                                  ? const Color(0xFF0891B2).withValues(alpha: 0.1)
                                  : const Color(0xFF059669).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isDelivery ? Icons.delivery_dining_rounded : Icons.storefront_rounded,
                                  size: 11,
                                  color: isDelivery ? const Color(0xFF0891B2) : const Color(0xFF059669),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  isDelivery ? 'Delivery' : 'Pickup',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isDelivery ? const Color(0xFF0891B2) : const Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (isDelivery && deliveryAddress.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFF0891B2)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                deliveryAddress,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (!isDelivery && pickupTime.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFF059669)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Pickup: $pickupTime',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
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
          // ── Missing-pin CTA: delivery order has no buyer pin yet ──
          if (status != 'cancelled' &&
              status != 'declined' &&
              status != 'completed' &&
              isDelivery &&
              (deliveryLat == null || deliveryLng == null)) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: Color(0xFFB45309)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'This order has no map pin yet',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The rider can\'t find your exact spot without a pin. Tap below to add one.',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF92400E), height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: compactHeight,
                      child: ElevatedButton.icon(
                        onPressed: () => _repinOrder(order),
                        icon: const Icon(Icons.add_location_alt_rounded, size: 16),
                        label: const Text(
                          'Pin this order on the map',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          backgroundColor: const Color(0xFFB45309),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ── Map: where to pick up (pickup) / delivery destination ──
          if (status != 'cancelled' &&
              status != 'declined' &&
              ((isDelivery && deliveryLat != null && deliveryLng != null) ||
                  (!isDelivery && storeLat != null && storeLng != null))) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isDelivery
                            ? Icons.delivery_dining_rounded
                            : Icons.map_outlined,
                        size: 14,
                        color: _kPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isDelivery
                            ? 'Delivering to your pin'
                            : 'Where to pick up',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _kPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DeliveryRoutePreview(
                    height: 140,
                    shops: storeLat != null && storeLng != null
                        ? [
                            StallPoint(
                              name: storeName,
                              point: LatLng(storeLat, storeLng),
                            ),
                          ]
                        : const [],
                    buyer: isDelivery && deliveryLat != null && deliveryLng != null
                        ? LatLng(deliveryLat, deliveryLng)
                        : null,
                  ),
                  if (!isDelivery && storeLat != null && storeLng != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: actionHeight,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final ok = await launchExternalNavigation(
                            LatLng(storeLat, storeLng),
                            label: storeName,
                          );
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not open a maps app.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.navigation_rounded, size: 16),
                        label: const Text(
                          'Navigate to Stall',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // QR Code button for ready pickup orders only
          if (status == 'ready' && !isDelivery) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: SizedBox(
                width: double.infinity,
                height: actionHeight,
                child: ElevatedButton.icon(
                  onPressed: () => _showPickupQR(order),
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  label: const Text('Show Pickup QR Code',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
          // Cancel button for pending orders
          if (status == 'pending') ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: SizedBox(
                width: double.infinity,
                height: actionHeight,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelOrder(order),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel Order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
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
                Text(_statusLabel(status, isDelivery: isDelivery),
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
