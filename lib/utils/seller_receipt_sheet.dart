import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../seller_pages/order.dart';

class SellerReceiptSheet extends StatefulWidget {
  const SellerReceiptSheet({super.key, required this.orderId});
  final String orderId;

  @override
  State<SellerReceiptSheet> createState() => _SellerReceiptSheetState();
}

class _SellerReceiptSheetState extends State<SellerReceiptSheet> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client
          .from('orders')
          .select()
          .eq('id', widget.orderId)
          .maybeSingle();
      if (mounted) setState(() { _order = res; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m $period';
    } catch (_) { return ''; }
  }

  static String methodLabel(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'gcash':   return 'GCash';
      case 'paymaya':
      case 'maya':    return 'Maya';
      case 'cod':     return 'Cash on Delivery';
      default:        return raw?.isNotEmpty == true ? raw! : 'Online';
    }
  }

  static Color methodColor(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'gcash':   return const Color(0xFF007DFF);
      case 'paymaya':
      case 'maya':    return const Color(0xFF00A859);
      default:        return const Color(0xFF059669);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 28,
      ),
      child: _loading
          ? const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          : _error != null
              ? SizedBox(
                  height: 180,
                  child: Center(
                    child: Text(
                      'Could not load order.',
                      style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                    ),
                  ),
                )
              : _buildReceipt(context),
    );
  }

  Widget _buildReceipt(BuildContext context) {
    final order = _order;
    if (order == null) {
      return const SizedBox(
        height: 140,
        child: Center(child: Text('Order not found.', style: TextStyle(color: Color(0xFF6B7280)))),
      );
    }

    final productName = order['product_name']?.toString() ?? 'Item';
    final qty        = order['qty'];
    final qtyNum     = qty is num ? qty.toDouble() : (double.tryParse(qty?.toString() ?? '') ?? 1.0);
    final unitType   = order['unit_type']?.toString() ?? 'kg';
    final price      = (order['price'] as num?)?.toDouble() ?? 0;
    final total      = (order['total_amount'] as num?)?.toDouble() ?? price * qtyNum;
    final payMethod  = order['payment_method']?.toString();
    final variant    = order['selected_variant']?.toString();
    final shortId    = widget.orderId.length >= 8
        ? widget.orderId.substring(0, 8).toUpperCase()
        : widget.orderId.toUpperCase();
    final dateStr    = _formatDate(order['updated_at']?.toString() ?? order['created_at']?.toString());
    final label      = methodLabel(payMethod);
    final color      = methodColor(payMethod);
    final qtyDisplay = qtyNum % 1 == 0 ? qtyNum.toInt().toString() : qtyNum.toStringAsFixed(2);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Success circle
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF059669).withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 36),
        ),
        const SizedBox(height: 12),

        const Text(
          'Payment Confirmed',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 6),

        // Method badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // Details card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A4BA0).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.shopping_bag_rounded, color: Color(0xFF2A4BA0), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                        ),
                        if (variant != null && variant.isNotEmpty)
                          Text(variant, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                        Text('$qtyDisplay $unitType', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                      ],
                    ),
                  ),
                  Text(
                    '₱${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: Color(0xFFE2E8F0)),
              ),
              _row('Payment Method', label, color),
              const SizedBox(height: 8),
              _row('Amount Paid', '₱${total.toStringAsFixed(2)}', const Color(0xFF059669)),
              const SizedBox(height: 8),
              _row('Order Ref', '#$shortId', const Color(0xFF94A3B8)),
              if (dateStr.isNotEmpty) ...[
                const SizedBox(height: 8),
                _row('Date', dateStr, const Color(0xFF94A3B8)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersPage()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A4BA0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            child: const Text('View Full Order', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: valueColor)),
      ],
    );
  }
}

void showSellerReceipt(BuildContext context, String orderId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SellerReceiptSheet(orderId: orderId),
  );
}
