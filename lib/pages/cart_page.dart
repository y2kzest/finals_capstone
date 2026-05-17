import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cart_badge_service.dart';
import '../services/paymongo_service.dart';
import '../services/pickup_preference_service.dart';
import '../utils/delivery_route_preview.dart';
import '../utils/marketplace_ui.dart' show ShimmerBox;
import '../utils/page_transitions.dart';
import 'orders_page.dart';
import 'addresses_page.dart';
import 'payment_method_page.dart';
import 'paymongo_webview_page.dart';
import 'pick_location_page.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _cartItems = [];
  Map<String, String> _sellerLogos = {};
  // Per-seller delivery fee read from `seller_profiles.delivery_fee`. The
  // cart adds these into the order total so the buyer pays the right
  // amount based on each store's individual rate.
  Map<String, double> _sellerDeliveryFees = {};
  bool _isLoading = true;
  bool _isCheckingOut = false;
  StreamSubscription<AuthState>? _authSub;
  String _savedAddress = '';
  List<Map<String, dynamic>> _savedAddresses = [];
  String? _cartSelectedAddressId;

  static const Color _kPrimary = Color(0xFF2A4BA0);
  static const Color _kSurface = Color(0xFFF5F6FB);
  static const Color _kRed = Color(0xFFDC2626);

  TimeOfDay _parseCartPickupTime(String? time) {
    if (time == null || time.trim().isEmpty) return TimeOfDay.now();
    final normalized = time.trim().toLowerCase();
    if (normalized.contains('morning')) return const TimeOfDay(hour: 9, minute: 0);
    if (normalized.contains('afternoon')) return const TimeOfDay(hour: 14, minute: 0);
    if (normalized.contains('evening')) return const TimeOfDay(hour: 18, minute: 0);
    if (normalized.contains('all day') || normalized.contains('tomorrow')) {
      return const TimeOfDay(hour: 10, minute: 0);
    }
    try {
      final parts = time.split(' ');
      final hm = parts[0].split(':');
      int hour = int.parse(hm[0]);
      final minute = int.parse(hm[1]);
      final isPm = parts.length > 1 && parts[1].toUpperCase() == 'PM';
      if (isPm && hour != 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return TimeOfDay.now();
    }
  }

  String _formatCartPickupTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  static String _generatePickupCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    CartBadgeService.instance.ensureInitialized();
    PickupPreferenceService.instance.ensureInitialized();
    _loadCart();
    _loadSavedAddress();
    _loadSavedAddresses();
    _authSub = supabase.auth.onAuthStateChange.listen((_) {
      if (mounted) {
        _loadCart();
        _loadSavedAddress();
        _loadSavedAddresses();
      }
    });
  }

  Future<void> _loadSavedAddresses() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await supabase
          .from('delivery_addresses')
          .select()
          .eq('user_id', user.id)
          .order('is_default', ascending: false)
          .order('created_at', ascending: true);
      if (mounted) {
        final list = List<Map<String, dynamic>>.from(res);
        // Auto-select the default address if none chosen yet
        if (_cartSelectedAddressId == null && list.isNotEmpty) {
          final defaultAddr = list.firstWhere(
            (a) => a['is_default'] == true,
            orElse: () => list.first,
          );
          _cartSelectedAddressId = defaultAddr['id']?.toString();
        }
        setState(() => _savedAddresses = list);
      }
    } catch (_) {}
  }

  Future<void> _loadSavedAddress() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final profile = await supabase
          .from('profile')
          .select('delivery_address')
          .eq('user_id', user.id)
          .maybeSingle();
      if (mounted) {
        setState(
          () => _savedAddress =
              profile?['delivery_address']?.toString().trim() ?? '',
        );
      }
    } catch (_) {}
  }

  Future<void> _saveAddress(String address) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase
          .from('profile')
          .update({'delivery_address': address})
          .eq('user_id', user.id);
      if (mounted) setState(() => _savedAddress = address);
    } catch (_) {}
  }

  Future<void> _editAddress() async {
    final ctrl = TextEditingController(text: _savedAddress);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delivery Address',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'House no., street, barangay, city',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          minLines: 1,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) await _saveAddress(result);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCart() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      CartBadgeService.instance.syncFromRows(const []);
      if (mounted) {
        setState(() {
          _cartItems = [];
          _isLoading = false;
        });
      }
      return;
    }
    try {
      final res = await supabase
          .from('cart')
          .select()
          .eq('buyer_id', user.id)
          .order('id', ascending: false);
      if (!mounted) return;
      final items = List<Map<String, dynamic>>.from(res);
      // Fetch seller logos for all unique seller_ids
      final sellerIds = items
          .map((i) => i['seller_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final Map<String, String> logos = {};
      final Map<String, double> fees = {};
      if (sellerIds.isNotEmpty) {
        try {
          final profiles = await supabase
              .from('seller_profiles')
              .select('user_id, logo_url, delivery_fee, delivery_enabled')
              .inFilter('user_id', sellerIds);
          for (final p in profiles as List) {
            final id = p['user_id']?.toString();
            if (id == null) continue;
            final logo = p['logo_url']?.toString();
            if (logo != null && logo.isNotEmpty) logos[id] = logo;
            // Only count the fee when the seller has delivery turned on.
            final enabled = p['delivery_enabled'] == true;
            final feeRaw = (p['delivery_fee'] as num?)?.toDouble() ?? 0;
            if (enabled && feeRaw > 0) fees[id] = feeRaw;
          }
        } catch (_) {
          // delivery_fee column may not exist yet — fees stay empty so
          // the cart total just falls back to the subtotal.
        }
      }
      if (!mounted) return;
      setState(() {
        _cartItems = items;
        _sellerLogos = logos;
        _sellerDeliveryFees = fees;
        _isLoading = false;
      });
      CartBadgeService.instance.syncFromRows(items);
    } catch (e) {
      debugPrint('Cart load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateQty(Map<String, dynamic> item, double newQty) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final id = item['id']?.toString();
    if (id == null) return;
    if (newQty <= 0) {
      await _removeItem(item);
      return;
    }
    try {
      await supabase
          .from('cart')
          .update({'qty': newQty})
          .eq('id', id)
          .eq('buyer_id', user.id);
      await _loadCart();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
        const SnackBar(
          content: Text('Removed from cart'),
          duration: Duration(seconds: 1),
        ),
      );
      await _loadCart();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
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

  bool _isSellerCurrentlyOpen(Map<String, dynamic> info) {
    if (info['is_open'] != true) return false;
    try {
      final now = TimeOfDay.now();
      final op = (info['opening_time'] as String).split(':');
      final cl = (info['closing_time'] as String).split(':');
      final openMin = int.parse(op[0]) * 60 + int.parse(op[1]);
      final closeMin = int.parse(cl[0]) * 60 + int.parse(cl[1]);
      final nowMin = now.hour * 60 + now.minute;
      return nowMin >= openMin && nowMin <= closeMin;
    } catch (_) {
      return info['is_open'] == true;
    }
  }

  Future<void> _checkout() async {
    final user = supabase.auth.currentUser;
    if (user == null || _cartItems.isEmpty) return;

    // Safety net: block sellers from ordering products from their own shop,
    // even if the items somehow ended up in their cart.
    final ownShopItem = _cartItems.firstWhere(
      (i) => i['seller_id']?.toString() == user.id,
      orElse: () => const {},
    );
    if (ownShopItem.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You can't order from your own shop. Remove your own items first.",
          ),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isCheckingOut = true);
    try {
      // Batch-fetch seller profiles (address + delivery_enabled)
      final sellerIds = _cartItems
          .map((i) => i['seller_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      final Map<String, Map<String, dynamic>> sellerInfo = {};
      if (sellerIds.isNotEmpty) {
        try {
          final profiles = await supabase
              .from('seller_profiles')
              .select(
                  'user_id, store_name, store_address, delivery_enabled, stall_lat, stall_lng, is_open, opening_time, closing_time')
              .inFilter('user_id', sellerIds);
          for (final p in profiles as List) {
            sellerInfo[p['user_id'].toString()] = {
              'store_name': p['store_name']?.toString(),
              'store_address': p['store_address']?.toString(),
              'delivery_enabled': p['delivery_enabled'] == true,
              'stall_lat': (p['stall_lat'] as num?)?.toDouble(),
              'stall_lng': (p['stall_lng'] as num?)?.toDouble(),
              'is_open': p['is_open'] == true,
              'opening_time': p['opening_time']?.toString() ?? '05:00',
              'closing_time': p['closing_time']?.toString() ?? '19:00',
            };
          }
        } catch (_) {}
      }

      // Block checkout if any store is currently closed
      final closedStoreNames = <String>[];
      for (final sellerId in sellerIds) {
        final info = sellerInfo[sellerId];
        if (info != null && !_isSellerCurrentlyOpen(info)) {
          closedStoreNames.add(info['store_name'] as String? ?? 'A store');
        }
      }
      if (closedStoreNames.isNotEmpty) {
        setState(() => _isCheckingOut = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${closedStoreNames.join(', ')} ${closedStoreNames.length == 1 ? 'is' : 'are'} currently closed. You can\'t place orders from closed stores.',
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Determine which seller IDs have delivery enabled
      final deliverableSellers = sellerIds
          .where((id) => sellerInfo[id]?['delivery_enabled'] == true)
          .toSet();

      final preferredPickupWindow = PickupPreferenceService
          .instance
          .currentValue
          .trim();
      String? pickupTimeForOrders = preferredPickupWindow.isEmpty
          ? null
          : preferredPickupWindow;

      // If any seller in the cart supports delivery, ask the buyer once for
      // a delivery preference + address. We apply the same choice to all
      // deliverable sellers in this cart for simplicity.
      String orderType = 'pickup';
      String? deliveryAddress;
      double? deliveryLat;
      double? deliveryLng;

      if (deliverableSellers.isNotEmpty) {
        setState(() => _isCheckingOut = false);
        // Ensure addresses are fresh before showing the sheet
        await _loadSavedAddresses();
        final deliverableStalls = <StallPoint>[];
        for (final id in deliverableSellers) {
          final info = sellerInfo[id];
          final lat = info?['stall_lat'] as double?;
          final lng = info?['stall_lng'] as double?;
          if (lat == null || lng == null) continue;
          deliverableStalls.add(StallPoint(
            name: (info?['store_name'] as String?)?.trim().isNotEmpty == true
                ? info!['store_name'] as String
                : 'Stall',
            point: LatLng(lat, lng),
          ));
        }
        final result = await _showCartDeliverySheet(
          deliverableSellers.length,
          pickupTimeForOrders,
          deliverableStalls,
        );
        if (result == null) return; // user dismissed
        setState(() => _isCheckingOut = true);
        orderType = result['order_type'] as String;
        deliveryAddress = result['delivery_address'] as String?;
        deliveryLat = (result['delivery_lat'] as num?)?.toDouble();
        deliveryLng = (result['delivery_lng'] as num?)?.toDouble();
        final sheetPickupTime =
            (result['pickup_time'] as String?)?.trim();
        if (sheetPickupTime != null && sheetPickupTime.isNotEmpty) {
          pickupTimeForOrders = sheetPickupTime;
          // Persist so the home WITHIN pill reflects the buyer's latest choice.
          await PickupPreferenceService.instance.save(sheetPickupTime);
        }
        // Only save to profile if user typed a new custom address (not picked a saved tile)
        final isCustom = result['is_custom'] as bool? ?? false;
        final typedAddress = result['delivery_address'] as String?;
        if (isCustom &&
            typedAddress != null &&
            typedAddress.isNotEmpty &&
            typedAddress != _savedAddress) {
          await _saveAddress(typedAddress);
        }
      }

      final hasPickupOrders = _cartItems.any((item) {
        final sellerId = item['seller_id']?.toString();
        final itemOrderType =
            (sellerId != null && deliverableSellers.contains(sellerId))
            ? orderType
            : 'pickup';
        return itemOrderType == 'pickup';
      });

      // Ask the buyer how they want to pay (GCash / Maya / COD). The total
      // sent to the payment sheet now includes per-seller delivery fees so
      // the buyer is charged the same amount they saw on the cart summary.
      final cartSubtotal = _cartItems.fold<double>(
        0,
        (sum, i) => sum + _price(i['price']) * _qty(i['qty']),
      );
      final cartTotal = cartSubtotal + _deliveryFeeTotal;
      setState(() => _isCheckingOut = false);
      if (!mounted) return;
      final paymentChoice = await Navigator.of(context).push<PaymentMethodChoice>(
        MaterialPageRoute(
          builder: (_) => PaymentMethodPage(
            totalAmount: cartTotal,
            itemCount: _totalItems,
            shopCount: sellerIds.length,
          ),
        ),
      );
      if (paymentChoice == null) return; // buyer backed out
      if (!mounted) return;
      setState(() => _isCheckingOut = true);

      final isOnline = paymentChoice.isOnline;
      final walletMethod = paymentChoice.wallet;
      final paymentMethodCode = walletMethod?.apiValue ?? 'cod';
      final initialPaymentStatus = isOnline ? 'pending' : 'paid';

      final List<String> insertedOrderIds = [];

      for (final item in _cartItems) {
        final price = _price(item['price']);
        final qty = _qty(item['qty']);
        final sellerId = item['seller_id']?.toString();
        final pickupCode = _generatePickupCode();
        final info = sellerId != null ? sellerInfo[sellerId] : null;

        // Use delivery only for sellers who have it enabled
        final itemOrderType =
            (sellerId != null && deliverableSellers.contains(sellerId))
            ? orderType
            : 'pickup';
        final itemDeliveryAddress = itemOrderType == 'delivery'
            ? deliveryAddress
            : null;
        final itemDeliveryLat =
            itemOrderType == 'delivery' ? deliveryLat : null;
        final itemDeliveryLng =
            itemOrderType == 'delivery' ? deliveryLng : null;
        final stallLat = info?['stall_lat'] as double?;
        final stallLng = info?['stall_lng'] as double?;

        final orderData = <String, dynamic>{
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
          'order_type': itemOrderType,
          // Snapshot the seller's delivery fee on every order row so the
          // amount the buyer sees on the order detail screen matches what
          // they were charged at checkout, even if the seller later
          // changes their fee. Only populated when this row is being
          // delivered — pickup orders skip the fee entirely.
          if (itemOrderType == 'delivery' && sellerId != null)
            'delivery_fee': _sellerDeliveryFees[sellerId] ?? 0,
          'payment_method': paymentMethodCode,
          'payment_status': initialPaymentStatus,
          if ((item['selected_variant'] as String?)?.isNotEmpty == true)
            'selected_variant': item['selected_variant'],
          if (itemDeliveryAddress != null && itemDeliveryAddress.isNotEmpty)
            'delivery_address': itemDeliveryAddress,
          if (itemDeliveryLat != null) 'delivery_lat': itemDeliveryLat,
          if (itemDeliveryLng != null) 'delivery_lng': itemDeliveryLng,
          if (info?['store_address'] != null &&
              (info!['store_address'] as String).isNotEmpty)
            'store_address': info['store_address'],
          // Snapshot the stall coords on every order so the order's map view is
          // stable even if the seller later moves their pin.
          if (stallLat != null) 'store_lat': stallLat,
          if (stallLng != null) 'store_lng': stallLng,
          // Include scheduled pickup window for pickup orders
          if (itemOrderType == 'pickup' && pickupTimeForOrders != null)
            'pickup_time': pickupTimeForOrders,
        };

        final orderRes = await supabase
            .from('orders')
            .insert(orderData)
            .select('id')
            .single();
        insertedOrderIds.add(orderRes['id'].toString());

        // For online payments we hold off on notifying the seller until the
        // PayMongo webhook confirms the payment — see paymongo-webhook fn.
        if (!isOnline && sellerId != null && sellerId.isNotEmpty) {
          await supabase.from('seller_notifications').insert({
            'seller_id': sellerId,
            'order_id': orderRes['id'],
            'title': 'New Order!',
            'body':
                '${item['product_name'] ?? 'Item'} x$qty - P${(price * qty).toStringAsFixed(0)}'
                '${itemOrderType == 'delivery' ? ' (Delivery)' : ''}',
            'type': 'new_order',
          });
        }

        // Buyer notification
        await supabase.from('notifications').insert({
          'user_id': user.id,
          'type': isOnline ? 'order_pending_payment' : 'order_placed',
          'title': isOnline ? 'Awaiting Payment' : 'Order Placed',
          'message': isOnline
              ? '${item['product_name'] ?? 'Item'} x$qty — waiting for your '
                  '${walletMethod?.label ?? 'online'} payment'
              : '${item['product_name'] ?? 'Item'} x$qty — P${(price * qty).toStringAsFixed(0)} order sent to ${item['store_name'] ?? 'seller'}',
          'is_read': false,
        });
      }

      // COD path: clear cart immediately and celebrate
      if (!isOnline) {
        await _clearCart();
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _CheckoutSuccessDialog(
            pickupTime: hasPickupOrders ? pickupTimeForOrders : null,
            onViewOrders: () {
              Navigator.of(ctx).pop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersPage()),
              );
            },
            onContinue: () => Navigator.of(ctx).pop(),
          ),
        );
        return;
      }

      // Online payment path: create PayMongo source, open WebView, poll status
      final amountCentavos = (cartTotal * 100).round();
      final buyerEmail = user.email ?? '';
      final buyerName =
          (user.userMetadata?['full_name'] as String?)?.trim() ?? '';

      final PaymongoCheckout checkout;
      try {
        checkout = await PaymongoService.instance.createWalletCheckout(
          orderIds: insertedOrderIds,
          method: walletMethod!,
          amountCentavos: amountCentavos,
          email: buyerEmail,
          name: buyerName,
        );
      } on PaymongoException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start payment: ${e.message}'),
            backgroundColor: _kRed,
          ),
        );
        return;
      }

      if (!mounted) return;
      final webResult = await Navigator.of(context).push<PaymongoWebResult>(
        MaterialPageRoute(
          builder: (_) => PaymongoWebViewPage(
            checkoutUrl: checkout.checkoutUrl,
            methodLabel: walletMethod.label,
            pollOrderId: insertedOrderIds.first,
          ),
        ),
      );
      if (!mounted) return;

      if (webResult == PaymongoWebResult.success) {
        // PayMongo redirected to our success_url. Confirm via webhook-updated
        // order row (the webhook flips payment_status to 'paid').
        setState(() => _isCheckingOut = true);
        final finalStatus = await PaymongoService.instance
            .waitForPaymentResult(insertedOrderIds.first);
        if (!mounted) return;

        if (finalStatus == 'paid') {
          await _clearCart();
          if (!mounted) return;
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => _CheckoutSuccessDialog(
              pickupTime: hasPickupOrders ? pickupTimeForOrders : null,
              onViewOrders: () {
                Navigator.of(ctx).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OrdersPage()),
                );
              },
              onContinue: () => Navigator.of(ctx).pop(),
            ),
          );
        } else {
          // Webhook hasn't flipped it yet — clear the cart anyway since orders
          // exist; the buyer can refresh Orders in a moment.
          await _clearCart();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Payment received. Confirming with the bank — check Orders in a moment.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (webResult == PaymongoWebResult.failed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Payment was declined. Your orders are saved — try again from Orders.',
            ),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        // cancelled / dismissed
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment cancelled. Your orders are saved — you can pay later from Orders.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout failed: $e'), backgroundColor: _kRed),
      );
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  /// Bottom sheet for delivery choice during cart checkout.
  Future<Map<String, dynamic>?> _showCartDeliverySheet(
    int deliverableShops,
    String? pickupPreference,
    List<StallPoint> deliverableStalls,
  ) async {
    // Determine initial selection - prefer cart-selected address, then default
    Map<String, dynamic>? defaultAddr;
    if (_cartSelectedAddressId != null) {
      try {
        defaultAddr = _savedAddresses.firstWhere(
          (a) => a['id']?.toString() == _cartSelectedAddressId,
        );
      } catch (_) {}
    }
    defaultAddr ??= _savedAddresses.isNotEmpty
        ? _savedAddresses.firstWhere(
            (a) => a['is_default'] == true,
            orElse: () => _savedAddresses.first,
          )
        : null;

    String selected = 'pickup';
    String? selectedAddrId = defaultAddr?['id']?.toString();
    String? chosenPickupTime = pickupPreference;
    final addrCtrl = TextEditingController(
      text: defaultAddr == null ? _savedAddress : '',
    );
    bool showCustomField = _savedAddresses.isEmpty && _savedAddress.isNotEmpty;

    if (defaultAddr != null || _savedAddress.isNotEmpty) {
      selected = 'delivery';
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$deliverableShops shop${deliverableShops == 1 ? ' offers' : 's offer'} delivery',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'How would you like to receive your orders?',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final initial = _parseCartPickupTime(chosenPickupTime);
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: initial,
                          helpText: 'Pickup time for pickup orders',
                          builder: (c, child) => MediaQuery(
                            data: MediaQuery.of(c).copyWith(
                              alwaysUse24HourFormat: false,
                            ),
                            child: child!,
                          ),
                        );
                        if (picked == null) return;
                        setModal(() {
                          chosenPickupTime = _formatCartPickupTime(picked);
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE5EAF5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.schedule_outlined,
                              color: _kPrimary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                chosenPickupTime == null ||
                                        chosenPickupTime!.isEmpty
                                    ? 'Tap to set pickup time'
                                    : 'Pickup time: $chosenPickupTime',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF374151),
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.edit_outlined,
                              color: _kPrimary,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _CartDeliveryTile(
                    icon: Icons.storefront_rounded,
                    title: 'Pick up at store',
                    subtitle: 'Collect each order from the seller',
                    selected: selected == 'pickup',
                    onTap: () => setModal(() => selected = 'pickup'),
                  ),
                  const SizedBox(height: 10),
                  _CartDeliveryTile(
                    icon: Icons.delivery_dining_rounded,
                    title: 'Delivery',
                    subtitle:
                        'Delivered to your address (delivery-enabled shops only)',
                    selected: selected == 'delivery',
                    onTap: () => setModal(() => selected = 'delivery'),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable:
                        PickupPreferenceService.instance.preferredPickup,
                    builder: (context, pickupWindow, _) =>
                        _summaryRow('Pickup time', pickupWindow),
                  ),
                  if (selected == 'delivery') ...[
                    const SizedBox(height: 14),
                    Builder(builder: (_) {
                      LatLng? buyerPin;
                      if (selectedAddrId != null) {
                        final picked = _savedAddresses.firstWhere(
                          (a) => a['id']?.toString() == selectedAddrId,
                          orElse: () => {},
                        );
                        final lat = (picked['lat'] as num?)?.toDouble();
                        final lng = (picked['lng'] as num?)?.toDouble();
                        if (lat != null && lng != null) {
                          buyerPin = LatLng(lat, lng);
                        }
                      }
                      return DeliveryRoutePreview(
                        shops: deliverableStalls,
                        buyer: buyerPin,
                      );
                    }),
                    const SizedBox(height: 14),
                    // Saved addresses
                    if (_savedAddresses.isNotEmpty) ...[
                      const Text(
                        'Select address',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._savedAddresses.map((a) {
                        final id = a['id']?.toString();
                        final isChosen = selectedAddrId == id;
                        return GestureDetector(
                          onTap: () => setModal(() {
                            selectedAddrId = id;
                            showCustomField = false;
                          }),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isChosen
                                  ? _kPrimary.withAlpha(12)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isChosen
                                    ? _kPrimary
                                    : Colors.grey.shade300,
                                width: isChosen ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  a['label'] == 'Work'
                                      ? Icons.work_outline_rounded
                                      : Icons.home_outlined,
                                  color: isChosen ? _kPrimary : Colors.grey,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            a['label']?.toString() ?? 'Home',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: isChosen
                                                  ? _kPrimary
                                                  : const Color(0xFF111827),
                                            ),
                                          ),
                                          if (a['is_default'] == true) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _kPrimary.withAlpha(20),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: const Text(
                                                'Default',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: _kPrimary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (a['lat'] == null ||
                                              a['lng'] == null) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEE2E2),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: const Text(
                                                'Needs pin',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Color(0xFFB91C1C),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        a['address']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isChosen)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: _kPrimary,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setModal(() {
                                selectedAddrId = null;
                                showCustomField = true;
                              });
                            },
                            icon: const Icon(
                              Icons.edit_note_rounded,
                              size: 16,
                            ),
                            label: const Text('Type a different address'),
                            style: TextButton.styleFrom(
                              foregroundColor: _kPrimary,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () async {
                              final picked =
                                  await Navigator.push<Map<String, dynamic>>(
                                ctx,
                                MaterialPageRoute(
                                  builder: (_) => const PickLocationPage(),
                                ),
                              );
                              if (picked == null) return;
                              final user =
                                  supabase.auth.currentUser;
                              if (user == null) return;
                              try {
                                final inserted = await supabase
                                    .from('delivery_addresses')
                                    .insert({
                                  'user_id': user.id,
                                  'label': picked['label'],
                                  'address': picked['address'],
                                  'lat': picked['lat'],
                                  'lng': picked['lng'],
                                  'is_default': _savedAddresses.isEmpty,
                                })
                                    .select()
                                    .single();
                                await _loadSavedAddresses();
                                final newId =
                                    inserted['id']?.toString();
                                setModal(() {
                                  selectedAddrId = newId;
                                  showCustomField = false;
                                  addrCtrl.text = '';
                                });
                              } on PostgrestException catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Could not save: ${e.message}'),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(
                              Icons.add_location_alt_rounded,
                              size: 16,
                            ),
                            label: const Text('Pin on Map'),
                            style: TextButton.styleFrom(
                              foregroundColor: _kPrimary,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (showCustomField || _savedAddresses.isEmpty) ...[
                      if (_savedAddresses.isNotEmpty) const SizedBox(height: 4),
                      TextField(
                        controller: addrCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Delivery Address',
                          hintText: 'House no., street, barangay, city',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        minLines: 1,
                        maxLines: 3,
                      ),
                    ],
                    // Link to manage addresses page
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AddressesPage(),
                            ),
                          );
                          await _loadSavedAddresses();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: _kPrimary,
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text(
                          'Manage addresses →',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        if (selected == 'delivery') {
                          // Resolve the final address + coords
                          String finalAddr = '';
                          double? finalLat;
                          double? finalLng;
                          if (selectedAddrId != null && !showCustomField) {
                            final a = _savedAddresses.firstWhere(
                              (a) => a['id']?.toString() == selectedAddrId,
                              orElse: () => {},
                            );
                            finalAddr = a['address']?.toString() ?? '';
                            finalLat = (a['lat'] as num?)?.toDouble();
                            finalLng = (a['lng'] as num?)?.toDouble();
                          } else {
                            finalAddr = addrCtrl.text.trim();
                          }
                          if (finalAddr.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please select or enter a delivery address.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (finalLat == null || finalLng == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'This address has no map pin. Tap "Pin on Map" so the rider can find you.',
                                ),
                                duration: const Duration(seconds: 4),
                                action: SnackBarAction(
                                  label: 'PIN NOW',
                                  textColor: Colors.white,
                                  onPressed: () async {
                                    final picked =
                                        await Navigator.push<Map<String, dynamic>>(
                                      ctx,
                                      MaterialPageRoute(
                                        builder: (_) => PickLocationPage(
                                          initialAddress: finalAddr,
                                        ),
                                      ),
                                    );
                                    if (picked == null) return;
                                    final user = supabase.auth.currentUser;
                                    if (user == null) return;
                                    try {
                                      final inserted = await supabase
                                          .from('delivery_addresses')
                                          .insert({
                                            'user_id': user.id,
                                            'label': picked['label'],
                                            'address': picked['address'],
                                            'lat': picked['lat'],
                                            'lng': picked['lng'],
                                            'is_default': _savedAddresses.isEmpty,
                                          })
                                          .select()
                                          .single();
                                      await _loadSavedAddresses();
                                      setModal(() {
                                        selectedAddrId =
                                            inserted['id']?.toString();
                                        showCustomField = false;
                                        addrCtrl.text = '';
                                      });
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                              content: Text('Save failed: $e')),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx, {
                            'order_type': 'delivery',
                            'delivery_address': finalAddr,
                            'delivery_lat': finalLat,
                            'delivery_lng': finalLng,
                            'is_custom': showCustomField,
                            'pickup_time': chosenPickupTime,
                          });
                        } else {
                          Navigator.pop(ctx, {
                            'order_type': 'pickup',
                            'delivery_address': null,
                            'pickup_time': chosenPickupTime,
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Confirm & Place Orders',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    addrCtrl.dispose();
    return result;
  }

  double _price(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _qty(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 1.0;
  }

  String _name(Map<String, dynamic> item) {
    final n = item['product_name']?.toString().trim() ?? '';
    return n.isEmpty ? 'Market Item' : n;
  }

  String _store(Map<String, dynamic> item) {
    final s = item['store_name']?.toString().trim() ?? '';
    return s.isEmpty ? 'Market Stall' : s;
  }

  String _image(Map<String, dynamic> item) =>
      item['image_url']?.toString().trim() ?? '';

  Map<String, List<Map<String, dynamic>>> _groupByShop(
    List<Map<String, dynamic>> items,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      grouped.putIfAbsent(_store(item), () => []).add(item);
    }
    return grouped;
  }

  double get _subtotal {
    double t = 0;
    for (final i in _cartItems) {
      t += _price(i['price']) * _qty(i['qty']);
    }
    return t;
  }

  int get _totalItems => _cartItems.length;

  /// Sum of each distinct shop's delivery fee in this cart. Charged once
  /// per store, regardless of how many items the buyer ordered from it.
  double get _deliveryFeeTotal {
    final sellerIds = _cartItems
        .map((i) => i['seller_id']?.toString())
        .whereType<String>()
        .toSet();
    var total = 0.0;
    for (final id in sellerIds) {
      total += _sellerDeliveryFees[id] ?? 0;
    }
    return total;
  }

  double get _grandTotal => _subtotal + _deliveryFeeTotal;

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
                  ? _buildCartShimmer()
                  : _cartItems.isEmpty
                  ? _buildEmptyCart()
                  : RefreshIndicator(
                      onRefresh: _loadCart,
                      color: _kPrimary,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          _buildOrderSummaryHeader(),
                          const SizedBox(height: 12),
                          _buildAddressCard(),
                          const SizedBox(height: 12),
                          ..._groupByShop(
                            _cartItems,
                          ).entries.map((e) => _buildShopGroup(e.key, e.value)),
                          const SizedBox(height: 12),
                          _buildPriceBreakdown(),
                          const SizedBox(height: 8),
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

  Widget _buildHeaderPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    final shopCount = _groupByShop(_cartItems).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A4BA0), Color(0xFF153075)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x221A4DBE),
            blurRadius: 18,
            offset: Offset(0, 8),
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
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(42, 42),
                ),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CHECKOUT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: Color(0xFFDCE6FF),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'My Cart',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              if (_cartItems.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Text('Clear Cart?'),
                        content: const Text('Remove all items from your cart?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Clear',
                              style: TextStyle(color: Color(0xFFDC2626)),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) await _clearCart();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Clear',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _cartItems.isEmpty
                ? 'Fresh picks from the plaza will show up here.'
                : '$shopCount shop${shopCount == 1 ? '' : 's'} · $_totalItems item${_totalItems == 1 ? '' : 's'} ready for checkout',
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Color(0xFFDCE6FF),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_cartItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildHeaderPill(Icons.storefront_rounded, '$shopCount shops'),
                _buildHeaderPill(
                  Icons.shopping_bag_rounded,
                  '$_totalItems items',
                ),
                _buildHeaderPill(
                  Icons.payments_rounded,
                  '₱${_subtotal.toStringAsFixed(0)}',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    // Find the currently selected address from profile saved addresses
    Map<String, dynamic>? selectedAddr;
    if (_cartSelectedAddressId != null) {
      try {
        selectedAddr = _savedAddresses.firstWhere(
          (a) => a['id']?.toString() == _cartSelectedAddressId,
        );
      } catch (_) {
        selectedAddr = null;
      }
    }
    if (selectedAddr == null && _savedAddresses.isNotEmpty) {
      selectedAddr = _savedAddresses.first;
      _cartSelectedAddressId = selectedAddr['id']?.toString();
    }

    final hasAddr = selectedAddr != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
        border: hasAddr
            ? Border.all(color: _kPrimary.withValues(alpha: 0.2), width: 1)
            : null,
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: hasAddr
                        ? _kPrimary.withValues(alpha: 0.1)
                        : const Color(0xFFF1F3F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    hasAddr
                        ? Icons.location_on_rounded
                        : Icons.add_location_alt_outlined,
                    color: hasAddr ? _kPrimary : const Color(0xFF9CA3AF),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DELIVERY',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Color(0xFF8B95A7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Saved Addresses',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddressesPage()),
                    );
                    await _loadSavedAddresses();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: _kPrimary,
                    backgroundColor: _kPrimary.withValues(alpha: 0.06),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Manage',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          if (!hasAddr)
            Padding(
              padding: const EdgeInsets.all(14),
              child: GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddressesPage()),
                  );
                  await _loadSavedAddresses();
                },
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F3F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Color(0xFF9CA3AF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No saved addresses',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Tap to add your delivery address',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFD1D5DB),
                      size: 20,
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Column(
                children: [
                  ..._savedAddresses.take(3).map((addr) {
                    final addrId = addr['id']?.toString();
                    final isSelected = addrId == _cartSelectedAddressId;
                    final label = addr['label']?.toString() ?? 'Home';
                    final text = addr['address']?.toString() ?? '';
                    final isDefAddr = addr['is_default'] == true;

                    IconData labelIcon;
                    if (label == 'Work') {
                      labelIcon = Icons.work_outline_rounded;
                    } else if (label == 'Other') {
                      labelIcon = Icons.place_outlined;
                    } else {
                      labelIcon = Icons.home_outlined;
                    }

                    return GestureDetector(
                      onTap: () =>
                          setState(() => _cartSelectedAddressId = addrId),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _kPrimary.withValues(alpha: 0.05)
                              : const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? _kPrimary
                                : const Color(0xFFE5E7EB),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              labelIcon,
                              size: 18,
                              color: isSelected
                                  ? _kPrimary
                                  : const Color(0xFF9CA3AF),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? _kPrimary
                                              : const Color(0xFF374151),
                                        ),
                                      ),
                                      if (isDefAddr) ...[
                                        const SizedBox(width: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _kPrimary.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'Default',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: _kPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    text,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF6B7280),
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: _kPrimary,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  if (_savedAddresses.length > 3)
                    TextButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddressesPage(),
                          ),
                        );
                        await _loadSavedAddresses();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: _kPrimary,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'See ${_savedAddresses.length - 3} more address${_savedAddresses.length - 3 == 1 ? '' : 'es'} →',
                        style: const TextStyle(
                          fontSize: 12,
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

  // ignore: unused_element
  Widget _buildOrderSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAF5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.shopping_cart_rounded,
              color: _kPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CART SNAPSHOT',
                  style: TextStyle(
                    color: Color(0xFF8B95A7),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_totalItems item${_totalItems == 1 ? '' : 's'} in cart',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'From ${_groupByShop(_cartItems).length} shop${_groupByShop(_cartItems).length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'P${_subtotal.toStringAsFixed(0)}',
            style: const TextStyle(
              color: _kPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopGroup(String shopName, List<Map<String, dynamic>> items) {
    double shopTotal = 0;
    final itemCount = items.length;
    for (final i in items) {
      shopTotal += _price(i['price']) * _qty(i['qty']);
    }
    final sellerId = items.first['seller_id']?.toString();
    final logoUrl = sellerId != null ? _sellerLogos[sellerId] : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAF5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _kPrimary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFE8EDF8),
                      width: 1,
                    ),
                  ),
                  child: logoUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.network(
                            logoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Center(
                              child: Text(
                                shopName.isNotEmpty
                                    ? shopName[0].toUpperCase()
                                    : 'S',
                                style: const TextStyle(
                                  color: _kPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            shopName.isNotEmpty
                                ? shopName[0].toUpperCase()
                                : 'S',
                            style: const TextStyle(
                              color: _kPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SHOP',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF8B95A7),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shopName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$itemCount item${itemCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _kPrimary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '\u20b1${shopTotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _kPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          ...items.asMap().entries.map(
                (e) => FadeInOnMount(
                  delay: Duration(milliseconds: (e.key * 35).clamp(0, 240)),
                  child: _buildCartItemTile(e.value),
                ),
              ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildCartItemTile(Map<String, dynamic> item) {
    final price = _price(item['price']);
    final qty = _qty(item['qty']);
    final unit = (item['unit_type'] ?? 'kg').toString();
    final imgUrl = _image(item);
    final subtotal = price * qty;
    const step = 1.0;
    const minQty = 1.0;
    String fmtQty(double v) =>
        v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

    return Dismissible(
      key: ValueKey(item['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: _kRed.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(0),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_rounded, color: _kRed, size: 22),
            const SizedBox(height: 3),
            Text(
              'Remove',
              style: TextStyle(
                color: _kRed,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) {
        // Optimistically remove from local list immediately so no setState
        // from a concurrent async op can try to rebuild a dismissed Dismissible
        // in the wrong build scope.
        setState(() {
          _cartItems = _cartItems.where((i) => i['id'] != item['id']).toList();
        });
        _removeItem(item);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: imgUrl.isEmpty
                    ? Container(
                        color: const Color(0xFFF1F3F9),
                        child: const Icon(
                          Icons.image_outlined,
                          color: Color(0xFFB6BDCC),
                          size: 28,
                        ),
                      )
                    : Image.network(
                        imgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFFF1F3F9),
                          child: const Icon(
                            Icons.image_outlined,
                            color: Color(0xFFB6BDCC),
                            size: 28,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name(item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '\u20b1${price.toStringAsFixed(0)} / $unit',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if ((item['selected_variant'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item['selected_variant'] as String,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2A4BA0),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F4FC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E9F5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _qtyButton(
                              Icons.remove,
                              () => _updateQty(item, (qty - step).clamp(minQty, double.infinity)),
                            ),
                            SizedBox(
                              width: 36,
                              child: Text(
                                fmtQty(qty),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ),
                            _qtyButton(
                              Icons.add,
                              () => _updateQty(item, qty + step),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '\u20b1${subtotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _kPrimary,
                        ),
                      ),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAF5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CHECKOUT PREVIEW',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8B95A7),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Order Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow(
            'Subtotal ($_totalItems item${_totalItems == 1 ? '' : 's'})',
            '\u20b1${_subtotal.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),
          _summaryRow('Shops', '${_groupByShop(_cartItems).length}'),
          const SizedBox(height: 8),
          _summaryRow(
            'Delivery fee',
            _deliveryFeeTotal > 0
                ? '\u20b1${_deliveryFeeTotal.toStringAsFixed(2)}'
                : 'Free',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF3F4F6)),
          ),
          Row(
            children: [
              const Text(
                'Estimated Total',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                ),
              ),
              const Spacer(),
              Text(
                '\u20b1${_grandTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _kPrimary,
                ),
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
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutBar() {
    final hasAddress = _savedAddress.isNotEmpty;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _editAddress,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5EAF5)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 14,
                      color: hasAddress ? _kPrimary : const Color(0xFFD1D5DB),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hasAddress ? _savedAddress : 'Add delivery address',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasAddress
                              ? const Color(0xFF374151)
                              : const Color(0xFFB0B8C4),
                          fontWeight: hasAddress
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: Color(0xFFB0B8C4),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Ready to checkout',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '\u20b1${_grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _kPrimary,
                        ),
                      ),
                      if (_deliveryFeeTotal > 0)
                        Text(
                          'incl. \u20b1${_deliveryFeeTotal.toStringAsFixed(2)} delivery',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                    ],
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isCheckingOut
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Checkout ($_totalItems)',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartShimmer() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        ShimmerBox(height: 84, borderRadius: BorderRadius.circular(20)),
        const SizedBox(height: 12),
        ShimmerBox(height: 70, borderRadius: BorderRadius.circular(20)),
        const SizedBox(height: 14),
        ...List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFEDEFF6)),
              ),
              child: Row(
                children: [
                  ShimmerBox(
                    width: 72,
                    height: 72,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(
                          height: 14,
                          width: 180,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        const SizedBox(height: 8),
                        ShimmerBox(
                          height: 12,
                          width: 110,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        const SizedBox(height: 14),
                        ShimmerBox(
                          height: 18,
                          width: 80,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 42,
                color: _kPrimary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your cart is empty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Fresh products from San Fernando Market\nare waiting for you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF9CA3AF),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 46,
              width: 190,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: const Text(
                  'Browse Products',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
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
        ),
      ),
    );
  }
}

class _CheckoutSuccessDialog extends StatelessWidget {
  final String? pickupTime;
  final VoidCallback onViewOrders;
  final VoidCallback onContinue;
  const _CheckoutSuccessDialog({
    this.pickupTime,
    required this.onViewOrders,
    required this.onContinue,
  });

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
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF059669),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Order Placed!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your order has been sent to the seller.\nYou will be notified once it is accepted.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            if (pickupTime != null && pickupTime!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDDE3F5)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      size: 18,
                      color: Color(0xFF2A4BA0),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pickup time for pickup orders: $pickupTime',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onViewOrders,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A4BA0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'View My Orders',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onContinue,
              child: const Text(
                'Continue Shopping',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable delivery option tile used in the cart delivery sheet ──
class _CartDeliveryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _CartDeliveryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2A4BA0);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.06)
              : const Color(0xFFF8F9FC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : const Color(0xFFE5E7F0),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? primary.withValues(alpha: 0.1)
                    : const Color(0xFFEEEFF3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: selected ? primary : const Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: selected ? primary : const Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: primary, size: 20),
          ],
        ),
      ),
    );
  }
}
