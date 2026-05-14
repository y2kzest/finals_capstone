import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'product_variants.dart';

const Color _kPrimary = Color(0xFF2A4BA0);

/// A form section that lets a seller define product variants with optional
/// per-variant prices (e.g. "Small – ₱50", "Large – ₱90").
///
/// Drop this widget anywhere inside a seller's product form. It manages its
/// own text controllers and calls [onChanged] whenever the list changes.
class VariantBuilderField extends StatefulWidget {
  final List<ProductVariant> initialVariants;
  final ValueChanged<List<ProductVariant>> onChanged;

  const VariantBuilderField({
    super.key,
    required this.initialVariants,
    required this.onChanged,
  });

  @override
  State<VariantBuilderField> createState() => _VariantBuilderFieldState();
}

// ── Internal row model ────────────────────────────────────────────────────────

class _VariantRow {
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;

  _VariantRow({String name = '', String price = ''})
      : nameCtrl = TextEditingController(text: name),
        priceCtrl = TextEditingController(text: price);

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

class _VariantBuilderFieldState extends State<VariantBuilderField> {
  late final List<_VariantRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.initialVariants.map((v) {
      return _VariantRow(
        name: v.name,
        price: v.price != null ? v.price!.toStringAsFixed(0) : '',
      );
    }).toList();
    // Always show at least one blank row so sellers know they can add options.
    if (_rows.isEmpty) _rows.add(_VariantRow());
    for (final r in _rows) {
      _attach(r);
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _attach(_VariantRow row) {
    row.nameCtrl.addListener(_notify);
    row.priceCtrl.addListener(_notify);
  }

  void _notify() {
    widget.onChanged(
      _rows
          .where((r) => r.nameCtrl.text.trim().isNotEmpty)
          .map((r) {
            final price = double.tryParse(r.priceCtrl.text.trim());
            return ProductVariant(name: r.nameCtrl.text.trim(), price: price);
          })
          .toList(),
    );
  }

  void _addRow() {
    setState(() {
      final r = _VariantRow();
      _attach(r);
      _rows.add(r);
    });
  }

  void _removeRow(int i) {
    setState(() {
      _rows[i].dispose();
      _rows.removeAt(i);
      if (_rows.isEmpty) {
        final r = _VariantRow();
        _attach(r);
        _rows.add(r);
      }
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.tune_rounded, size: 18, color: _kPrimary),
            const SizedBox(width: 8),
            const Text(
              'Variants / Options',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '(optional)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Add options like size, cut, or flavor — set a price or leave blank to use the base price.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 10),
        // Column headers
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 40),
          child: Row(
            children: [
              const Expanded(
                flex: 5,
                child: Text(
                  'Option name',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  'Price (₱)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Rows
        ...List.generate(_rows.length, (i) {
          final row = _rows[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: _field(
                    ctrl: row.nameCtrl,
                    hint: 'e.g. Small / With rice',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _field(
                    ctrl: row.priceCtrl,
                    hint: 'Base price',
                    prefix: '₱',
                    isNumber: true,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                  onPressed: () => _removeRow(i),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          );
        }),
        // Add option button
        TextButton.icon(
          onPressed: _addRow,
          icon: const Icon(Icons.add, size: 16, color: _kPrimary),
          label: const Text(
            'Add option',
            style: TextStyle(fontSize: 13, color: _kPrimary),
          ),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    String? prefix,
    bool isNumber = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(fontSize: 11, color: Colors.grey.shade400),
        prefixText: prefix,
        prefixStyle: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kPrimary),
        ),
      ),
    );
  }
}
