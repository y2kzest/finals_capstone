import 'package:flutter/material.dart';
import 'product_variants.dart';

const Color _kPrimary = Color(0xFF1A3C8C);

/// Result returned when the user confirms from the product options sheet.
class ProductOptionsResult {
  final ProductVariant? selectedVariant;

  /// The price to charge — variant price if one was selected, base price otherwise.
  final double effectivePrice;

  final double qty;

  /// Optional note the buyer typed (e.g. "cut into pieces, no fat").
  final String? note;

  /// Which button the user tapped: 'add_to_cart' or 'buy_now'.
  final String action;

  const ProductOptionsResult({
    this.selectedVariant,
    required this.effectivePrice,
    required this.qty,
    this.note,
    required this.action,
  });
}

/// Shows the Shopee-style product-options bottom sheet and returns the result,
/// or null if the user dismisses without confirming.
///
/// [showAddToCart] and [showBuyNow] control which action buttons appear.
Future<ProductOptionsResult?> showProductOptionsSheet({
  required BuildContext context,
  required Map<String, dynamic> product,
  bool showAddToCart = true,
  bool showBuyNow = true,
}) {
  return showModalBottomSheet<ProductOptionsResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProductOptionsSheet(
      product: product,
      showAddToCart: showAddToCart,
      showBuyNow: showBuyNow,
    ),
  );
}

// ---------------------------------------------------------------------------

class _ProductOptionsSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final bool showAddToCart;
  final bool showBuyNow;

  const _ProductOptionsSheet({
    required this.product,
    required this.showAddToCart,
    required this.showBuyNow,
  });

  @override
  State<_ProductOptionsSheet> createState() => _ProductOptionsSheetState();
}

class _ProductOptionsSheetState extends State<_ProductOptionsSheet> {
  List<ProductVariant> _variants = [];
  ProductVariant? _selectedVariant;
  double _qty = 1.0;
  final _noteCtrl = TextEditingController();

  // ── price helpers ─────────────────────────────────────────────────────────

  double get _basePrice {
    final v = widget.product['price'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  double get _displayPrice => _selectedVariant?.price ?? _basePrice;

  // ── unit / qty helpers ────────────────────────────────────────────────────
  //
  // Quantities are whole-number only. Partial weights (e.g. "Half kg") must
  // be modeled as seller-defined variants with their own price — this keeps
  // the cart math unambiguous and matches how ecommerce stores actually sell.

  String get _unitType {
    final u = widget.product['unit_type']?.toString().trim() ?? '';
    return u.isNotEmpty ? u : 'kg';
  }

  static const double _qtyStep = 1.0;
  static const double _qtyMin = 1.0;

  String _fmtQty(double v) => v.toStringAsFixed(0);

  String _fmtPrice(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _variants = parseVariants(widget.product['variants']?.toString());
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  // ── confirm ───────────────────────────────────────────────────────────────

  void _confirm(String action) {
    Navigator.of(context).pop(ProductOptionsResult(
      selectedVariant: _selectedVariant,
      effectivePrice: _displayPrice,
      qty: _qty,
      note: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
      action: action,
    ));
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
              const SizedBox(height: 14),
              _buildProductRow(),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              if (_variants.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildVariantSection(),
              ],
              const SizedBox(height: 14),
              _buildQtyStepper(),
              const SizedBox(height: 14),
              _buildNotesField(),
              const SizedBox(height: 20),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  // ── sub-widgets ───────────────────────────────────────────────────────────

  Widget _buildProductRow() {
    final imgUrl = widget.product['image_url']?.toString() ?? '';
    final name = (widget.product['name'] ?? widget.product['product_name'] ?? 'Product')
        .toString();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 80,
            height: 80,
            child: imgUrl.isNotEmpty
                ? Image.network(
                    imgUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholder(),
                  )
                : _placeholder(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '₱${_fmtPrice(_displayPrice)} / $_unitType',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _kPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFFF1F3F9),
        child: const Icon(Icons.image_outlined, color: Color(0xFFB6BDCC), size: 28),
      );

  Widget _buildVariantSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose Option',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _variants.map((v) {
            final selected = _selectedVariant?.name == v.name;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedVariant = selected ? null : v;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? _kPrimary : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? _kPrimary : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      v.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : const Color(0xFF374151),
                      ),
                    ),
                    if (v.price != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '₱${_fmtPrice(v.price!)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white70 : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
      ],
    );
  }

  Widget _buildQtyStepper() {
    final total = _displayPrice * _qty;
    return Row(
      children: [
        const Text(
          'Quantity',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF1F4FC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _qtyBtn(Icons.remove, () {
                if (_qty <= _qtyMin) return;
                setState(() => _qty -= _qtyStep);
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  _fmtQty(_qty),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              _qtyBtn(Icons.add, () => setState(() => _qty += _qtyStep)),
            ],
          ),
        ),
        const Spacer(),
        Text(
          'Total: ₱${_fmtPrice(total)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _kPrimary,
          ),
        ),
      ],
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 18, color: _kPrimary),
        ),
      );

  Widget _buildNotesField() {
    return TextField(
      controller: _noteCtrl,
      maxLength: 120,
      maxLines: 1,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'Add a note (e.g. cut into pieces, no fat…)',
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFB0B8C4)),
        filled: true,
        fillColor: const Color(0xFFF8FAFF),
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPrimary),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    final addToCartBtn = OutlinedButton(
      onPressed: () => _confirm('add_to_cart'),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: _kPrimary),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      child: const Text(
        'Add to Cart',
        style: TextStyle(color: _kPrimary, fontWeight: FontWeight.w700),
      ),
    );

    final buyNowBtn = ElevatedButton(
      onPressed: () => _confirm('buy_now'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      child: const Text(
        'Buy Now',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );

    if (widget.showAddToCart && widget.showBuyNow) {
      return Row(
        children: [
          Expanded(child: addToCartBtn),
          const SizedBox(width: 10),
          Expanded(child: buyNowBtn),
        ],
      );
    }
    if (widget.showBuyNow) {
      return SizedBox(width: double.infinity, child: buyNowBtn);
    }
    return SizedBox(width: double.infinity, child: addToCartBtn);
  }
}
