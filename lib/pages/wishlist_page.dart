import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'productdet.dart';

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWishlist();
  }

  Future<void> _loadWishlist() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await Supabase.instance.client
          .from('wishlist')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeFromWishlist(String productId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from('wishlist')
          .delete()
          .eq('user_id', user.id)
          .eq('product_id', productId);
      if (mounted) {
        setState(() => _items.removeWhere((i) => i['product_id'] == productId));
      }
    } catch (_) {}
  }

  String _formatPrice(dynamic price) {
    final p = (price as num?)?.toDouble() ?? 0;
    return p.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'My Wishlist',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFF2A4BA0),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.favorite_border, size: 64, color: Color(0xFFCBD5E1)),
                      SizedBox(height: 16),
                      Text(
                        'Your wishlist is empty',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Tap the heart icon on products to save them here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final imageUrl = item['image_url']?.toString() ?? '';
                    final name = item['product_name']?.toString() ?? 'Product';
                    final price = item['price'];
                    final storeName = item['store_name']?.toString() ?? '';
                    final productId = item['product_id']?.toString() ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          // Fetch full product data before navigating. Pull
                          // the seller's approval status so we can block the
                          // navigation if the seller has been suspended.
                          try {
                            final product = await Supabase.instance.client
                                .from('product')
                                .select(
                                  '*, seller_profiles!product_seller_id_fkey(approval_status)',
                                )
                                .eq('id', productId)
                                .maybeSingle();
                            if (!context.mounted) return;
                            if (product == null) return;
                            final sp = product['seller_profiles'];
                            final sellerStatus = sp is Map
                                ? sp['approval_status']
                                      ?.toString()
                                      .toLowerCase()
                                : null;
                            if (sellerStatus == 'suspended' ||
                                sellerStatus == 'rejected') {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'This store is currently unavailable.',
                                  ),
                                ),
                              );
                              return;
                            }
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProductViewPage(product: product),
                              ),
                            );
                            _loadWishlist(); // refresh after returning
                          } catch (_) {}
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: imageUrl.isNotEmpty
                                    ? Image.network(
                                        imageUrl,
                                        width: 70,
                                        height: 70,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            const _PlaceholderImage(),
                                      )
                                    : const _PlaceholderImage(),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1F2937),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (storeName.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        storeName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Text(
                                      '₱${_formatPrice(price)}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1A3C8C),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.favorite,
                                  color: Color(0xFFEF4444),
                                ),
                                onPressed: () => _removeFromWishlist(productId),
                                tooltip: 'Remove from wishlist',
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 70,
      color: const Color(0xFFE5E7EB),
      child: const Icon(Icons.image_outlined, color: Color(0xFF9CA3AF), size: 32),
    );
  }
}
