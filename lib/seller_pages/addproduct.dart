import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final supabase = Supabase.instance.client;

  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController retailPriceCtrl = TextEditingController();
  final TextEditingController stockCtrl = TextEditingController();
  final TextEditingController descriptionCtrl = TextEditingController();
  final TextEditingController variantsCtrl = TextEditingController();
  final TextEditingController prepTimeCtrl = TextEditingController();

  String selectedCategory = "Fish";
  String selectedUnit = "Kg";
  String selectedPricingBasis = 'per serving';
  bool dailyAvailable = true;

  List<String> categories = ["Fish", "Meat", "Vegetable", "Fruit", "Apparel", "Karinderya"];
  List<String> unitTypes = ["Kg", "pcs", "g", "serving", "order", "plate"];
  static const List<String> _pricingBases = [
    'per serving', 'per order', 'per kilo', 'per piece'
  ];

  final List<XFile> _pickedFiles = [];
  final List<Uint8List> _pickedBytes = [];
  bool _isSaving = false;
  static const int _maxImages = 5;

  Future<void> pickImages() async {
    final picker = ImagePicker();
    final remaining = _maxImages - _pickedFiles.length;
    if (remaining <= 0) return;
    final files = await picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    final toAdd = files.take(remaining).toList();
    for (final f in toAdd) {
      final bytes = await f.readAsBytes();
      _pickedFiles.add(f);
      _pickedBytes.add(bytes);
    }
    setState(() {});
  }

  Future<List<String>> uploadImages() async {
    final urls = <String>[];
    for (int i = 0; i < _pickedFiles.length; i++) {
      try {
        final ext = _pickedFiles[i].name.split('.').last.toLowerCase();
        final fileName = 'product_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        await supabase.storage.from('products').uploadBinary(
          fileName,
          _pickedBytes[i],
          fileOptions: FileOptions(contentType: 'image/$ext'),
        );
        urls.add(supabase.storage.from('products').getPublicUrl(fileName));
      } catch (e) {
        debugPrint('UPLOAD ERROR [$i] → $e');
      }
    }
    return urls;
  }

  Future<void> saveProduct() async {
    final isApparel = selectedCategory == 'Apparel';
    final isKarinderya = selectedCategory == 'Karinderya';
    if (nameCtrl.text.isEmpty ||
        priceCtrl.text.isEmpty ||
        (!isApparel && !isKarinderya && retailPriceCtrl.text.isEmpty) ||
        (!isApparel && !isKarinderya && stockCtrl.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields.")),
      );
      return;
    }

    // Retail price must be higher than selling price when provided
    if (!isApparel && !isKarinderya) {
      final price = double.tryParse(priceCtrl.text) ?? 0;
      final retailPrice = double.tryParse(retailPriceCtrl.text) ?? 0;
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

    List<String> imageUrls = [];
    if (_pickedFiles.isNotEmpty) {
      imageUrls = await uploadImages();
      if (imageUrls.isEmpty) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload images.')),
        );
        return;
      }
    }

    final userId = supabase.auth.currentUser?.id;
    final productData = {
      'user_id': userId,
      'seller_id': userId,
      'name': nameCtrl.text,
      'category': selectedCategory,
      'price': double.parse(priceCtrl.text),
      'retail_price': (isApparel || isKarinderya) ? 0.0 : double.parse(retailPriceCtrl.text),
      'stock_quantity': (isApparel || isKarinderya) ? 0 : int.parse(stockCtrl.text),
      'unit_type': (isApparel) ? 'pcs' : selectedUnit,
      'description': descriptionCtrl.text,
      'image_url': imageUrls.isNotEmpty ? imageUrls.first : null,
      'image_urls': imageUrls,
      "product_type": isKarinderya ? 'karinderya' : 'retail',
      if (isKarinderya) "pricing_basis": selectedPricingBasis,
      if (isKarinderya && variantsCtrl.text.trim().isNotEmpty)
        "variants": variantsCtrl.text.trim(),
      if (isKarinderya && prepTimeCtrl.text.trim().isNotEmpty)
        "prep_time": prepTimeCtrl.text.trim(),
      if (isKarinderya) 'daily_available': dailyAvailable,
    };

    try {
      await supabase.from('product').insert(productData);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Product added successfully!")),
      );
      Navigator.pop(context);
    } on PostgrestException catch (e) {
      // If image_urls column doesn't exist yet, retry without it
      if (e.message.contains('image_urls')) {
        try {
          final fallback = Map<String, dynamic>.from(productData)
            ..remove('image_urls');
          await supabase.from('product').insert(fallback);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Product added! Run DB migration to enable multi-image.")),
          );
          Navigator.pop(context);
        } catch (e2) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e2")),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.message}")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _circleButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
                  const Expanded(
                    child: Text('Add Product',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
                    _modernField(label: 'Product Name', controller: nameCtrl,
                        icon: Icons.shopping_bag_outlined),
                    const SizedBox(height: 14),
                    _modernDropdown<String>(
                      label: 'Category', icon: Icons.category_outlined,
                      value: selectedCategory, items: categories,
                      onChanged: (v) => setState(() {
                        selectedCategory = v!;
                        if (v == 'Karinderya') selectedUnit = 'serving';
                      }),
                    ),
                    const SizedBox(height: 14),
                    _modernField(label: 'Description / Inclusions', controller: descriptionCtrl,
                        icon: Icons.notes_rounded, maxLines: 3),
                    const SizedBox(height: 24),

                    _sectionTitle(selectedCategory == 'Apparel'
                        ? 'Pricing'
                        : selectedCategory == 'Karinderya'
                            ? 'Karinderya Pricing & Details'
                            : 'Pricing & Stock'),
                    const SizedBox(height: 12),
                    if (selectedCategory == 'Karinderya') ...[
                      // Pricing basis
                      _modernDropdown<String>(
                        label: 'Pricing Basis', icon: Icons.price_change_outlined,
                        value: selectedPricingBasis,
                        items: _pricingBases,
                        onChanged: (v) => setState(() => selectedPricingBasis = v!),
                      ),
                      const SizedBox(height: 14),
                      // Price + unit
                      Row(children: [
                        Expanded(child: _modernField(label: 'Price', controller: priceCtrl,
                            icon: Icons.payments_outlined, prefix: '₱', isNumber: true)),
                        const SizedBox(width: 12),
                        Expanded(child: _modernDropdown<String>(
                          label: 'Unit', icon: Icons.straighten_outlined,
                          value: selectedUnit,
                          items: unitTypes,
                          onChanged: (v) => setState(() => selectedUnit = v!),
                        )),
                      ]),
                      const SizedBox(height: 14),
                      // Prep time
                      _modernField(
                        label: 'Prep / Pickup Readiness (e.g. 10–15 mins)',
                        controller: prepTimeCtrl,
                        icon: Icons.schedule_rounded,
                      ),
                      const SizedBox(height: 14),
                      // Variants
                      _modernField(
                        label: 'Variants (optional, e.g. With rice / Without rice)',
                        controller: variantsCtrl,
                        icon: Icons.tune_rounded,
                      ),
                      const SizedBox(height: 14),
                      // Daily availability toggle
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Row(children: [
                          const Icon(Icons.today_rounded, size: 20, color: _kPrimary),
                          const SizedBox(width: 12),
                          const Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Available today', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              Text('Toggle off if today\'s menu is not ready', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                            ],
                          )),
                          Switch(
                            value: dailyAvailable,
                            onChanged: (v) => setState(() => dailyAvailable = v),
                            activeColor: _kPrimary,
                          ),
                        ]),
                      ),
                    ] else if (selectedCategory == 'Apparel') ...[
                      _modernField(label: 'Price', controller: priceCtrl,
                          icon: Icons.payments_outlined, prefix: '₱', isNumber: true),
                    ] else ...[
                      Row(children: [
                        Expanded(child: _modernField(label: 'Price', controller: priceCtrl,
                            icon: Icons.payments_outlined, prefix: '₱', isNumber: true)),
                        const SizedBox(width: 12),
                        Expanded(child: _modernField(label: 'Retail Price', controller: retailPriceCtrl,
                            icon: Icons.sell_outlined, prefix: '₱', isNumber: true)),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: _modernField(label: 'Stock Qty', controller: stockCtrl,
                            icon: Icons.inventory_outlined, isNumber: true)),
                        const SizedBox(width: 12),
                        Expanded(child: _modernDropdown<String>(
                          label: 'Unit', icon: Icons.straighten_outlined,
                          value: selectedUnit, items: unitTypes,
                          onChanged: (v) => setState(() => selectedUnit = v!),
                        )),
                      ]),
                    ],
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity, height: 54,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : saveProduct,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _kPrimary.withValues(alpha: 0.5),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isSaving
                            ? const SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : const Text('Publish Product',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
    final hasImages = _pickedBytes.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionTitle('Product Photos'),
            Text(
              '${_pickedFiles.length}/$_maxImages',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Thumbnail strip + add button
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Existing thumbnails
              for (int i = 0; i < _pickedBytes.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _pickedBytes[i],
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      // First image badge
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
                      // Remove button
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _pickedFiles.removeAt(i);
                              _pickedBytes.removeAt(i);
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
              if (_pickedFiles.length < _maxImages)
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
        Text(
          'First photo is the cover. Up to $_maxImages photos.',
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
        ),
      ],
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF374151)),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)));
  }

  Widget _modernField({
    required String label, required TextEditingController controller,
    IconData? icon, String? prefix, bool isNumber = false, int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          prefixIcon: icon != null ? Icon(icon, size: 20, color: _kPrimary) : null,
          prefixText: prefix,
          prefixStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _modernDropdown<T>({
    required String label, required IconData icon, required T value,
    required List<T> items, required ValueChanged<T?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: DropdownButtonFormField<T>(
        value: value,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toString()))).toList(),
        onChanged: onChanged,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF9CA3AF)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          prefixIcon: Icon(icon, size: 20, color: _kPrimary),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
