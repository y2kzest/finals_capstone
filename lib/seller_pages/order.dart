import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

const Color _kPrimary = Color(0xFF1A4DBE);
const Color _kSurface = Color(0xFFF5F6FB);
const Color _kGreen = Color(0xFF059669);
const Color _kRed = Color(0xFFDC2626);
const Color _kAmber = Color(0xFFF59E0B);
const Color _kPurple = Color(0xFF8B5CF6);

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final supabase = Supabase.instance.client;
  RealtimeChannel? _orderChannel;
  RealtimeChannel? _notifChannel;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fetchUnreadCount();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _orderChannel = supabase
        .channel('seller-orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'seller_id', value: userId),
          callback: (_) { if (mounted) setState(() {}); },
        )
        .subscribe();

    _notifChannel = supabase
        .channel('seller-notifs')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'seller_notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'seller_id', value: userId),
          callback: (_) {
            if (mounted) {
              setState(() => _unreadCount++);
              _tabController.animateTo(0);
            }
          },
        )
        .subscribe();
  }

  Future<void> _fetchUnreadCount() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final res = await supabase
          .from('seller_notifications')
          .select('id')
          .eq('seller_id', userId)
          .eq('is_read', false);
      if (mounted) setState(() => _unreadCount = (res as List).length);
    } catch (_) {}
  }

  Future<void> _markNotificationsRead() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await supabase
          .from('seller_notifications')
          .update({'is_read': true})
          .eq('seller_id', userId)
          .eq('is_read', false);
      if (mounted) setState(() => _unreadCount = 0);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_orderChannel != null) supabase.removeChannel(_orderChannel!);
    if (_notifChannel != null) supabase.removeChannel(_notifChannel!);
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchOrders(String status) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final res = await supabase
          .from('orders')
          .select()
          .eq('seller_id', userId)
          .eq('status', status)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Fetch orders error: $e');
      return [];
    }
  }

  Future<void> _updateStatus(String orderId, String newStatus, [Map<String, dynamic>? order]) async {
    try {
      await supabase.from('orders').update({
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);

      // Notify buyer of status change
      if (order != null) {
        final buyerId = order['buyer_id']?.toString();
        final productName = order['product_name']?.toString() ?? 'Your order';
        if (buyerId != null && buyerId.isNotEmpty) {
          String title;
          String message;
          String type;
          switch (newStatus) {
            case 'preparing':
              title = 'Order Accepted!';
              message = '$productName is now being prepared by the seller.';
              type = 'order_accepted';
              break;
            case 'ready':
              title = 'Order Ready!';
              message = '$productName is ready for pickup.';
              type = 'order_ready';
              break;
            case 'completed':
              title = 'Order Completed';
              message = '$productName has been marked as completed.';
              type = 'order_completed';
              break;
            default:
              title = 'Order Updated';
              message = '$productName status changed to $newStatus.';
              type = 'order_update';
          }
          await supabase.from('notifications').insert({
            'user_id': buyerId,
            'type': type,
            'title': title,
            'message': message,
            'is_read': false,
          });
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _declineOrder(String orderId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Decline Order?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Provide a reason (optional):',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. Out of stock',
                hintStyle: const TextStyle(color: Color(0xFFB6BDCC)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      // Fetch order details for buyer notification
      final orderData = await supabase
          .from('orders')
          .select('buyer_id, product_name')
          .eq('id', orderId)
          .maybeSingle();

      await supabase.from('orders').update({
        'status': 'declined',
        'declined_reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', orderId);

      // Notify buyer
      if (orderData != null) {
        final buyerId = orderData['buyer_id']?.toString();
        final productName = orderData['product_name']?.toString() ?? 'Your order';
        if (buyerId != null && buyerId.isNotEmpty) {
          final reason = reasonCtrl.text.trim();
          await supabase.from('notifications').insert({
            'user_id': buyerId,
            'type': 'order_declined',
            'title': 'Order Declined',
            'message': '$productName was declined${reason.isNotEmpty ? ': $reason' : '.'}',
            'is_read': false,
          });
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    reasonCtrl.dispose();
  }

  Future<void> _showVerifyPickupDialog(String orderId, Map<String, dynamic> order) async {
    final codeCtrl = TextEditingController();
    final expectedCode = order['pickup_code']?.toString() ?? '';

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.qr_code_scanner_rounded, color: _kPurple, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Verify Pickup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Scan the buyer\'s QR code or enter the 6-digit pickup code.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final scanned = await _openQRScanner();
                  if (scanned != null && scanned.isNotEmpty) {
                    Navigator.pop(ctx, scanned);
                  }
                },
                icon: const Icon(Icons.camera_alt_rounded, size: 18),
                label: const Text('Scan QR Code', style: TextStyle(fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kPrimary,
                  side: const BorderSide(color: _kPrimary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey[300])),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w600)),
                ),
                Expanded(child: Divider(color: Colors.grey[300])),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 6),
              decoration: InputDecoration(
                hintText: 'ABC123',
                hintStyle: TextStyle(color: Colors.grey[300], letterSpacing: 6),
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx, 'manual:${codeCtrl.text.trim().toUpperCase()}');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    codeCtrl.dispose();
    if (result == null || result.isEmpty) return;

    // Parse the result
    String enteredCode;
    if (result.startsWith('quickcart:')) {
      // QR scanned: "quickcart:ORDER_ID:CODE"
      final parts = result.split(':');
      if (parts.length >= 3) {
        final scannedOrderId = parts[1];
        enteredCode = parts[2];
        if (scannedOrderId != orderId) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This QR code is for a different order.'),
                backgroundColor: _kRed,
              ),
            );
          }
          return;
        }
      } else {
        enteredCode = result;
      }
    } else if (result.startsWith('manual:')) {
      enteredCode = result.substring(7);
    } else {
      enteredCode = result;
    }

    if (expectedCode.isEmpty) {
      // No pickup code stored, allow completion anyway
      await _updateStatus(orderId, 'completed', order);
      return;
    }

    if (enteredCode.toUpperCase() == expectedCode.toUpperCase()) {
      await _updateStatus(orderId, 'completed', order);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Pickup verified! Order completed.'),
              ],
            ),
            backgroundColor: _kGreen,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Invalid pickup code. Please try again.'),
              ],
            ),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }

  Future<String?> _openQRScanner() async {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const _QRScannerPage(),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return _kAmber;
      case 'preparing': return _kPrimary;
      case 'ready': return _kGreen;
      case 'completed': return _kPurple;
      case 'declined': return _kRed;
      default: return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending': return Icons.schedule_rounded;
      case 'preparing': return Icons.restaurant_rounded;
      case 'ready': return Icons.check_circle_outline_rounded;
      case 'completed': return Icons.done_all_rounded;
      case 'declined': return Icons.cancel_rounded;
      default: return Icons.receipt_long_rounded;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return dateStr; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Orders',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                    ),
                  ),
                  if (_unreadCount > 0)
                    GestureDetector(
                      onTap: _markNotificationsRead,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _kRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.notifications_active_rounded, size: 14, color: _kRed),
                            const SizedBox(width: 4),
                            Text('$_unreadCount new',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kRed),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF6B7280),
                indicator: BoxDecoration(color: _kPrimary, borderRadius: BorderRadius.circular(12)),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                padding: const EdgeInsets.all(4),
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'New'),
                  Tab(text: 'Preparing'),
                  Tab(text: 'Ready'),
                  Tab(text: 'Completed'),
                  Tab(text: 'Declined'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTab('pending'),
                  _buildTab('preparing'),
                  _buildTab('ready'),
                  _buildTab('completed'),
                  _buildTab('declined'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String status) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchOrders(status),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2.5));
        }
        final orders = snapshot.data!;
        if (orders.isEmpty) return _buildEmpty(status);

        return RefreshIndicator(
          color: _kPrimary,
          onRefresh: () async { setState(() {}); },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            itemCount: orders.length,
            itemBuilder: (ctx, i) => _buildOrderCard(orders[i], status),
          ),
        );
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> o, String status) {
    final color = _statusColor(status);
    final productName = o['product_name']?.toString() ?? 'Order Item';
    // store_name available in o['store_name'] if needed
    final price = o['price'] ?? 0;
    final qty = o['qty'] ?? 1;
    final priceNum = price is num ? price.toDouble() : (double.tryParse(price.toString()) ?? 0);
    final qtyNum = qty is num ? qty.toInt() : (int.tryParse(qty.toString()) ?? 1);
    final total = priceNum * qtyNum;
    final unit = (o['unit_type'] ?? 'kg').toString();
    final orderId = o['id']?.toString() ?? '';
    final shortId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
    final imgUrl = o['image_url']?.toString().trim() ?? '';
    final declinedReason = o['declined_reason']?.toString();

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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 50, height: 50,
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
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _chip(Icons.shopping_bag_outlined, '$qtyNum x P${priceNum.toStringAsFixed(0)} /$unit'),
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
                    Text('#$shortId',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(78, 4, 16, 6),
            child: Row(
              children: [
                Icon(Icons.access_time_rounded, size: 13, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text(_formatDate(o['created_at']?.toString()),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          if (status == 'declined' && declinedReason != null && declinedReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kRed.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 14, color: _kRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(declinedReason,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Action buttons
          if (status == 'pending') ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: OutlinedButton(
                        onPressed: () => _declineOrder(orderId),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kRed,
                          side: const BorderSide(color: _kRed),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () => _updateStatus(orderId, 'preparing', o),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Accept Order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (status == 'preparing') ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SizedBox(
                width: double.infinity, height: 40,
                child: ElevatedButton(
                  onPressed: () => _updateStatus(orderId, 'ready', o),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Mark Ready for Pickup', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ),
          ] else if (status == 'ready') ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: () => _showVerifyPickupDialog(orderId, o),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                        label: const Text('Verify Pickup', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPurple,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildEmpty(String status) {
    final messages = {
      'pending': 'No new orders',
      'preparing': 'No orders being prepared',
      'ready': 'No orders ready for pickup',
      'completed': 'No completed orders yet',
      'declined': 'No declined orders',
    };
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
            child: Icon(_statusIcon(status), size: 36, color: Colors.grey[350]),
          ),
          const SizedBox(height: 16),
          Text(messages[status] ?? 'No orders',
            style: TextStyle(color: Colors.grey[500], fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text('Pull down to refresh', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }
}

// ── QR Scanner Page ─────────────────────────────────────────
class _QRScannerPage extends StatefulWidget {
  const _QRScannerPage();

  @override
  State<_QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<_QRScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_hasScanned) return;
              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;
              final code = barcodes.first.rawValue;
              if (code == null || code.isEmpty) return;
              _hasScanned = true;
              Navigator.pop(context, code);
            },
          ),
          // Overlay
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text('Scan Pickup QR',
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (!kIsWeb)
                        IconButton(
                          icon: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 22),
                          onPressed: () => _controller.toggleTorch(),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  width: 240, height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Point camera at the buyer\'s QR code',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
