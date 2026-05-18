import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'addproduct.dart';
import 'edit_product.dart';

// ── Design tokens ──────────────────────────────────────────
const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);
const Color _kCard = Colors.white;
const Color _kGreen = Color(0xFF059669);
const Color _kOrange = Color(0xFFF59E0B);
const Color _kRed = Color(0xFFDC2626);
const Color _kTextPrimary = Color(0xFF111827);
const Color _kTextSecondary = Color(0xFF6B7280);

class InventoryManagementScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const InventoryManagementScreen({super.key, this.onBack});

  @override
  State<InventoryManagementScreen> createState() =>
      _InventoryManagementScreenState();
}

class _InventoryManagementScreenState extends State<InventoryManagementScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _salesLog = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;
  RealtimeChannel? _productChannel;
  RealtimeChannel? _logChannel;

  // Today's sales stats
  int _soldTodayCount = 0;
  double _soldTodayRevenue = 0;

  // Summary stats
  int get _totalItems => _products.length;
  int get _lowStockCount =>
      _products.where((p) => _stockOf(p) > 0 && _stockOf(p) < 5).length;
  int get _outOfStockCount =>
      _products.where((p) => _stockOf(p) <= 0).length;
  double get _totalValue => _products.fold(0.0, (sum, p) {
        final price = (p['price'] as num?)?.toDouble() ?? 0;
        final stock = _stockOf(p);
        return sum + (price * stock);
      });
  int _stockOf(Map<String, dynamic> p) {
    final s = p['stock_quantity'];
    if (s is int) return s;
    return int.tryParse(s?.toString() ?? '') ?? 0;
  }

  int? _parseWholeNumber(String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null) return null;
    if (value != value.truncateToDouble()) return null;
    return value.toInt();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadProducts();
    _loadSalesLog();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _productChannel = supabase
        .channel('inventory-products-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'product',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) { if (mounted) _loadProducts(); },
        )
        .subscribe();

    _logChannel = supabase
        .channel('inventory-log-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'inventory_log',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) { if (mounted) _loadSalesLog(); },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _productChannel?.unsubscribe();
    if (_productChannel != null) supabase.removeChannel(_productChannel!);
    _logChannel?.unsubscribe();
    if (_logChannel != null) supabase.removeChannel(_logChannel!);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final response = await supabase
          .from('product')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _products = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Inventory load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSalesLog() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await supabase
          .from('inventory_log')
          .select()
          .eq('user_id', userId)
          .eq('type', 'sale')
          .order('created_at', ascending: false)
          .limit(100);
      final logs = List<Map<String, dynamic>>.from(response);

      // Calculate today's totals
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      int todayCount = 0;
      double todayRevenue = 0;
      for (final log in logs) {
        final createdAt = DateTime.tryParse(log['created_at']?.toString() ?? '');
        if (createdAt != null && createdAt.isAfter(todayStart)) {
          todayCount += (log['quantity'] as num?)?.toInt() ?? 0;
          todayRevenue += (log['total_amount'] as num?)?.toDouble() ?? 0;
        }
      }

      if (mounted) {
        setState(() {
          _salesLog = logs;
          _soldTodayCount = todayCount;
          _soldTodayRevenue = todayRevenue;
        });
      }
    } catch (e) {
      debugPrint('Sales log load error: \$e');
    }
  }

  List<Map<String, dynamic>> _filteredProducts(int tabIndex) {
    List<Map<String, dynamic>> base;
    switch (tabIndex) {
      case 1:
        base = _products
            .where((p) => _stockOf(p) > 0 && _stockOf(p) < 5)
            .toList();
        break;
      case 2:
        base = _products.where((p) => _stockOf(p) <= 0).toList();
        break;
      default:
        base = _products;
    }
    if (_searchQuery.isEmpty) return base;
    return base.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery);
    }).toList();
  }

  Future<void> _updateStock(
    String productId,
    int newStock, {
    int? previousStock,
    String? productName,
  }) async {
    try {
      await supabase
          .from('product')
          .update({'stock_quantity': newStock})
          .eq('id', productId);
      if (previousStock != null) {
        await _notifyStockChange(
          previousStock: previousStock,
          newStock: newStock,
          productName: productName ?? 'Item',
        );
      }
      _loadProducts();
    } catch (e) {
      debugPrint('Stock update error: $e');
    }
  }

  Future<void> _notifyStockChange({
    required int previousStock,
    required int newStock,
    required String productName,
  }) async {
    final sellerId = supabase.auth.currentUser?.id;
    if (sellerId == null) return;
    const int lowThreshold = 5;
    final crossedToOut = previousStock > 0 && newStock <= 0;
    final crossedToLow =
        previousStock >= lowThreshold && newStock < lowThreshold && newStock > 0;
    final restocked = previousStock <= 0 && newStock > 0;
    if (!crossedToOut && !crossedToLow && !restocked) return;
    String title;
    String body;
    String type;
    if (crossedToOut) {
      title = 'Out of stock';
      body = '$productName is now out of stock. Restock soon to keep selling.';
      type = 'out_of_stock';
    } else if (crossedToLow) {
      title = 'Low stock';
      body = '$productName is running low ($newStock left). Consider restocking.';
      type = 'low_stock';
    } else {
      title = 'Restocked';
      body = '$productName is back in stock ($newStock available).';
      type = 'restocked';
    }
    try {
      await supabase.from('seller_notifications').insert({
        'seller_id': sellerId,
        'title': title,
        'body': body,
        'type': type,
      });
    } catch (_) {}
  }

  Future<void> _deleteProduct(String productId) async {
    try {
      await supabase.from('product').delete().eq('id', productId);
      _loadProducts();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  // ── Quick stock adjustment dialog ─────────────────────────
  void _showStockAdjustDialog(Map<String, dynamic> product) {
    final currentStock = _stockOf(product);
    final controller = TextEditingController();
    String adjustType = 'add'; // 'add' or 'remove'

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Adjust Stock: ${product['name'] ?? 'Product'}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Current Stock',
                        style: TextStyle(color: _kTextSecondary)),
                    Text('$currentStock',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setDialogState(() => adjustType = 'add'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: adjustType == 'add'
                              ? _kGreen.withValues(alpha: 0.1)
                              : _kSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: adjustType == 'add'
                                ? _kGreen
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '+ Restock',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color:
                                  adjustType == 'add' ? _kGreen : _kTextSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setDialogState(() => adjustType = 'remove'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: adjustType == 'remove'
                              ? _kRed.withValues(alpha: 0.1)
                              : _kSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: adjustType == 'remove'
                                ? _kRed
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '− Remove',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: adjustType == 'remove'
                                  ? _kRed
                                  : _kTextSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Quantity',
                  prefixIcon: Icon(
                    adjustType == 'add' ? Icons.add : Icons.remove,
                    color: adjustType == 'add' ? _kGreen : _kRed,
                  ),
                  filled: true,
                  fillColor: _kSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('Cancel', style: TextStyle(color: _kTextSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = int.tryParse(controller.text) ?? 0;
                if (qty <= 0) return;
                int newStock = adjustType == 'add'
                    ? currentStock + qty
                    : (currentStock - qty).clamp(0, 999999);
                _updateStock(
                  product['id'].toString(),
                  newStock,
                  previousStock: currentStock,
                  productName: (product['name'] ?? product['product_name'])
                      ?.toString(),
                );
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Record sale dialog ────────────────────────────────────
  void _showRecordSaleDialog(Map<String, dynamic> product) {
    final currentStock = _stockOf(product);
    final qtyController = TextEditingController();
    final priceController = TextEditingController(
      text: (product['price'] ?? '').toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.point_of_sale_rounded,
                  color: _kGreen, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Record Sale: ${product['name'] ?? 'Product'}',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Available Stock',
                      style: TextStyle(color: _kTextSecondary)),
                  Text('$currentStock',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Quantity sold',
                prefixIcon: const Icon(Icons.shopping_cart_outlined,
                    color: _kPrimary, size: 20),
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'Price per unit',
                prefixIcon: const Icon(Icons.payments_outlined,
                    color: _kPrimary, size: 20),
                prefixText: '₱ ',
                filled: true,
                fillColor: _kSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: _kTextSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final qty = int.tryParse(qtyController.text) ?? 0;
              if (qty <= 0 || qty > currentStock) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(qty > currentStock
                        ? 'Cannot sell more than available stock ($currentStock)'
                        : 'Enter a valid quantity'),
                    backgroundColor: _kRed,
                  ),
                );
                return;
              }
              final newStock = currentStock - qty;
              await _updateStock(
                product['id'].toString(),
                newStock,
                previousStock: currentStock,
                productName: (product['name'] ?? product['product_name'])
                    ?.toString(),
              );

              // Try to log the sale in inventory_log table
              try {
                final userId = supabase.auth.currentUser?.id;
                final price =
                    double.tryParse(priceController.text) ?? 0;
                await supabase.from('inventory_log').insert({
                  'user_id': userId,
                  'product_id': product['id'].toString(),
                  'product_name': product['name'] ?? 'Product',
                  'type': 'sale',
                  'quantity': qty,
                  'price_per_unit': price,
                  'total_amount': price * qty,
                  'notes': 'Manual sale recorded',
                  'created_at': DateTime.now().toIso8601String(),
                });
                _loadSalesLog();
              } catch (_) {
                // inventory_log table may not exist yet
              }

              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Sale recorded: $qty × ${product['name']}'),
                    backgroundColor: _kGreen,
                  ),
                );
              }
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Record Sale'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Edit product dialog ───────────────────────────────────
  // ignore: unused_element
  void _showEditProductDialog(Map<String, dynamic> product) {
    final nameController =
        TextEditingController(text: product['name']?.toString() ?? '');
    final priceController =
        TextEditingController(text: product['price']?.toString() ?? '');
    final stockController =
        TextEditingController(text: _stockOf(product).toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: _kPrimary, size: 22),
            SizedBox(width: 10),
            Text('Edit Product',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogField('Product Name', nameController, Icons.label_outline),
              const SizedBox(height: 10),
              _buildDialogField(
                  'Price (₱)', priceController, Icons.payments_outlined,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 10),
              _buildDialogField(
                  'Stock Quantity', stockController, Icons.inventory_2_outlined,
                  keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: _kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final priceValue = _parseWholeNumber(priceController.text) ??
                    ((product['price'] is num)
                        ? (product['price'] as num).toInt()
                        : 0);
                final previousStock = _stockOf(product);
                final newStock =
                    int.tryParse(stockController.text) ?? previousStock;
                await supabase.from('product').update({
                  'name': nameController.text,
                  'price': priceValue,
                  'stock_quantity': newStock,
                }).eq('id', product['id'].toString());
                await _notifyStockChange(
                  previousStock: previousStock,
                  newStock: newStock,
                  productName: nameController.text.trim().isEmpty
                      ? ((product['name'] ?? product['product_name'])
                              ?.toString() ??
                          'Item')
                      : nameController.text.trim(),
                );
                _loadProducts();
              } catch (e) {
                debugPrint('Edit product error: $e');
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogField(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _kPrimary, size: 20),
        filled: true,
        fillColor: _kSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ── BUILD ─────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          size: 20, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('Inventory',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AddProductPage()),
                      );
                      _loadProducts();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: _kPrimary,
                      minimumSize: const Size(80, 40),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Summary cards ──
              _buildSummaryCards(),
              const SizedBox(height: 16),

              // ── Search bar ──
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.grey[400], size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Search products...',
                          hintStyle: TextStyle(color: _kTextSecondary),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () => _searchController.clear(),
                        child: const Icon(Icons.close,
                            size: 18, color: _kTextSecondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Tabs ──
              Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: _kPrimary,
                  unselectedLabelColor: _kTextSecondary,
                  indicatorColor: _kPrimary,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13),
                  tabs: [
                    Tab(text: 'All (${_products.length})'),
                    Tab(text: 'Low Stock ($_lowStockCount)'),
                    Tab(text: 'Out ($_outOfStockCount)'),
                    const Tab(text: 'Sales Log'),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Product list ──
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: _kPrimary, strokeWidth: 3))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          ...List.generate(3, (tabIndex) {
                            final items = _filteredProducts(tabIndex);
                            if (items.isEmpty) {
                              return _buildEmptyState(tabIndex);
                            }
                            return RefreshIndicator(
                              onRefresh: _loadProducts,
                              color: _kPrimary,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.only(top: 4, bottom: 80),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  return _buildInventoryCard(items[index]);
                                },
                              ),
                            );
                          }),
                          _buildSalesLogTab(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Summary cards row ─────────────────────────────────────
  Widget _buildSummaryCards() {
    return Row(
      children: [
        _SummaryTile(
          label: 'Total Items',
          value: '$_totalItems',
          icon: Icons.inventory_2_rounded,
          color: _kPrimary,
        ),
        const SizedBox(width: 8),
        _SummaryTile(
          label: 'Low Stock',
          value: '$_lowStockCount',
          icon: Icons.warning_amber_rounded,
          color: _kOrange,
        ),
        const SizedBox(width: 8),
        _SummaryTile(
          label: 'Out of Stock',
          value: '$_outOfStockCount',
          icon: Icons.remove_shopping_cart_rounded,
          color: _kRed,
        ),
        const SizedBox(width: 8),
        _SummaryTile(
          label: 'Sold Today',
          value: '$_soldTodayCount',
          icon: Icons.point_of_sale_rounded,
          color: _kGreen,
        ),
        const SizedBox(width: 8),
        _SummaryTile(
          label: 'Total Value',
          value: '\u20b1${_totalValue.toStringAsFixed(0)}',
          icon: Icons.monetization_on_rounded,
          color: _kOrange,
        ),
      ],
    );
  }

  // ── Empty state ───────────────────────────────────────────
  Widget _buildEmptyState(int tabIndex) {
    final messages = [
      'No products yet.\nTap + Add to create one.',
      'No low-stock products. Great job!',
      'No out-of-stock items. Everything is stocked!',
    ];
    final icons = [
      Icons.inventory_2_outlined,
      Icons.check_circle_outline_rounded,
      Icons.check_circle_outline_rounded,
    ];
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icons[tabIndex], size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty
                ? 'No products match "$_searchQuery"'
                : messages[tabIndex],
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Inventory card ────────────────────────────────────────
  Widget _buildInventoryCard(Map<String, dynamic> product) {
    final name = product['name']?.toString() ?? 'Unknown';
    final price = product['price'];
    final imageUrl = product['image_url']?.toString();
    final stock = _stockOf(product);
    final isOutOfStock = stock <= 0;
    final isLowStock = stock > 0 && stock < 5;

    Color stockColor = _kGreen;
    String stockLabel = 'In Stock';
    if (isOutOfStock) {
      stockColor = _kRed;
      stockLabel = 'Out of Stock';
    } else if (isLowStock) {
      stockColor = _kOrange;
      stockLabel = 'Low Stock';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOutOfStock
              ? _kRed.withValues(alpha: 0.2)
              : isLowStock
                  ? _kOrange.withValues(alpha: 0.2)
                  : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top row: image + info + stock badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: _buildImage(imageUrl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      price != null ? '₱$price' : '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _kPrimary,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: stockColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      stockLabel,
                      style: TextStyle(
                          color: stockColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Qty: $stock',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: stockColor),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── Action buttons row ──
          Row(
            children: [
              _ActionChip(
                icon: Icons.add_circle_outline,
                label: 'Adjust Stock',
                color: _kPrimary,
                onTap: () => _showStockAdjustDialog(product),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: Icons.point_of_sale_rounded,
                label: 'Record Sale',
                color: _kGreen,
                onTap: () => _showRecordSaleDialog(product),
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: Icons.edit_outlined,
                label: 'Edit',
                color: _kOrange,
                onTap: () async {
                  final updated = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditProductPage(product: product),
                    ),
                  );
                  if (updated == true) _loadProducts();
                },
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      title: const Text('Delete product?'),
                      content:
                          Text('Remove "$name" from your inventory?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteProduct(product['id'].toString());
                          },
                          child: const Text('Delete',
                              style: TextStyle(color: _kRed)),
                        ),
                      ],
                    ),
                  );
                },
                child:
                    const Icon(Icons.delete_outline, color: _kRed, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Sales log tab ──────────────────────────────────────────
  Widget _buildSalesLogTab() {
    if (_salesLog.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'No sales recorded yet.\nUse "Record Sale" on any product.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Group by date
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    return RefreshIndicator(
      onRefresh: _loadSalesLog,
      color: _kPrimary,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 80),
        itemCount: _salesLog.length + 1, // +1 for the revenue header
        itemBuilder: (context, index) {
          if (index == 0) {
            // Today's revenue header
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF059669), Color(0xFF10B981)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.trending_up_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Today's Revenue",
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        '\u20b1${_soldTodayRevenue.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Items Sold',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        '$_soldTodayCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          final log = _salesLog[index - 1];
          final createdAt =
              DateTime.tryParse(log['created_at']?.toString() ?? '');
          final qty = (log['quantity'] as num?)?.toInt() ?? 0;
          final total = (log['total_amount'] as num?)?.toDouble() ?? 0;
          final pricePerUnit =
              (log['price_per_unit'] as num?)?.toDouble() ?? 0;
          final productName = log['product_name']?.toString() ?? 'Product';

          // Date label
          String dateLabel = '';
          if (createdAt != null) {
            if (createdAt.isAfter(todayStart)) {
              dateLabel = 'Today';
            } else if (createdAt.isAfter(yesterdayStart)) {
              dateLabel = 'Yesterday';
            } else {
              dateLabel =
                  '${createdAt.month}/${createdAt.day}/${createdAt.year}';
            }
          }

          // Time label
          String timeLabel = '';
          if (createdAt != null) {
            final hour = createdAt.hour > 12
                ? createdAt.hour - 12
                : (createdAt.hour == 0 ? 12 : createdAt.hour);
            final amPm = createdAt.hour >= 12 ? 'PM' : 'AM';
            final min = createdAt.minute.toString().padLeft(2, '0');
            timeLabel = '$hour:$min $amPm';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shopping_bag_outlined,
                      color: _kGreen, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(productName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 3),
                      Text(
                        '$qty x \u20b1${pricePerUnit.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: _kTextSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\u20b1${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: _kGreen),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$dateLabel \u00b7 $timeLabel',
                      style: const TextStyle(
                          color: _kTextSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildImage(String? url) {
    if (url == null || url.isEmpty) return _placeholder();
    if (url.startsWith('assets/') || url.startsWith('images/')) {
      return Image.asset(url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder());
    }
    return Image.network(url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder());
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child:
          const Icon(Icons.image_outlined, size: 28, color: _kTextSecondary),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ── HELPER WIDGETS ────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 15),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: _kTextPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: _kTextSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
