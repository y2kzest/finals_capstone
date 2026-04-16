import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Color _kPrimary = Color(0xFF1A4DBE);
const Color _kPrimaryLight = Color(0xFFE8EEFF);
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

  String selectedCategory = "Fish";
  String selectedUnit = "Kg";

  List<String> categories = ["Fish", "Meat", "Vegetable", "Fruit", "Service", "Apparel"];
  List<String> unitTypes = ["Kg", "pcs", "g"];

  XFile? pickedXFile;
  Uint8List? pickedBytes;
  bool _isSaving = false;

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      pickedXFile = file;
      pickedBytes = await file.readAsBytes();
      setState(() {});
    }
  }

  Future<String?> uploadImage() async {
    try {
      if (pickedXFile == null || pickedBytes == null) return null;
      final ext = pickedXFile!.name.split('.').last;
      final fileName = "product_${DateTime.now().millisecondsSinceEpoch}.$ext";
      await supabase.storage.from('products').uploadBinary(
        fileName,
        pickedBytes!,
        fileOptions: FileOptions(contentType: "image/$ext"),
      );
      return supabase.storage.from('products').getPublicUrl(fileName);
    } catch (e) {
      debugPrint("UPLOAD ERROR → $e");
      return null;
    }
  }

  Future<void> saveProduct() async {
    final isApparel = selectedCategory == 'Apparel';
    if (nameCtrl.text.isEmpty ||
        priceCtrl.text.isEmpty ||
        (!isApparel && retailPriceCtrl.text.isEmpty) ||
        (!isApparel && stockCtrl.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields.")),
      );
      return;
    }

    setState(() => _isSaving = true);

    String? imageUrl;
    if (pickedXFile != null) {
      imageUrl = await uploadImage();
      if (imageUrl == null) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to upload image.")),
        );
        return;
      }
    }

    final userId = supabase.auth.currentUser?.id;
    final productData = {
      "user_id": userId,
      "seller_id": userId,
      "name": nameCtrl.text,
      "category": selectedCategory,
      "price": double.parse(priceCtrl.text),
      "retail_price": isApparel ? 0.0 : double.parse(retailPriceCtrl.text),
      "stock_quantity": isApparel ? 0 : int.parse(stockCtrl.text),
      "unit_type": isApparel ? 'pcs' : selectedUnit,
      "description": descriptionCtrl.text,
      "image_url": imageUrl,
    };

    try {
      await supabase.from('product').insert(productData);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Product added successfully!")),
      );
      Navigator.pop(context);
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
                    // ── Image picker ──
                    GestureDetector(
                      onTap: pickImage,
                      child: Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: pickedBytes != null ? _kPrimary : Colors.grey.shade300,
                            width: pickedBytes != null ? 2 : 1,
                          ),
                          image: pickedBytes != null
                              ? DecorationImage(image: MemoryImage(pickedBytes!), fit: BoxFit.cover)
                              : null,
                        ),
                        child: pickedBytes == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 56, height: 56,
                                    decoration: BoxDecoration(
                                        color: _kPrimaryLight,
                                        borderRadius: BorderRadius.circular(16)),
                                    child: const Icon(Icons.add_a_photo_rounded,
                                        color: _kPrimary, size: 28),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text('Tap to upload product photo',
                                      style: TextStyle(color: Color(0xFF6B7280),
                                          fontSize: 13, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 4),
                                  Text('JPG, PNG • Max 5 MB',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                                ],
                              )
                            : null,
                      ),
                    ),
                    if (pickedBytes != null) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: pickImage,
                          icon: const Icon(Icons.refresh_rounded, size: 18, color: _kPrimary),
                          label: const Text('Change photo',
                              style: TextStyle(color: _kPrimary, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    _sectionTitle('Product Information'),
                    const SizedBox(height: 12),
                    _modernField(label: 'Product Name', controller: nameCtrl,
                        icon: Icons.shopping_bag_outlined),
                    const SizedBox(height: 14),
                    _modernDropdown<String>(
                      label: 'Category', icon: Icons.category_outlined,
                      value: selectedCategory, items: categories,
                      onChanged: (v) => setState(() => selectedCategory = v!),
                    ),
                    const SizedBox(height: 14),
                    _modernField(label: 'Description', controller: descriptionCtrl,
                        icon: Icons.notes_rounded, maxLines: 3),
                    const SizedBox(height: 24),

                    _sectionTitle(selectedCategory == 'Apparel' ? 'Pricing' : 'Pricing & Stock'),
                    const SizedBox(height: 12),
                    if (selectedCategory == 'Apparel') ...
                    [
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
