import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';
import 'addresses_page.dart';
import 'buyer_messages_page.dart';
import 'cart_page.dart';
import 'seller_profile_page.dart';

class ProductViewPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductViewPage({super.key, required this.product});

  @override
  State<ProductViewPage> createState() => _ProductViewPageState();
}

class _ProductViewPageState extends State<ProductViewPage> {
  static const List<String> _reviewEligibleStatuses = [
    'completed',
    'delivered',
  ];

  int _quantity = 1;
  bool _showReviews = false;
  bool _inWishlist = false;
  String? _sellerLogoUrl;
  bool _sellerIsOpen = false;
  String _sellerOpenTime = '05:00';
  String _sellerCloseTime = '19:00';
  String? _storeAddress;
  bool _sellerDeliveryEnabled = false;
  int _cartCount = 0;
  List<Map<String, dynamic>> _reviews = [];
  double _averageRating = 0;
  bool _canWriteReview = false;
  bool _isCheckingReviewEligibility = false;
  int _currentImageIndex = 0;
  late final PageController _imagePageController;

  String? get _productId {
    final candidates = [widget.product['id'], widget.product['product_id']];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  List<String> get _productImages {
    final raw = widget.product['image_urls'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final single = (widget.product['image_url'] ?? '').toString().trim();
    return single.isNotEmpty ? [single] : [];
  }

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();
    _fetchSellerLogo();
    _fetchReviews();
    _loadCartCount();
    _checkWishlist();
    _refreshReviewEligibility();
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    super.dispose();
  }

  Future<void> _checkWishlist() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final productId = _productId;
    if (productId == null || productId.isEmpty) return;
    try {
      final res = await Supabase.instance.client
          .from('wishlist')
          .select('id')
          .eq('user_id', user.id)
          .eq('product_id', productId)
          .maybeSingle();
      if (mounted) setState(() => _inWishlist = res != null);
    } catch (_) {}
  }

