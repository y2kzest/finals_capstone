import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/product_variants.dart';
import '../utils/variant_builder.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);

class EditProductPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const EditProductPage({super.key, required this.product});

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final supabase = Supabase.instance.client;

  late final TextEditingController nameCtrl;
  late final TextEditingController priceCtrl;
  late final TextEditingController retailPriceCtrl;
  late final TextEditingController stockCtrl;
  late final TextEditingController descriptionCtrl;
  List<ProductVariant> _variants = [];
  bool _variantsHaveErrors = false;
  late final TextEditingController prepTimeCtrl;

  late String selectedCategory;
  late String selectedUnit;
  late String selectedPricingBasis;
  bool dailyAvailable = true;

  static const List<String> categories = [
    'Fish', 'Meat', 'Vegetable', 'Fruit', 'Service', 'Apparel', 'Karinderya'
  ];
  static const List<String> unitTypes = [
    'Kg', 'pcs', 'g', 'serving', 'order', 'plate'
  ];
  static const List<String> _pricingBases = [
    'per serving', 'per order', 'per kilo', 'per piece'
  ];

  // Existing images loaded from DB (URLs)
  List<String> _existingImages = [];
  // Newly picked local images (not yet uploaded)
  final List<XFile> _newFiles = [];
  final List<Uint8List> _newBytes = [];
  bool _isSaving = false;
  static const int _maxImages = 5;

  int? _parseWholeNumber(String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null) return null;
    if (value != value.truncateToDouble()) return null;
    return value.toInt();
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    nameCtrl = TextEditingController(
        text: p['name']?.toString() ?? p['product_name']?.toString() ?? '');
    priceCtrl = TextEditingController(
        text: (p['price'] as num?)?.toString() ?? '');
    retailPriceCtrl = TextEditingController(
        text: (p['retail_price'] as num?)?.toString() ?? '');
    stockCtrl = TextEditingController(
        text: (p['stock_quantity'] as num?)?.toString() ?? '');
    descriptionCtrl = TextEditingController(
        text: p['description']?.toString() ?? '');
    _variants = parseVariants(p['variants']?.toString());
    prepTimeCtrl = TextEditingController(
      text: p['prep_time']?.toString() ?? '');

    final rawCat = p['category']?.toString();
    final productType = p['product_type']?.toString();
    selectedCategory = (rawCat != null && categories.contains(rawCat))
      ? rawCat
      : (productType == 'karinderya' ? 'Karinderya' : 'Fish');

    final rawPricing = p['pricing_basis']?.toString() ?? _pricingBases.first;
    selectedPricingBasis = _pricingBases.contains(rawPricing)
      ? rawPricing
      : _pricingBases.first;
    dailyAvailable = p['daily_available'] == null
      ? true
      : p['daily_available'] == true;

    final rawUnit = p['unit_type']?.toString() ?? '';
    final fallbackUnit = selectedCategory == 'Karinderya'
      ? 'serving'
      : selectedCategory == 'Apparel'
        ? 'pcs'
        : 'Kg';
    selectedUnit = unitTypes.contains(rawUnit) ? rawUnit : fallbackUnit;

    // Load existing images — prefer image_urls array, fallback to image_url
    final rawUrls = p['image_urls'];
    if (rawUrls is List && rawUrls.isNotEmpty) {
      _existingImages = rawUrls
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      final single = p['image_url']?.toString().trim() ?? '';
      if (single.isNotEmpty) _existingImages = [single];
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    retailPriceCtrl.dispose();
    stockCtrl.dispose();
    descriptionCtrl.dispose();
    prepTimeCtrl.dispose();
    super.dispose();
  }

  int get _totalImages => _existingImages.length + _newFiles.length;

  Future<void> pickImages() async {
    final remaining = _maxImages - _totalImages;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    final toAdd = files.take(remaining).toList();
    for (final f in toAdd) {
      final bytes = await f.readAsBytes();
      _newFiles.add(f);
      _newBytes.add(bytes);
    }
    setState(() {});
  }

  Future<List<String>> _uploadNewImages() async {
    final urls = <String>[];
    for (int i = 0; i < _newFiles.length; i++) {
      try {
        final ext = _newFiles[i].name.split('.').last.toLowerCase();
        final fileName =
            'product_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        await supabase.storage.from('products').uploadBinary(
          fileName,
          _newBytes[i],
          fileOptions: FileOptions(contentType: 'image/$ext'),
        );
        urls.add(supabase.storage.from('products').getPublicUrl(fileName));
      } catch (e) {
        debugPrint('UPLOAD ERROR [$i] → $e');
      }
    }
    return urls;
  }

  Future<void> _saveChanges() async {
    final isApparel = selectedCategory == 'Apparel';
    final isKarinderya = selectedCategory == 'Karinderya';
    if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields.')),
      );
      return;
    }

    if (_variantsHaveErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Each variant needs a price. Fix or remove incomplete options before saving.',
          ),
        ),
      );
      return;
    }

    final priceValue = _parseWholeNumber(priceCtrl.text);
    if (priceValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Price must be a whole number.')),
      );
      return;
    }

    final retailPriceValue = (isApparel || isKarinderya)
        ? 0
        : (retailPriceCtrl.text.trim().isEmpty
            ? 0
            : _parseWholeNumber(retailPriceCtrl.text));
    if (!isApparel && !isKarinderya && retailPriceValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retail price must be a whole number.')),
      );
      return;
    }

    // Retail price must be higher than selling price when provided
    if (!isApparel && !isKarinderya) {
      final price = priceValue;
      final retailPrice = retailPriceValue ?? 0;
      if (retailPrice > 0 && retailPrice <= price) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Retail price must be higher than the selling price, or leave it blank.'),
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    // Upload any newly picked images
    List<String> newUrls = [];
    if (_newFiles.isNotEmpty) {
      newUrls = await _uploadNewImages();
    }

    // Merge: existing (retained) + newly uploaded
    final allImages = [..._existingImages, ...newUrls];

    final productId = widget.product['id']?.toString();
    if (productId == null) {
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    final updates = {
      'name': nameCtrl.text.trim(),
      'category': selectedCategory,
      'price': priceValue,
      'retail_price': (isApparel || isKarinderya) ? 0 : (retailPriceValue ?? 0),
      'stock_quantity': (isApparel || isKarinderya)
          ? 0
          : (double.tryParse(stockCtrl.text)?.toInt() ?? 0),
      'unit_type': isApparel ? 'pcs' : selectedUnit,
      'description': descriptionCtrl.text.trim(),
      'image_url': allImages.isNotEmpty ? allImages.first : null,
      'image_urls': allImages,
      'product_type': isKarinderya ? 'karinderya' : 'retail',
      if (isKarinderya) 'pricing_basis': selectedPricingBasis,
      'variants': _variants.isNotEmpty ? encodeVariants(_variants) : null,
      if (isKarinderya && prepTimeCtrl.text.trim().isNotEmpty)
        'prep_time': prepTimeCtrl.text.trim(),
      if (isKarinderya) 'daily_available': dailyAvailable,
    };

    try {
      await supabase.from('product').update(updates).eq('id', productId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product updated successfully!'),
          backgroundColor: _kPrimary,
        ),
      );
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      // If image_urls column doesn't exist yet, retry without it
      if (e.message.contains('image_urls')) {
        try {
          final fallback = Map<String, dynamic>.from(updates)
            ..remove('image_urls');
          await supabase.from('product').update(fallback).eq('id', productId);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Updated! Run DB migration to enable multi-image.'),
              backgroundColor: _kPrimary,
            ),
          );
          Navigator.pop(context, true);
        } catch (e2) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e2')));
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isApparel = selectedCategory == 'Apparel';
    final isKarinderya = selectedCategory == 'Karinderya';
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _circleButton(
                      Icons.arrow_back_ios_new, () => Navigator.pop(context)),
                  const Expanded(
                    child: Text('Edit Product',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 42),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Multi-image picker ──
                    _buildImagePicker(),
                    const SizedBox(height: 20),

                    _sectionTitle('Product Information'),
                    const SizedBox(height: 12),
                    _modernField(
                        label: 'Product Name',
                        controller: nameCtrl,
                        icon: Icons.shopping_bag_outlined),
                    const SizedBox(height: 14),
                    _modernDropdown<String>(
                      label: 'Category',
                      icon: Icons.category_outlined,
                      value: selectedCategory,
                      items: categories,
                      onChanged: (v) => setState(() {
                        selectedCategory = v!;
                        if (v == 'Karinderya') {
                          selectedUnit = 'serving';
                        } else if (v == 'Apparel') {
                          selectedUnit = 'pcs';
                        }
                      }),
                    ),
                    const SizedBox(height: 14),
                    _modernField(
                        label: 'Description',
                        controller: descriptionCtrl,
                        icon: Icons.notes_rounded,
                        maxLines: 3),
                    const SizedBox(height: 24),

                    _sectionTitle(
                        isApparel
                            ? 'Pricing'
                            : isKarinderya
                                ? 'Karinderya Pricing & Details'
                                : 'Pricing & Stock'),
                    const SizedBox(height: 12),
                    if (isKarinderya) ...[
                      _modernDropdown<String>(
                        label: 'Pricing Basis',
                        icon: Icons.price_change_outlined,
                        value: selectedPricingBasis,
                        items: _pricingBases,
                        onChanged: (v) =>
                            setState(() => selectedPricingBasis = v!),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                            child: _modernField(
                                label: 'Price',
                                controller: priceCtrl,
                                icon: Icons.payments_outlined,
                            prefix: '₱',
                                isNumber: true)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _modernDropdown<String>(
                          label: 'Unit',
                          icon: Icons.straighten_outlined,
                          value: selectedUnit,
                          items: unitTypes,
                          onChanged: (v) =>
                              setState(() => selectedUnit = v!),
                        )),
                      ]),
                      const SizedBox(height: 14),
                      _modernField(
                        label: 'Prep / Pickup Readiness (e.g. 10-15 mins)',
                        controller: prepTimeCtrl,
                        icon: Icons.schedule_rounded,
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: Row(children: [
                          const Icon(Icons.today_rounded, size: 20, color: _kPrimary),
                          const SizedBox(width: 12),
                          const Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Available today',
                                  style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w600)),
                              Text(
                                  "Toggle off if today's menu is not ready",
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF9CA3AF))),
                            ],
                          )),
                          Switch(
                            value: dailyAvailable,
                            onChanged: (v) => setState(() => dailyAvailable = v),
                            activeThumbColor: _kPrimary,
                          ),
                        ]),
                      ),
                    ] else if (isApparel) ...[
                      _modernField(
                          label: 'Price',
                          controller: priceCtrl,
                          icon: Icons.payments_outlined,
                          prefix: '₱',
                          isNumber: true),
                    ] else ...[
                      Row(children: [
                        Expanded(
                            child: _modernField(
                                label: 'Price',
                                controller: priceCtrl,
                                icon: Icons.payments_outlined,
                            prefix: '₱',
                                isNumber: true)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _modernField(
                                label: 'Retail Price',
                                controller: retailPriceCtrl,
                                icon: Icons.sell_outlined,
                            prefix: '₱',
                                isNumber: true)),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                            child: _modernField(
                                label: 'Stock Qty',
                                controller: stockCtrl,
                                icon: Icons.inventory_outlined,
                                isNumber: true)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _modernDropdown<String>(
                          label: 'Unit',
                          icon: Icons.straighten_outlined,
                          value: selectedUnit,
                          items: unitTypes,
                          onChanged: (v) =>
                              setState(() => selectedUnit = v!),
                        )),
                      ]),
                    ],
                    const SizedBox(height: 20),
                    VariantBuilderField(
                      initialVariants: _variants,
                      onChanged: (v) => setState(() => _variants = v),
                      onValidationChanged: (hasErrors) =>
                          setState(() => _variantsHaveErrors = hasErrors),
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: (_isSaving || _variantsHaveErrors) ? null : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              _kPrimary.withValues(alpha: 0.5),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white))
                            : const Text('Save Changes',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    final hasImages = _totalImages > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionTitle('Product Photos'),
            Text(
              '$_totalImages/$_maxImages',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Existing images from DB
              for (int i = 0; i < _existingImages.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          _existingImages[i],
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 100,
                            height: 100,
                            color: const Color(0xFFEEF1F8),
                            child: const Icon(Icons.broken_image_outlined,
                                color: Color(0xFFB6BDCC)),
                          ),
                        ),
                      ),
                      if (i == 0)
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kPrimary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Cover',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _existingImages.removeAt(i)),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDC2626),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded,
                                size: 13, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Newly picked images
              for (int i = 0; i < _newBytes.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _newBytes[i],
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _newFiles.removeAt(i);
                              _newBytes.removeAt(i);
                            });
                          },
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDC2626),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded,
                                size: 13, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Add more button
              if (_totalImages < _maxImages)
                GestureDetector(
                  onTap: pickImages,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasImages
                            ? _kPrimary.withValues(alpha: 0.4)
                            : Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          hasImages
                              ? Icons.add_photo_alternate_outlined
                              : Icons.add_a_photo_rounded,
                          color: hasImages ? _kPrimary : Colors.grey,
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          hasImages ? 'Add more' : 'Add photos',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasImages
                                ? _kPrimary
                                : Colors.grey.shade500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'First photo is the cover. Up to 5 photos.',
          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
        ),
      ],
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF374151)),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827)));
  }

  Widget _modernField({
    required String label,
    required TextEditingController controller,
    IconData? icon,
    String? prefix,
    bool isNumber = false,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType:
            isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          prefixIcon: icon != null
              ? Icon(icon, size: 20, color: _kPrimary)
              : null,
          prefixText: prefix,
          prefixStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151)),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: _kPrimary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _modernDropdown<T>({
    required String label,
    required IconData icon,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        items: items
            .map((e) =>
                DropdownMenuItem(value: e, child: Text(e.toString())))
            .toList(),
        onChanged: onChanged,
        icon: const Icon(Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF9CA3AF)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          prefixIcon: Icon(icon, size: 20, color: _kPrimary),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: _kPrimary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
