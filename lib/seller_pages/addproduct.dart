import 'package:flutter/foundation.dart'; // Uint8List for web
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final supabase = Supabase.instance.client;

  // Controllers
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController retailPriceCtrl = TextEditingController();
  final TextEditingController stockCtrl = TextEditingController();
  final TextEditingController descriptionCtrl = TextEditingController();

  // Dropdown selections
  String selectedCategory = "Fish";
  String selectedUnit = "Kg";

  List<String> categories = ["Fish", "Meat", "Vegetable", "Fruit", "Service"];
  List<String> unitTypes = ["Kg", "pcs", "g"];

  // Image variables
  XFile? pickedXFile;
  Uint8List? pickedBytes;

  // ================================= PICK IMAGE =================================
  Future<void> pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);

    if (file != null) {
      pickedXFile = file;
      pickedBytes = await file.readAsBytes(); // ALWAYS READ AS BYTES
      setState(() {});
    }
  }

  // ================================= UPLOAD IMAGE =================================
  Future<String?> uploadImage() async {
    try {
      if (pickedXFile == null || pickedBytes == null) return null;

      final ext = pickedXFile!.name.split('.').last;
      final fileName = "product_${DateTime.now().millisecondsSinceEpoch}.$ext";

      // Always upload using binary (works for mobile + web)
      await supabase.storage.from('products').uploadBinary(
        fileName,
        pickedBytes!,
        fileOptions: FileOptions(contentType: "image/$ext"),
      );

      // Get public URL
      return supabase.storage.from('products').getPublicUrl(fileName);
    } catch (e) {
      print("UPLOAD ERROR → $e");
      return null;
    }
  }

  // ================================= SAVE PRODUCT =================================
  Future<void> saveProduct() async {
    if (nameCtrl.text.isEmpty ||
        priceCtrl.text.isEmpty ||
        retailPriceCtrl.text.isEmpty ||
        stockCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields.")),
      );
      return;
    }

    String? imageUrl;

    if (pickedXFile != null) {
      imageUrl = await uploadImage();

      if (imageUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to upload image.")),
        );
        return;
      }
    }

    final productData = {
      "name": nameCtrl.text,
      "category": selectedCategory,
      "price": double.parse(priceCtrl.text),
      "retail_price": double.parse(retailPriceCtrl.text),
      "stock_quantity": int.parse(stockCtrl.text),
      "unit_type": selectedUnit,
      "description": descriptionCtrl.text,
      "image_url": imageUrl,
    };

    try {
      await supabase.from('product').insert(productData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Product added successfully!")),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  // ================================= UI =================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Add Product"),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image preview
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(15),
                image: (pickedBytes != null)
                    ? DecorationImage(
                        image: MemoryImage(pickedBytes!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: pickedBytes == null
                  ? const Center(
                      child: Icon(Icons.image_outlined,
                          size: 80, color: Colors.grey),
                    )
                  : null,
            ),

            const SizedBox(height: 15),

            Center(
              child: ElevatedButton.icon(
                onPressed: pickImage,
                icon: const Icon(Icons.upload),
                label: const Text("Upload"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 25,
                    vertical: 12,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 25),

            const Text("Product name:"),
            TextField(controller: nameCtrl, decoration: inputStyle()),

            const SizedBox(height: 15),

            const Text("Category:"),
            DropdownButtonFormField(
              initialValue: selectedCategory,
              items: categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (value) => setState(() => selectedCategory = value!),
              decoration: inputStyle(),
            ),

            const SizedBox(height: 15),

            const Text("Price (per unit):"),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: inputStyle(label: selectedUnit),
            ),

            const SizedBox(height: 15),

            const Text("Retail Price:"),
            TextField(
              controller: retailPriceCtrl,
              keyboardType: TextInputType.number,
              decoration: inputStyle(label: selectedUnit),
            ),

            const SizedBox(height: 15),

            const Text("Stock Quantity:"),
            TextField(
              controller: stockCtrl,
              keyboardType: TextInputType.number,
              decoration: inputStyle(),
            ),

            const SizedBox(height: 15),

            const Text("Unit Type:"),
            DropdownButtonFormField(
              initialValue: selectedUnit,
              items: unitTypes
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (val) => setState(() => selectedUnit = val!),
              decoration: inputStyle(),
            ),

            const SizedBox(height: 15),

            const Text("Description:"),
            TextField(
              controller: descriptionCtrl,
              maxLines: 4,
              decoration: inputStyle(),
            ),

            const SizedBox(height: 25),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saveProduct,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child:
                    const Text("Save Product", style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration inputStyle({String? label}) {
    return InputDecoration(
      suffixText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    );
  }
}
