import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductViewPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductViewPage({super.key, required this.product});

  @override
  State<ProductViewPage> createState() => _ProductViewPageState();
}

class _ProductViewPageState extends State<ProductViewPage> {
  int _quantity = 1;
  bool _showNutrition = false;
  bool _showReviews = false;

  String get _displayName {
    return (widget.product['name'] ??
            widget.product['product_name'] ??
            'Unknown product')
        .toString();
  }

  String get _sellerName {
    final seller = widget.product['seller_name']?.toString().trim();
    if (seller != null && seller.isNotEmpty) {
      return seller;
    }
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

    try {
      await supabase.from('cart').insert({
        'product_name': _displayName,
        'price': _priceValue,
        'qty': _quantity,
        'buyer_id': user.id,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $_quantity item(s) to cart successfully!'),
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
      await supabase.from('orders').insert({
        'product_name': _displayName,
        'price': _priceValue,
        'qty': _quantity,
        'buyer_id': buyerId,
      });

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
                            width: 124,
                            height: 124,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F3F7),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE5E7F0),
                              ),
                            ),
                            child: const Icon(
                              Icons.image_outlined,
                              size: 54,
                              color: Color(0xFFB6BDCC),
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
                                '₱${_formatPrice(_priceValue)}/KG',
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
                              const Icon(
                                Icons.storefront_outlined,
                                size: 22,
                                color: Color(0xFFB4BAC9),
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
                                _rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$_reviewCount reviews',
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
                          _detailToggle(
                            title: 'Nutritional facts',
                            expanded: _showNutrition,
                            onTap: () {
                              setState(() {
                                _showNutrition = !_showNutrition;
                              });
                            },
                          ),
                          AnimatedCrossFade(
                            duration: const Duration(milliseconds: 180),
                            crossFadeState: _showNutrition
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                            firstChild: const Padding(
                              padding: EdgeInsets.fromLTRB(2, 8, 2, 10),
                              child: Text(
                                'Estimated per 100g: Protein 19g, Fat 6g, Sodium 65mg. Values vary by freshness and cut from each market stall.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF7D8596),
                                  height: 1.4,
                                ),
                              ),
                            ),
                            secondChild: const SizedBox.shrink(),
                          ),
                          const Divider(height: 4, color: Color(0xFFE3E6EF)),
                          const SizedBox(height: 8),
                          _detailToggle(
                            title: 'Reviews',
                            expanded: _showReviews,
                            onTap: () {
                              setState(() {
                                _showReviews = !_showReviews;
                              });
                            },
                          ),
                          AnimatedCrossFade(
                            duration: const Duration(milliseconds: 180),
                            crossFadeState: _showReviews
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                            firstChild: const Padding(
                              padding: EdgeInsets.fromLTRB(2, 8, 2, 0),
                              child: Text(
                                '"Fresh and clean cut, seller was responsive and packed well for transport."',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF7D8596),
                                  height: 1.4,
                                ),
                              ),
                            ),
                            secondChild: const SizedBox.shrink(),
                          ),
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

  Widget _detailToggle({
    required String title,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: Color(0xFF303746),
              ),
            ),
            const Spacer(),
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: const Color(0xFF9AA1B2),
            ),
          ],
        ),
      ),
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
