import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'product_variants.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kDanger = Color(0xFFDC2626);
const Color _kSuccess = Color(0xFF059669);

/// A form section that lets a seller define product variants — each with its
/// own price. The seller is the one who controls these prices; buyers can
/// only pick from the options the seller publishes.
///
/// Typical use: a 600₱/kg item with variants "Half kg → ₱300", "1 kg → ₱600",
/// "2 kg → ₱1200". Buyers tap a pill and the variant's price is what hits
/// the cart — no fractional-quantity math, no ambiguity.
class VariantBuilderField extends StatefulWidget {
  final List<ProductVariant> initialVariants;
  final ValueChanged<List<ProductVariant>> onChanged;

  /// Optional: fires `true` whenever any row has a name but no valid price.
  /// Parent forms can use this to disable their Publish button.
  final ValueChanged<bool>? onValidationChanged;

  const VariantBuilderField({
    super.key,
    required this.initialVariants,
    required this.onChanged,
    this.onValidationChanged,
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

  bool get isBlank =>
      nameCtrl.text.trim().isEmpty && priceCtrl.text.trim().isEmpty;

  bool get hasName => nameCtrl.text.trim().isNotEmpty;

  double? get parsedPrice => double.tryParse(priceCtrl.text.trim());

  /// A row is invalid when the seller typed a name but the price is missing
  /// or non-positive. Blank rows are skipped entirely (not invalid).
  bool get isInvalid => hasName && (parsedPrice == null || parsedPrice! <= 0);

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

class _VariantBuilderFieldState extends State<VariantBuilderField> {
  late final List<_VariantRow> _rows;
  bool _lastEmittedInvalid = false;

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
    row.nameCtrl.addListener(_onAnyFieldChanged);
    row.priceCtrl.addListener(_onAnyFieldChanged);
  }

  void _onAnyFieldChanged() {
    // Trigger a rebuild so the per-row error state updates live, then notify
    // the parent with only the rows that have BOTH a name AND a valid price.
    if (mounted) setState(() {});
    _notify();
  }

  void _notify() {
    widget.onChanged(
      _rows
          .where((r) => r.hasName && !r.isInvalid)
          .map((r) => ProductVariant(name: r.nameCtrl.text.trim(), price: r.parsedPrice))
          .toList(),
    );
    final hasInvalid = _rows.any((r) => r.isInvalid);
    if (hasInvalid != _lastEmittedInvalid) {
      _lastEmittedInvalid = hasInvalid;
      widget.onValidationChanged?.call(hasInvalid);
    }
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

  // ── Derived state ───────────────────────────────────────────────────────────

  int get _validCount =>
      _rows.where((r) => r.hasName && !r.isInvalid).length;

  int get _invalidCount => _rows.where((r) => r.isInvalid).length;

  String? get _priceRangeSummary {
    final prices = _rows
        .where((r) => r.hasName && !r.isInvalid)
        .map((r) => r.parsedPrice!)
        .toList();
    if (prices.isEmpty) return null;
    prices.sort();
    if (prices.first == prices.last) return '₱${prices.first.toStringAsFixed(0)}';
    return '₱${prices.first.toStringAsFixed(0)} – ₱${prices.last.toStringAsFixed(0)}';
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
            const Spacer(),
            if (_validCount > 0) _summaryPill(),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Sell the same product at different sizes or weights. Example: '
          '"Half kg → ₱300", "1 kg → ₱600". Buyers can only pick what you publish.',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),

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
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    const Text(
                      'Price ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    Text(
                      '*',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kDanger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Rows
        ...List.generate(_rows.length, (i) {
          final row = _rows[i];
          final hasError = row.isInvalid;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _field(
                        ctrl: row.nameCtrl,
                        hint: 'e.g. Half kg / Small / With rice',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _field(
                        ctrl: row.priceCtrl,
                        hint: 'Required',
                        prefix: '₱',
                        isNumber: true,
                        errored: hasError,
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
                if (hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Row(
                      children: const [
                        Icon(Icons.error_outline_rounded,
                            size: 12, color: _kDanger),
                        SizedBox(width: 4),
                        Text(
                          'Enter a price greater than 0 for this option.',
                          style: TextStyle(
                            fontSize: 11,
                            color: _kDanger,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }),

        // Add option button
        Row(
          children: [
            TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add_rounded, size: 16, color: _kPrimary),
              label: const Text(
                'Add option',
                style: TextStyle(
                  fontSize: 13,
                  color: _kPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const Spacer(),
            if (_invalidCount > 0)
              Text(
                '$_invalidCount option${_invalidCount == 1 ? '' : 's'} missing a price',
                style: const TextStyle(
                  fontSize: 11,
                  color: _kDanger,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Sub-widgets ─────────────────────────────────────────────────────────────

  Widget _summaryPill() {
    final summary = _priceRangeSummary ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kSuccess.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kSuccess.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 12, color: _kSuccess),
          const SizedBox(width: 4),
          Text(
            '$_validCount option${_validCount == 1 ? '' : 's'} · $summary',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _kSuccess,
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    String? prefix,
    bool isNumber = false,
    bool errored = false,
  }) {
    final borderColor = errored ? _kDanger : const Color(0xFFE5E7EB);
    final focusedColor = errored ? _kDanger : _kPrimary;
    return TextField(
      controller: ctrl,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 11,
          color: errored ? _kDanger.withValues(alpha: 0.7) : Colors.grey.shade400,
        ),
        prefixText: prefix,
        prefixStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: errored ? _kDanger : const Color(0xFF374151),
        ),
        filled: true,
        fillColor: errored
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFF9FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: focusedColor, width: 1.4),
        ),
      ),
    );
  }
}
