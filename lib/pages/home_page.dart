import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cart_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<dynamic> products = [];
  bool isLoading = true;

  // Define the default local asset path
  static const String _defaultAssetPath = "assets/img/kasim.png";

  @override
  void initState() {
    super.initState();
    fetchProducts();
  }

  Future<void> fetchProducts() async {
    try {
      final response = await Supabase.instance.client
          .from('product') 
          .select()
          .order('id', ascending: false);

      setState(() {
        products = response;
        isLoading = false;
      });
    } catch (e) {
      print("FETCH ERROR → $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopHeader(),
            const SizedBox(height: 20),

            Text(
              "Recommended",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 210, 
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : products.isEmpty
                      ? const Center(child: Text("No products yet."))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: products.length,
                          itemBuilder: (_, i) {
                            final p = products[i];

                            return ProductCard(
                              title: p['product_name'] ?? "Juan Store",
                              price: p['price'] != null
                                  ? "₱${p['price']} /kg"
                                  : "₱0",
                              
                              // Pass the product image URL, or the default asset path if null
                              imageUrl: p[''] ?? _defaultAssetPath,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A4DBE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Hey, *****",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.notifications_none,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CartPage()),
                      );
                    },
                    child: const Icon(Icons.shopping_cart_outlined,
                        color: Colors.white, size: 28),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
              hintText: "Search Products or store",
              prefixIcon:
                  const Icon(Icons.search_rounded, color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF173C9E),
              hintStyle: const TextStyle(color: Colors.white70),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  final String title;
  final String price;
  final String imageUrl;

  const ProductCard({
    super.key,
    required this.title,
    required this.price,
    required this.imageUrl,
  });

  // Helper method to check if the path is likely a local asset
  bool _isAssetPath(String path) {
    return path.startsWith('assets/') || path.startsWith('images/');
  }

  @override
  Widget build(BuildContext context) {
    // Determine the correct widget type
    final Widget imageWidget;
    
    if (_isAssetPath(imageUrl)) {
      // Use Image.asset for local files
      imageWidget = Image.asset(
        imageUrl,
        height: 100, 
        width: double.infinity,
        fit: BoxFit.cover,
        // Optional: fallback to a text placeholder if the asset is missing
        errorBuilder: (_, __, ___) => const Center(child: Text('Asset Error')),
      );
    } else {
      // Use Image.network for URLs (Supabase)
      imageWidget = Image.network(
        imageUrl,
        height: 100,
        width: double.infinity,
        fit: BoxFit.cover,
        // Fallback to a local asset image if the network request fails
        errorBuilder: (_, __, ___) => Image.asset(
          "assets/img/kasim.png", // Your specified asset as the network fallback
          height: 100,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }

    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageWidget, // Use the determined image widget
          ),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const Text("Shop/Store",
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          Text(price,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }
}