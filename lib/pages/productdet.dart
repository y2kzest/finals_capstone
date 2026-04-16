import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/helpers.dart';

class ProductViewPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductViewPage({super.key, required this.product});

  @override
  State<ProductViewPage> createState() => _ProductViewPageState();
}

class _ProductViewPageState extends State<ProductViewPage> {
  int _quantity = 1;
  bool _showReviews = false;
  String? _sellerLogoUrl;
  bool _sellerIsOpen = false;
  String _sellerOpenTime = '05:00';
  String _sellerCloseTime = '19:00';
  List<Map<String, dynamic>> _reviews = [];
  double _averageRating = 0;

  @override
  void initState() {
    super.initState();
    _fetchSellerLogo();
    _fetchReviews();
  }

  Future<void> _fetchSellerLogo() async {
    final sellerId = widget.product['seller_id']?.toString();
    if (sellerId == null || sellerId.isEmpty) return;
    try {
      final resp = await Supabase.instance.client
          .from('seller_profiles')
          .select('logo_url, is_open, opening_time, closing_time')
          .eq('user_id', sellerId)
          .maybeSingle();
      if (mounted && resp != null) {
        setState(() {
          _sellerLogoUrl = resp['logo_url']?.toString();
          _sellerIsOpen = resp['is_open'] == true;
          _sellerOpenTime = resp['opening_time']?.toString() ?? '05:00';
          _sellerCloseTime = resp['closing_time']?.toString() ?? '19:00';
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchReviews() async {
    final productId = widget.product['id']?.toString();
    if (productId == null || productId.isEmpty) return;
    try {
      final resp = await Supabase.instance.client
          .from('reviews')
          .select('*')
          .eq('product_id', productId)
          .order('created_at', ascending: false)
          .limit(20);
      if (mounted) {
        final list = List<Map<String, dynamic>>.from(resp);
        double total = 0;
        for (final r in list) {
          total += (r['rating'] as num?)?.toDouble() ?? 0;
        }
        setState(() {
          _reviews = list;
          _averageRating = list.isNotEmpty ? total / list.length : 0;
        });
      }
    } catch (_) {
      // reviews table may not exist yet
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
    final location = widget.product['market_location']?.toString().trim();
    if (location != null && location.isNotEmpty) {
      return location;
    }
    return 'Main Public Market';
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
    final productId = widget.product['id']?.toString();

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
          'store_name': widget.product['store_name']?.toString() ?? 'Market Stall',
          'unit_type': (widget.product['unit_type'] ?? 'kg').toString(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $_quantity $productName to cart!'),
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

  Future<void> _buyNow() async {
    final supabase = Supabase.instance.client;
    final buyerId = supabase.auth.currentUser?.id;

    if (buyerId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first.')));
      return;
    }

    try {
      final sellerId = widget.product['seller_id']?.toString();
      final total = _priceValue * _quantity;

      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final rng = Random.secure();
      final pickupCode = List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();

      final orderRes = await supabase.from('orders').insert({
        'product_name': _displayName,
        'price': _priceValue,
        'qty': _quantity,
        'buyer_id': buyerId,
        'seller_id': sellerId,
        'product_id': widget.product['id']?.toString(),
        'image_url': widget.product['image_url']?.toString(),
        'store_name': widget.product['store_name']?.toString() ?? 'Market Stall',
        'unit_type': (widget.product['unit_type'] ?? 'kg').toString(),
        'total_amount': total,
        'status': 'pending',
        'pickup_code': pickupCode,
      }).select('id').single();

      // Notify seller
      if (sellerId != null && sellerId.isNotEmpty) {
        await supabase.from('seller_notifications').insert({
          'seller_id': sellerId,
          'order_id': orderRes['id'],
          'title': 'New Order!',
          'body': '$_displayName x$_quantity — ₱${total.toStringAsFixed(0)}',
          'type': 'new_order',
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order submitted for $_quantity item(s)!')),
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

  Widget _buildDetailImage() {
    final imageUrl = (widget.product['image_url'] ?? '').toString().trim();
    if (imageUrl.isEmpty) {
      return const Center(
        child: Icon(Icons.image_outlined, size: 54, color: Color(0xFFB6BDCC)),
      );
    }
    if (imageUrl.startsWith('assets/') || imageUrl.startsWith('images/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.image_not_supported_outlined, size: 54, color: Color(0xFFB6BDCC)),
        ),
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined, size: 54, color: Color(0xFFB6BDCC)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double total = _priceValue * _quantity;
    final double regularPrice = _priceValue <= 0 ? 0.0 : _priceValue * 1.15;

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
                  Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        onPressed: () {},
                      ),
                      Positioned(
                        right: 7,
                        top: 7,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF5A524),
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            '3',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
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
                              child: _buildDetailImage(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _indicator(true),
                              _indicator(false),
                              _indicator(false),
                            ],
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
                              Text(
                                '₱${_formatPrice(_priceValue)}/$_unitType',
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: Color(0xFF1A3C8C),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Reg: ₱${_formatPrice(regularPrice)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFFA7ADBC),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: const Color(0xFFE8EEFF),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _sellerLogoUrl != null && _sellerLogoUrl!.isNotEmpty
                                    ? Image.network(_sellerLogoUrl!, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(
                                            Icons.storefront_outlined, size: 18, color: Color(0xFFB4BAC9)))
                                    : const Icon(Icons.storefront_outlined, size: 18, color: Color(0xFFB4BAC9)),
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
                                    color: Color(0xFF1A4DBE),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Shop open/closed status
                          Builder(builder: (_) {
                            bool isWithinHours = false;
                            try {
                              final now = TimeOfDay.now();
                              final op = _sellerOpenTime.split(':');
                              final cl = _sellerCloseTime.split(':');
                              final openMin = int.parse(op[0]) * 60 + int.parse(op[1]);
                              final closeMin = int.parse(cl[0]) * 60 + int.parse(cl[1]);
                              final nowMin = now.hour * 60 + now.minute;
                              isWithinHours = nowMin >= openMin && nowMin <= closeMin;
                            } catch (_) {}
                            final shopOpen = _sellerIsOpen && isWithinHours;
                            return Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: shopOpen ? const Color(0xFF059669) : const Color(0xFFDC2626),
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
                                    color: shopOpen ? const Color(0xFF059669) : const Color(0xFFDC2626),
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
                          }),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 16,
                                color: Color(0xFF9299AA),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _marketLocation,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF9299AA),
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
                                (_averageRating > 0 ? _averageRating : _rating).toStringAsFixed(1),
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
    final displayRating = _averageRating > 0 ? _averageRating : _rating;
    final displayCount = _reviews.isNotEmpty ? _reviews.length : _reviewCount;

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
              const Text('Product Reviews',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              const Spacer(),
              Row(
                children: [
                  Text('${displayRating.toStringAsFixed(1)}/5',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFF5A524))),
                  const SizedBox(width: 4),
                  Text('($displayCount)',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF8E95A6))),
                  const SizedBox(width: 4),
                  Icon(_showReviews ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: const Color(0xFF9AA1B2), size: 22),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Rating summary bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8F0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  Text(displayRating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFFF5A524))),
                  Row(
                    children: List.generate(5, (i) => Icon(
                      i < displayRating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 16, color: const Color(0xFFF5A524))),
                  ),
                  const SizedBox(height: 4),
                  Text('$displayCount ratings',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8E95A6))),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: List.generate(5, (i) {
                    final star = 5 - i;
                    final count = _reviews.where((r) => (r['rating'] as num?)?.toInt() == star).length;
                    final pct = _reviews.isNotEmpty ? count / _reviews.length : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text('$star', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                          const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF5A524)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: const Color(0xFFE5E7EB),
                                valueColor: const AlwaysStoppedAnimation(Color(0xFFF5A524)),
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 24,
                            child: Text('$count', style: const TextStyle(fontSize: 11, color: Color(0xFF8E95A6)),
                                textAlign: TextAlign.end),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        // Individual reviews
        if (_showReviews) ...[
          const SizedBox(height: 12),
          if (_reviews.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.rate_review_outlined, size: 36, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text('No reviews yet', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Be the first to review this product!',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ),
            )
          else
            ...(_reviews.take(5).map((r) {
              final name = r['reviewer_name']?.toString() ?? 'Buyer';
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
                        CircleAvatar(radius: 16,
                            backgroundColor: const Color(0xFFE8EEFF),
                            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'B',
                                style: const TextStyle(color: Color(0xFF1A4DBE),
                                    fontWeight: FontWeight.w700, fontSize: 14))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Row(
                                children: [
                                  ...List.generate(5, (i) => Icon(
                                    i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                    size: 13, color: const Color(0xFFF5A524))),
                                  const SizedBox(width: 6),
                                  Text(formattedDate,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (comment.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(comment, style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563), height: 1.4)),
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
                child: Text('See all ${_reviews.length} reviews',
                    style: const TextStyle(color: Color(0xFF1A4DBE), fontWeight: FontWeight.w600)),
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
