import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductViewPage extends StatelessWidget {
  final Map<String, dynamic> product;
  const ProductViewPage({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final displayName = (product['name'] ?? product['product_name'] ?? 'Unknown product').toString();
    final priceRaw = product['price'] ?? product['price_per_kg'];
    final priceValue = double.tryParse(priceRaw?.toString() ?? '') ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      "Details",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.shopping_cart_outlined),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            const Icon(Icons.image_outlined, size: 120, color: Colors.grey),
            const SizedBox(height: 6),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _indicator(true),
                _indicator(false),
                _indicator(false),
              ],
            ),

            const SizedBox(height: 20),

            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),

                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "₱$priceValue/KG",
                            style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF1A3C8C),
                                fontWeight: FontWeight.bold),
                          ),
                          const Text("Reg: ₱000", style: TextStyle(color: Colors.grey)),
                        ],
                      ),

                      const SizedBox(height: 20),

                      const Text("Details", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),

                      const Text(
                        "***************************************\n***************************************\n***************************************",
                        style: TextStyle(color: Colors.grey),
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          // ADD TO CART BUTTON
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final supabase = Supabase.instance.client;
                                final user = supabase.auth.currentUser;

                                if (user == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Please login first.")),
                                  );
                                  return;
                                }

                                try {
                                  await supabase.from('cart').insert({
                                    'product_name': displayName,
                                    'price': priceValue,
                                    'qty': 1,
                                    'user_id': user.id,
                                  });

                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text("Added to cart successfully!")),
                                  );
                                } on PostgrestException catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Error: ${e.message}")),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Error: $e")),
                                  );
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Text(
                                "Add To Cart",
                                style: TextStyle(color: Color(0xFF1A3C8C)),
                              ),
                            ),
                          ),

                          const SizedBox(width: 10),

                          // BUY NOW BUTTON
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                final supabase = Supabase.instance.client;
                                final buyerId = supabase.auth.currentUser?.id;

                                if (buyerId == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text("Please login first.")),
                                  );
                                  return;
                                }

                                try {
                                  await supabase.from('orders').insert({
                                    'product_name': displayName,
                                    'price': priceValue,
                                    'qty': 1,
                                    'buyer_id': buyerId,
                                  });

                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text("Order submitted!")),
                                  );
                                } on PostgrestException catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Error: ${e.message}")),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Error: $e")),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A3C8C),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Text("Buy Now"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
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
        color: active ? Colors.orange : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