  Future<void> _toggleWishlist() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }
    final productId = _productId;
    if (productId == null || productId.isEmpty) return;
    try {
      if (_inWishlist) {
        await Supabase.instance.client
            .from('wishlist')
            .delete()
            .eq('user_id', user.id)
            .eq('product_id', productId);
        if (mounted) setState(() => _inWishlist = false);
      } else {
        await Supabase.instance.client.from('wishlist').insert({
          'user_id': user.id,
          'product_id': productId,
        });
        if (mounted) setState(() => _inWishlist = true);
      }
    } catch (_) {}
  }

  Future<String> _loadReviewerName(User user) async {
    try {
      final profile = await Supabase.instance.client
          .from('profile')
          .select('name')
          .eq('user_id', user.id)
          .maybeSingle();
      final profileName = profile?['name']?.toString().trim();
      if (profileName != null && profileName.isNotEmpty) {
        return profileName;
      }
    } catch (_) {}
    return preferredProfileName(user);
  }

  Future<Map<String, dynamic>?> _findEligibleReviewOrder(User user) async {
    final productId = _productId;
    if (productId == null || productId.isEmpty) return null;

    final response = await Supabase.instance.client
        .from('orders')
        .select('id, status, created_at')
        .eq('buyer_id', user.id)
        .eq('product_id', productId)
        .inFilter('status', _reviewEligibleStatuses)
        .order('created_at', ascending: false)
        .limit(1);

    final orders = List<Map<String, dynamic>>.from(response);
    return orders.isEmpty ? null : orders.first;
  }

  Future<void> _refreshReviewEligibility() async {
    final user = Supabase.instance.client.auth.currentUser;
    final productId = _productId;

    if (user == null || productId == null || productId.isEmpty) {
      if (mounted) {
        setState(() {
          _canWriteReview = false;
          _isCheckingReviewEligibility = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isCheckingReviewEligibility = true);
    }

    var canWriteReview = false;
    try {
      canWriteReview = await _findEligibleReviewOrder(user) != null;
    } catch (_) {
      canWriteReview = false;
    }

    if (mounted) {
      setState(() {
        _canWriteReview = canWriteReview;
        _isCheckingReviewEligibility = false;
      });
    }
  }

  Future<void> _showWriteReviewDialog() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    if (mounted) {
      setState(() => _isCheckingReviewEligibility = true);
    }

    Map<String, dynamic>? eligibleOrder;
    try {
      eligibleOrder = await _findEligibleReviewOrder(user);
    } catch (_) {
      eligibleOrder = null;
    }

    if (mounted) {
      setState(() {
        _canWriteReview = eligibleOrder != null;
        _isCheckingReviewEligibility = false;
      });
    }

    if (eligibleOrder == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complete a purchase before reviewing this product.'),
          ),
        );
      }
      return;
    }

    final eligibleOrderId = eligibleOrder['id'];

    int selectedRating = 5;
    final commentCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Write a Review',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your rating',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 6),
              Row(
                children: List.generate(
                  5,
                  (i) => GestureDetector(
                    onTap: () => setDlg(() => selectedRating = i + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        i < selectedRating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 32,
                        color: const Color(0xFFF5A524),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Share your experience...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(12),
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
              onPressed: () async {
                final productId = _productId;
                if (productId == null || productId.isEmpty) {
                  Navigator.pop(ctx);
                  return;
                }
                final reviewerName = await _loadReviewerName(user);
                try {
                  await Supabase.instance.client
                      .from('reviews')
                      .insert({
                        'product_id': productId,
                        'order_id': eligibleOrderId,
                        'buyer_id': user.id,
                        'reviewer_id': user.id,
                        'reviewer_name': reviewerName,
                        'rating': selectedRating,
                        'comment': commentCtrl.text.trim(),
                      })
                      .select('id')
                      .single();
                  if (mounted) {
                    await _fetchReviews();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Review submitted!')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A3C8C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    commentCtrl.dispose();
  }

  Future<void> _loadCartCount() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final res = await Supabase.instance.client
          .from('cart')
          .select('id')
          .eq('buyer_id', user.id);
      if (mounted) setState(() => _cartCount = (res as List).length);
    } catch (_) {}
  }

  Future<void> _fetchSellerLogo() async {
    final sellerId = widget.product['seller_id']?.toString();
    if (sellerId == null || sellerId.isEmpty) return;
    try {
      final resp = await Supabase.instance.client
          .from('seller_profiles')
          .select(
            'logo_url, is_open, opening_time, closing_time, store_address, delivery_enabled',
          )
          .eq('user_id', sellerId)
          .maybeSingle();
      if (mounted && resp != null) {
        setState(() {
          _sellerLogoUrl = resp['logo_url']?.toString();
          _sellerIsOpen = resp['is_open'] == true;
          _sellerOpenTime = resp['opening_time']?.toString() ?? '05:00';
          _sellerCloseTime = resp['closing_time']?.toString() ?? '19:00';
          _storeAddress = resp['store_address']?.toString();
          _sellerDeliveryEnabled = resp['delivery_enabled'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchReviews() async {
    final productId = _productId;
    if (productId == null || productId.isEmpty) {
      if (mounted) {
        setState(() {
          _reviews = [];
          _averageRating = 0;
        });
      }
      return;
    }
    try {
      final resp = await Supabase.instance.client
          .from('reviews')
          .select('*')
          .eq('product_id', productId)
          .order('created_at', ascending: false)
          .limit(20);

      final list = List<Map<String, dynamic>>.from(resp);
      final reviewerIds = list
          .map(
            (review) =>
                review['buyer_id']?.toString() ??
                review['reviewer_id']?.toString() ??
                '',
          )
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (reviewerIds.isNotEmpty) {
        try {
          final profiles = await Supabase.instance.client
              .from('profile')
              .select('user_id, avatar_url')
              .inFilter('user_id', reviewerIds);

          final avatarByUserId = <String, String>{};
          for (final profile in profiles as List) {
            final userId = profile['user_id']?.toString() ?? '';
            final avatarUrl = profile['avatar_url']?.toString().trim() ?? '';
            if (userId.isNotEmpty && avatarUrl.isNotEmpty) {
              avatarByUserId[userId] = avatarUrl;
            }
          }

          for (final review in list) {
            final reviewerId =
                review['buyer_id']?.toString() ??
                review['reviewer_id']?.toString() ??
                '';
            review['reviewer_avatar_url'] = avatarByUserId[reviewerId];
          }
        } catch (_) {
          // Ignore avatar lookup failures and keep the initials fallback.
        }
      }

      if (mounted) {
        double total = 0;
        for (final r in list) {
          total += (r['rating'] as num?)?.toDouble() ?? 0;
        }
        setState(() {
          _reviews = list;
          _averageRating = list.isNotEmpty ? total / list.length : 0;
        });
      }
    } on PostgrestException catch (e) {
      debugPrint('Failed to load reviews for product $productId: ${e.message}');
    } catch (e) {
      debugPrint('Failed to load reviews for product $productId: $e');
    }
  }

  String get _displayName {
    return (widget.product['name'] ??
            widget.product['product_name'] ??
            'Unknown product')
        .toString();
  }

  String get _sellerName {
    final store = widget.product['store_name']?.toString().trim();
    if (store != null && store.isNotEmpty) return store;
    final seller = widget.product['seller_name']?.toString().trim();
    if (seller != null && seller.isNotEmpty) return seller;
    return 'Lienda Public Market Stall';
  }

  String get _marketLocation {
    if (_storeAddress != null && _storeAddress!.isNotEmpty)
      return _storeAddress!;
    final location = widget.product['market_location']?.toString().trim();
    if (location != null && location.isNotEmpty) return location;
    return 'Public Market';
  }

  double get _rating {
    final raw = widget.product['rating'];
    final parsed = double.tryParse(raw?.toString() ?? '');
    return parsed ?? 4.6;
  }

  int get _reviewCount {
    final raw = widget.product['reviews'];
    final parsed = int.tryParse(raw?.toString() ?? '');
    return parsed ?? 110;
  }

  double get _priceValue {
    final raw = widget.product['price'] ?? widget.product['price_per_kg'];
    final numeric = raw?.toString().replaceAll(RegExp(r'[^0-9.]'), '').trim();
    return double.tryParse(numeric ?? '') ?? 0;
  }

  /// Retail price = the seller's original/reference price (compare-at price).
  /// Only meaningful when it is strictly greater than the selling price.
  double get _retailPriceValue {
    final raw = widget.product['retail_price'];
    final numeric = raw?.toString().replaceAll(RegExp(r'[^0-9.]'), '').trim();
    return double.tryParse(numeric ?? '') ?? 0;
  }

  /// True only when a real, higher original price exists.
  bool get _hasDiscount => _retailPriceValue > _priceValue && _priceValue > 0;

  /// Integer discount percentage, e.g. 20 for 20% off.
  int get _discountPercent {
    if (!_hasDiscount) return 0;
    return ((_retailPriceValue - _priceValue) / _retailPriceValue * 100)
        .round();
  }

  String get _description {
    final fromProduct = widget.product['description']?.toString().trim();
    if (fromProduct != null && fromProduct.isNotEmpty) {
      return fromProduct;
    }

    final lower = _displayName.toLowerCase();
    if (lower.contains('dalagang')) {
      return 'Fresh dalagang bukid from local fishers. Best for frying or paksiw, with tender meat and clean ocean taste.';
    }
    if (lower.contains('bangus')) {
      return 'Locally sourced bangus with firm texture, ideal for grilling and sinigang.';
    }
    if (lower.contains('tilapia')) {
      return 'Daily market tilapia, affordable and perfect for fried or stewed dishes.';
    }
    if (lower.contains('liempo')) {
      return 'Premium liempo cut from trusted market vendors. Great for inihaw and crispy pork recipes.';
    }
    return 'Freshly sourced product from verified public market vendors. Quality checked every morning for better value and freshness.';
  }

  String get _unitType {
    final unit = widget.product['unit_type']?.toString().trim();
    if (unit != null && unit.isNotEmpty) return unit;
    return 'KG';
  }

  String _formatPrice(double value) {
    if (value == value.truncateToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  Future<void> _addToCart() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    final productName = _displayName;
    final productId = _productId;

    try {
      // Check if this product is already in the cart
      Map<String, dynamic>? existing;
      if (productId != null && productId.isNotEmpty) {
        existing = await supabase
            .from('cart')
            .select('id, qty')
            .eq('buyer_id', user.id)
            .eq('product_id', productId)
            .maybeSingle();
      }
      existing ??= await supabase
          .from('cart')
          .select('id, qty')
          .eq('buyer_id', user.id)
          .eq('product_name', productName)
          .maybeSingle();

      if (existing != null) {
        final currentQty = int.tryParse(existing['qty'].toString()) ?? 0;
        await supabase
            .from('cart')
            .update({'qty': currentQty + _quantity})
            .eq('id', existing['id'])
            .eq('buyer_id', user.id);
      } else {
        await supabase.from('cart').insert({
          'product_name': productName,
          'price': _priceValue,
          'qty': _quantity,
          'buyer_id': user.id,
          'seller_id': widget.product['seller_id']?.toString(),
          'product_id': productId,
          'image_url': widget.product['image_url']?.toString(),
          'store_name':
              widget.product['store_name']?.toString() ?? 'Market Stall',
          'unit_type': (widget.product['unit_type'] ?? 'kg').toString(),
        });
      }

      if (!mounted) return;
      _loadCartCount();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $_quantity $productName to cart!')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _buyNow() async {
    final supabase = Supabase.instance.client;
    final buyerId = supabase.auth.currentUser?.id;

    if (buyerId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    // Load saved buyer delivery address + saved addresses list
    String savedAddress = '';
    List<Map<String, dynamic>> savedAddresses = [];
    try {
      final profile = await supabase
          .from('profile')
          .select('delivery_address')
          .eq('user_id', buyerId)
          .maybeSingle();
      savedAddress = profile?['delivery_address']?.toString().trim() ?? '';
    } catch (_) {}
    try {
      final res = await supabase
          .from('delivery_addresses')
          .select()
          .eq('user_id', buyerId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: true);
      savedAddresses = List<Map<String, dynamic>>.from(res);
    } catch (_) {}

    if (!mounted) return;

    // Always show Shopee-style order confirmation sheet
    final result = await _showOrderConfirmationSheet(
      savedAddress,
      savedAddresses,
    );
    if (result == null) return; // user dismissed

    final orderType = result['order_type'] as String;
    final deliveryAddress = result['delivery_address'] as String?;
    final newAddress = result['new_address'] as String?;
    final buyerNotes = result['buyer_notes'] as String?;
    final allowSubstitution = result['allow_substitution'] as bool? ?? false;
    final requestedWeight = result['requested_weight'] as double?;

    // Save updated address back to profile if changed
    if (newAddress != null &&
        newAddress.isNotEmpty &&
        newAddress != savedAddress) {
      try {
        await supabase
            .from('profile')
            .update({'delivery_address': newAddress})
            .eq('user_id', buyerId);
      } catch (_) {}
    }

    try {
      final sellerId = widget.product['seller_id']?.toString();
      final productId = _productId;
      final total = _priceValue * _quantity;

      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final rng = Random.secure();
      final pickupCode = List.generate(
        6,
        (_) => chars[rng.nextInt(chars.length)],
      ).join();

      final orderRes = await supabase
          .from('orders')
          .insert({
            'product_name': _displayName,
            'price': _priceValue,
            'qty': _quantity,
            'buyer_id': buyerId,
            'seller_id': sellerId,
            'product_id': productId,
            'image_url': widget.product['image_url']?.toString(),
            'store_name':
                widget.product['store_name']?.toString() ?? 'Market Stall',
            'unit_type': (widget.product['unit_type'] ?? 'kg').toString(),
            'total_amount': total,
            'status': 'pending',
            'pickup_code': pickupCode,
            'order_type': orderType,
            if (buyerNotes != null && buyerNotes.isNotEmpty)
              'buyer_notes': buyerNotes,
            'allow_substitution': allowSubstitution,
            if (requestedWeight != null) 'requested_weight': requestedWeight,
            if (deliveryAddress != null && deliveryAddress.isNotEmpty)
              'delivery_address': deliveryAddress,
            if (_storeAddress != null && _storeAddress!.isNotEmpty)
              'store_address': _storeAddress,
          })
          .select('id')
          .single();

      // Notify seller
      if (sellerId != null && sellerId.isNotEmpty) {
        await supabase.from('seller_notifications').insert({
          'seller_id': sellerId,
          'order_id': orderRes['id'],
          'title': 'New Order!',
          'body':
              '$_displayName x$_quantity \u2014 \u20b1${total.toStringAsFixed(0)}'
              '${orderType == 'delivery' ? ' (Delivery)' : ''}',
          'type': 'new_order',
        });
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _OrderSuccessDialog(
          orderType: orderType,
          address: deliveryAddress,
          onDone: () => Navigator.of(ctx).pop(),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Shopee-style order confirmation sheet.
  /// Shows product summary, fulfillment choice, and address input.
  /// Returns a map with 'order_type', optional 'delivery_address', optional 'new_address'.
  Future<Map<String, dynamic>?> _showOrderConfirmationSheet(
    String savedAddress,
    List<Map<String, dynamic>> savedAddresses,
  ) async {
    String selected = _sellerDeliveryEnabled ? 'delivery' : 'pickup';

    // Determine initial selected address
    final defaultAddr = savedAddresses.isNotEmpty
        ? savedAddresses.firstWhere(
            (a) => a['is_default'] == true,
            orElse: () => savedAddresses.first,
          )
        : null;
    String? selectedAddrId = defaultAddr?['id']?.toString();
    bool showCustomField = savedAddresses.isEmpty;
    final addrCtrl = TextEditingController(
      text: savedAddresses.isEmpty ? savedAddress : '',
    );
    final notesCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    bool allowSubstitution = false;
    final bool isByWeight = widget.product['is_by_weight'] == true;
    int qty = _quantity;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final total = _priceValue * qty;
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
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
                    const Text(
                      'Confirm Order',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Product summary row
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 68,
                            height: 68,
                            child: _buildSheetThumb(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _sellerName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '\u20b1${_formatPrice(_priceValue)}/$_unitType',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF153075),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Qty stepper
                        Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F4FC),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _sheetQtyBtn(Icons.remove, () {
                                    if (qty > 1) setModal(() => qty--);
                                  }),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Text(
                                      '$qty',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  _sheetQtyBtn(
                                    Icons.add,
                                    () => setModal(() => qty++),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\u20b1${_formatPrice(total)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF153075),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE5E7F0)),
                    const SizedBox(height: 14),
                    // Fulfillment section
                    const Text(
                      'Fulfillment',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DeliveryOptionTile(
                      icon: Icons.storefront_rounded,
                      title: 'Pick up at store',
                      subtitle:
                          _storeAddress != null && _storeAddress!.isNotEmpty
                          ? _storeAddress!
                          : 'Collect your order from the seller',
                      selected: selected == 'pickup',
                      onTap: () => setModal(() => selected = 'pickup'),
                    ),
                    if (_sellerDeliveryEnabled) ...[
                      const SizedBox(height: 8),
                      _DeliveryOptionTile(
                        icon: Icons.delivery_dining_rounded,
                        title: 'Delivery',
                        subtitle: 'Delivered to your address',
                        selected: selected == 'delivery',
                        onTap: () => setModal(() => selected = 'delivery'),
                      ),
                      if (selected == 'delivery') ...[
                        const SizedBox(height: 12),
                        // Saved address tiles
                        if (savedAddresses.isNotEmpty) ...[
                          const Text(
                            'Select address',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...savedAddresses.map((a) {
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
                                      ? const Color(0xFF2A4BA0).withAlpha(12)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isChosen
                                        ? const Color(0xFF2A4BA0)
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
                                      color: isChosen
                                          ? const Color(0xFF2A4BA0)
                                          : Colors.grey,
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
                                                a['label']?.toString() ??
                                                    'Home',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                  color: isChosen
                                                      ? const Color(0xFF2A4BA0)
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
                                                    color: const Color(
                                                      0xFF2A4BA0,
                                                    ).withAlpha(20),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'Default',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Color(0xFF2A4BA0),
                                                      fontWeight:
                                                          FontWeight.w700,
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
                                        color: Color(0xFF2A4BA0),
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          TextButton.icon(
                            onPressed: () => setModal(() {
                              selectedAddrId = null;
                              showCustomField = true;
                            }),
                            icon: const Icon(
                              Icons.add_location_alt_outlined,
                              size: 16,
                            ),
                            label: const Text('Use a different address'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF2A4BA0),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                        if (showCustomField || savedAddresses.isEmpty) ...[
                          if (savedAddresses.isNotEmpty)
                            const SizedBox(height: 4),
                          TextField(
                            controller: addrCtrl,
                            autofocus: savedAddresses.isEmpty,
                            decoration: InputDecoration(
                              labelText: 'Delivery Address',
                              hintText: 'House no., street, barangay, city',
                              prefixIcon: const Icon(
                                Icons.location_on_outlined,
                              ),
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
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF2A4BA0),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'Manage addresses →',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE5E7F0)),
                    const SizedBox(height: 14),
                    // ── Buyer notes & substitution ──
                    const Text(
                      'Special Instructions',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'e.g. Cut into pieces, no fat, etc.',
                        prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Allow substitution',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF374151),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'If item is unavailable, seller may replace with a similar product.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: allowSubstitution,
                          onChanged: (v) =>
                              setModal(() => allowSubstitution = v),
                          activeColor: const Color(0xFF2A4BA0),
                        ),
                      ],
                    ),
                    if (isByWeight) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Requested weight (kg)',
                          hintText: 'e.g. 0.5',
                          prefixIcon: const Icon(
                            Icons.scale_outlined,
                            size: 18,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE5E7F0)),
                    const SizedBox(height: 12),
                    // Total row
                    Row(
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '\u20b1${_formatPrice(total)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A3C8C),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          if (selected == 'delivery') {
                            String finalAddr = '';
                            if (selectedAddrId != null && !showCustomField) {
                              final a = savedAddresses.firstWhere(
                                (a) => a['id']?.toString() == selectedAddrId,
                                orElse: () => {},
                              );
                              finalAddr = a['address']?.toString() ?? '';
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
                            Navigator.pop(ctx, {
                              'order_type': selected,
                              'delivery_address': finalAddr,
                              'new_address': showCustomField ? finalAddr : null,
                              'qty': qty,
                              'buyer_notes': notesCtrl.text.trim(),
                              'allow_substitution': allowSubstitution,
                              if (isByWeight)
                                'requested_weight': double.tryParse(
                                  weightCtrl.text.trim(),
                                ),
                            });
                          } else {
                            Navigator.pop(ctx, {
                              'order_type': selected,
                              'delivery_address': null,
                              'new_address': null,
                              'qty': qty,
                              'buyer_notes': notesCtrl.text.trim(),
                              'allow_substitution': allowSubstitution,
                              if (isByWeight)
                                'requested_weight': double.tryParse(
                                  weightCtrl.text.trim(),
                                ),
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A3C8C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Place Order',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    addrCtrl.dispose();
    notesCtrl.dispose();
    weightCtrl.dispose();
    if (result != null && result.containsKey('qty')) {
      setState(() => _quantity = result['qty'] as int);
    }
    return result;
  }

  Widget _sheetQtyBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: const Color(0xFF2A4BA0)),
        ),
      ),
    );
  }

  Widget _karRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xFFD4500A)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B4226),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: valueColor ?? const Color(0xFF6B4226),
            ),
          ),
        ),
      ],
    );
  }

  /// Single-image thumbnail used inside dialogs/sheets so we don't share
  /// [_imagePageController] with a second PageView (which causes an assertion).
  Widget _buildSheetThumb() {
    final images = _productImages;
    if (images.isEmpty) {
      return const Center(
        child: Icon(Icons.image_outlined, size: 36, color: Color(0xFFB6BDCC)),
      );
    }
    final url = images.first;
    if (url.startsWith('assets/') || url.startsWith('images/')) {
      return Image.asset(url, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.image_not_supported_outlined,
                    size: 36, color: Color(0xFFB6BDCC))));
    }
    return Image.network(url, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  size: 36, color: Color(0xFFB6BDCC))));
  }

  Widget _buildDetailImage() {
    final images = _productImages;
    if (images.isEmpty) {
      return const Center(
        child: Icon(Icons.image_outlined, size: 54, color: Color(0xFFB6BDCC)),
      );
    }
    return PageView.builder(
      controller: _imagePageController,
      itemCount: images.length,
      onPageChanged: (i) => setState(() => _currentImageIndex = i),
      itemBuilder: (_, i) {
        final url = images[i];
        if (url.startsWith('assets/') || url.startsWith('images/')) {
          return Image.asset(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 54,
                color: Color(0xFFB6BDCC),
              ),
            ),
          );
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 54,
              color: Color(0xFFB6BDCC),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double total = _priceValue * _quantity;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFECEEF5),
                    ),
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: _inWishlist
                          ? const Color(0xFFFFE8E8)
                          : const Color(0xFFECEEF5),
                    ),
                    icon: Icon(
                      _inWishlist
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 20,
                      color: _inWishlist ? const Color(0xFFDC2626) : null,
                    ),
                    onPressed: _toggleWishlist,
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CartPage()),
                    ),
                    child: Stack(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFECEEF5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.shopping_cart_outlined,
                            size: 20,
                          ),
                        ),
                        if (_cartCount > 0)
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
                                '$_cartCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x11000000),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            height: 200,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F3F7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE5E7F0),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              // NotificationListener stops horizontal scroll
                              // notifications from reaching the parent
                              // SingleChildScrollView so the PageView can
                              // capture swipe gestures correctly.
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (n) =>
                                    n.metrics.axis == Axis.horizontal,
                                child: _buildDetailImage(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_productImages.length > 1)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _productImages.length,
                                (i) => _indicator(i == _currentImageIndex),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName,
                            style: const TextStyle(
                              fontSize: 29,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '₱${_formatPrice(_priceValue)}/$_unitType',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      color: Color(0xFF1A3C8C),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (_hasDiscount)
                                    Text(
                                      '₱${_formatPrice(_retailPriceValue)}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFFA7ADBC),
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                ],
                              ),
                              if (_hasDiscount)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$_discountPercent% OFF',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF16A34A),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () {
                              final sellerId = widget.product['seller_id']
                                  ?.toString();
                              if (sellerId == null || sellerId.isEmpty) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SellerProfilePage(
                                    sellerId: sellerId,
                                    initialStoreName: _sellerName,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F8FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFDDE3F5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: const Color(0xFFE8EEFF),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child:
                                        _sellerLogoUrl != null &&
                                            _sellerLogoUrl!.isNotEmpty
                                        ? Image.network(
                                            _sellerLogoUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                                  Icons.storefront_outlined,
                                                  size: 18,
                                                  color: Color(0xFFB4BAC9),
                                                ),
                                          )
                                        : const Icon(
                                            Icons.storefront_outlined,
                                            size: 18,
                                            color: Color(0xFFB4BAC9),
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _sellerName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF606777),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF4FF),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'Verified',
                                      style: TextStyle(
                                        color: Color(0xFF2A4BA0),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Shop open/closed status
                          Builder(
                            builder: (_) {
                              bool isWithinHours = false;
                              try {
                                final now = TimeOfDay.now();
                                final op = _sellerOpenTime.split(':');
                                final cl = _sellerCloseTime.split(':');
                                final openMin =
                                    int.parse(op[0]) * 60 + int.parse(op[1]);
                                final closeMin =
                                    int.parse(cl[0]) * 60 + int.parse(cl[1]);
                                final nowMin = now.hour * 60 + now.minute;
                                isWithinHours =
                                    nowMin >= openMin && nowMin <= closeMin;
                              } catch (_) {}
                              final shopOpen = _sellerIsOpen && isWithinHours;
                              return Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: shopOpen
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    shopOpen
                                        ? 'Open \u00b7 Closes ${to12Hour(_sellerCloseTime)}'
                                        : 'Closed \u00b7 Opens ${to12Hour(_sellerOpenTime)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: shopOpen
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${to12Hour(_sellerOpenTime)} \u2013 ${to12Hour(_sellerCloseTime)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF9299AA),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 6),
                          // Delivery availability badge
                          if (_sellerDeliveryEnabled)
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF2A4BA0,
                                    ).withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF2A4BA0,
                                      ).withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.delivery_dining_rounded,
                                        size: 13,
                                        color: Color(0xFF2A4BA0),
                                      ),
                                      SizedBox(width: 5),
                                      Text(
                                        'Delivery Available',
                                        style: TextStyle(
                                          color: Color(0xFF2A4BA0),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF9299AA,
                                    ).withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF9299AA,
                                      ).withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.storefront_rounded,
                                        size: 13,
                                        color: Color(0xFF9299AA),
                                      ),
                                      SizedBox(width: 5),
                                      Text(
                                        'Pick-up Only',
                                        style: TextStyle(
                                          color: Color(0xFF9299AA),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: Color(0xFF9299AA),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _marketLocation,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF9299AA),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(
                                Icons.star,
                                size: 18,
                                color: Color(0xFFF5A524),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (_averageRating > 0 ? _averageRating : _rating)
                                    .toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_reviews.isNotEmpty ? _reviews.length : _reviewCount} reviews',
                                style: const TextStyle(
                                  color: Color(0xFF8E95A6),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Message Seller button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final sellerId = widget.product['seller_id']
                                    ?.toString();
                                if (sellerId == null || sellerId.isEmpty)
                                  return;
                                openOrCreateConversation(
                                  context,
                                  sellerId: sellerId,
                                  sellerName: _sellerName,
                                  productId: _productId,
                                  sellerAvatarUrl: _sellerLogoUrl,
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFF2A4BA0),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: Color(0xFF2A4BA0),
                                size: 18,
                              ),
                              label: const Text(
                                'Message Seller',
                                style: TextStyle(
                                  color: Color(0xFF2A4BA0),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Details',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _description,
                            style: const TextStyle(
                              color: Color(0xFF626A7A),
                              height: 1.45,
                              fontSize: 14,
                            ),
                          ),
                          // ── Karinderya info card ──
                          if ((widget.product['product_type']?.toString() ??
                                  '') ==
                              'karinderya') ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF4ED),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFF6B35,
                                  ).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.restaurant_rounded,
                                        size: 16,
                                        color: Color(0xFFD4500A),
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Karinderya / Cooked Food',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFD4500A),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if ((widget.product['pricing_basis']
                                              ?.toString() ??
                                          '')
                                      .isNotEmpty)
                                    _karRow(
                                      Icons.price_change_outlined,
                                      'Pricing',
                                      widget.product['pricing_basis']
                                          .toString(),
                                    ),
                                  if ((widget.product['prep_time']
                                              ?.toString() ??
                                          '')
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    _karRow(
                                      Icons.schedule_rounded,
                                      'Ready in',
                                      widget.product['prep_time'].toString(),
                                    ),
                                  ],
                                  if ((widget.product['variants']?.toString() ??
                                          '')
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    _karRow(
                                      Icons.tune_rounded,
                                      'Options',
                                      widget.product['variants'].toString(),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  _karRow(
                                    Icons.today_rounded,
                                    'Today\'s status',
                                    widget.product['daily_available'] == false
                                        ? 'Not available today'
                                        : 'Available today',
                                    valueColor:
                                        widget.product['daily_available'] ==
                                            false
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF059669),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          // ── Reviews section (Shopee-style) ──
                          _buildReviewsSection(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Quantity',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF555D6E),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _qtyButton(
                        icon: Icons.remove,
                        onTap: () {
                          if (_quantity == 1) return;
                          setState(() {
                            _quantity -= 1;
                          });
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '$_quantity',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _qtyButton(
                        icon: Icons.add,
                        onTap: () {
                          setState(() {
                            _quantity += 1;
                          });
                        },
                      ),
                      const Spacer(),
                      Text(
                        'Total: ₱${_formatPrice(total)}',
                        style: const TextStyle(
                          color: Color(0xFF1A3C8C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _addToCart,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF1A3C8C)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text(
                            'Add To Cart',
                            style: TextStyle(
                              color: Color(0xFF1A3C8C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _buyNow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A3C8C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text(
                            'Buy Now',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
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

  Widget _indicator(bool active) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 6,
      width: active ? 20 : 8,
      decoration: BoxDecoration(
        color: active ? const Color(0xFFF5A524) : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  // ── Shopee-style reviews section ──
  Widget _buildReviewsSection() {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final hasReviews = _reviews.isNotEmpty;
    final displayRating = hasReviews ? _averageRating : 0.0;
    final displayCount = _reviews.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, color: Color(0xFFE3E6EF)),
        const SizedBox(height: 14),
        // Header row
        InkWell(
          onTap: () => setState(() => _showReviews = !_showReviews),
          child: Row(
            children: [
              const Text(
                'Product Reviews',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  if (hasReviews) ...[
                    Text(
                      '${displayRating.toStringAsFixed(1)}/5',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF5A524),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($displayCount)',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8E95A6),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ] else ...[
                    const Text(
                      'No ratings yet',
                      style: TextStyle(fontSize: 13, color: Color(0xFF8E95A6)),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    _showReviews
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: const Color(0xFF9AA1B2),
                    size: 22,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Rating summary bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8F0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: hasReviews
              ? Row(
                  children: [
                    Column(
                      children: [
                        Text(
                          displayRating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFF5A524),
                          ),
                        ),
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              i < displayRating.round()
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 16,
                              color: const Color(0xFFF5A524),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$displayCount ratings',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8E95A6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: List.generate(5, (i) {
                          final star = 5 - i;
                          final count = _reviews
                              .where(
                                (r) => (r['rating'] as num?)?.toInt() == star,
                              )
                              .length;
                          final pct = count / _reviews.length;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Text(
                                  '$star',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                                const Icon(
                                  Icons.star_rounded,
                                  size: 12,
                                  color: Color(0xFFF5A524),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      backgroundColor: const Color(0xFFE5E7EB),
                                      valueColor: const AlwaysStoppedAnimation(
                                        Color(0xFFF5A524),
                                      ),
                                      minHeight: 6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '$count',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF8E95A6),
                                    ),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.star_outline_rounded,
                      size: 28,
                      color: Color(0xFFD1A545),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No ratings yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7C8395),
                      ),
                    ),
                  ],
                ),
        ),
        // Individual reviews
        if (_showReviews) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isCheckingReviewEligibility
                  ? null
                  : _showWriteReviewDialog,
              icon: const Icon(Icons.rate_review_outlined, size: 16),
              label: const Text('Write a Review'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF2A4BA0)),
                foregroundColor: const Color(0xFF2A4BA0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          if (currentUser != null &&
              (_isCheckingReviewEligibility || !_canWriteReview))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _isCheckingReviewEligibility
                    ? 'Checking your completed purchases...'
                    : 'Complete a purchase before reviewing this product.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8E95A6)),
              ),
            ),
          const SizedBox(height: 12),
          if (_reviews.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.rate_review_outlined,
                    size: 36,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No reviews yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Be the first to review this product!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            )
          else
            ...(_reviews.take(5).map((r) {
              final name = r['reviewer_name']?.toString() ?? 'Buyer';
              final avatarUrl =
                  r['reviewer_avatar_url']?.toString().trim() ?? '';
              final rating = (r['rating'] as num?)?.toInt() ?? 5;
              final comment = r['comment']?.toString() ?? '';
              final date = r['created_at']?.toString() ?? '';
              String formattedDate = '';
              try {
                final dt = DateTime.parse(date).toLocal();
                formattedDate = '${dt.month}/${dt.day}/${dt.year}';
              } catch (_) {}

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: const Color(0xFFE8EEFF),
                          backgroundImage: avatarUrl.isNotEmpty
                              ? NetworkImage(avatarUrl)
                              : null,
                          child: avatarUrl.isEmpty
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'B',
                                  style: const TextStyle(
                                    color: Color(0xFF2A4BA0),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Row(
                                children: [
                                  ...List.generate(
                                    5,
                                    (i) => Icon(
                                      i < rating
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      size: 13,
                                      color: const Color(0xFFF5A524),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    formattedDate,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF9CA3AF),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        comment,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF4B5563),
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                  ],
                ),
              );
            })),
          if (_reviews.length > 5)
            Center(
              child: TextButton(
                onPressed: () {},
                child: Text(
                  'See all ${_reviews.length} reviews',
                  style: const TextStyle(
                    color: Color(0xFF2A4BA0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _qtyButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F4FA),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF55607A)),
      ),
    );
  }
}

// ── Delivery option tile used inside the delivery bottom sheet ──
class _DeliveryOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _DeliveryOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1A3C8C);
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

class _OrderSuccessDialog extends StatelessWidget {
  final String orderType;
  final String? address;
  final VoidCallback onDone;

  const _OrderSuccessDialog({
    required this.orderType,
    this.address,
    required this.onDone,
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
            Text(
              orderType == 'delivery' && address != null && address!.isNotEmpty
                  ? 'Your order will be delivered to:\n$address'
                  : 'Your order has been sent to the seller.\nYou will be notified once it is accepted.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDone,
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
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
