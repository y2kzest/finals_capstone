import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnalyticsReportScreen extends StatefulWidget {
  const AnalyticsReportScreen({super.key});

  @override
  State<AnalyticsReportScreen> createState() => _AnalyticsReportScreenState();
}

class _AnalyticsReportScreenState extends State<AnalyticsReportScreen> {
  String selectedTimeframe = 'All-time';
  bool isTimeframeMenuOpen = false;
  String selectedQuickPeriod = 'This Month';
  final List<String> quickPeriods = ['Last 7 Days', 'This Month', 'This Year', 'All-time'];

  bool _isLoading = true;
  double _totalRevenue = 0;
  int _totalOrders = 0;
  double _avgOrder = 0;
  String _topSelling = '—';
  List<Map<String, dynamic>> _productSalesData = [];

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final orders = List<Map<String, dynamic>>.from(
        await supabase.from('orders').select().eq('seller_id', userId),
      );
      double revenue = 0;
      final productCount = <String, int>{};
      for (final o in orders) {
        final price = (o['price'] as num?)?.toDouble() ?? 0;
        final qty = (o['qty'] as num?)?.toInt() ?? 1;
        revenue += price * qty;
        final pName = o['product_name']?.toString() ?? '';
        if (pName.isNotEmpty) productCount[pName] = (productCount[pName] ?? 0) + qty;
      }
      String topSelling = '—';
      if (productCount.isNotEmpty) {
        topSelling = productCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      }
      final products = List<Map<String, dynamic>>.from(
        await supabase.from('product').select('name, stock_quantity').eq('user_id', userId),
      );
      final salesData = <Map<String, dynamic>>[];
      for (final p in products) {
        final pName = p['name']?.toString() ?? '';
        final sold = productCount[pName] ?? 0;
        double pRevenue = 0;
        for (final o in orders) {
          if (o['product_name'] == pName) {
            pRevenue += ((o['price'] as num?)?.toDouble() ?? 0) *
                ((o['qty'] as num?)?.toInt() ?? 1);
          }
        }
        salesData.add({
          'Product': pName,
          'Sold': '$sold',
          'Revenue': '₱${pRevenue.toStringAsFixed(0)}',
          'StockLeft': p['stock_quantity']?.toString() ?? '—',
        });
      }
      setState(() {
        _totalRevenue = revenue;
        _totalOrders = orders.length;
        _avgOrder = orders.isNotEmpty ? revenue / orders.length : 0;
        _topSelling = topSelling;
        _productSalesData = salesData;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Analytics error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          // --- Main Content (Scrollable) ---
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Header (with Padding to account for Status Bar)
                Padding(
                  padding: const EdgeInsets.only(top: 30, bottom: 20),
                  child: Row(
                    children: [
                      // Back Button
                      GestureDetector(
                        onTap: () {
                          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[200],
                          ),
                          child: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.black87),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Title
                      const Text(
                        'Analytics Report',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                // --- Timeframe Selector ---
                GestureDetector(
                  onTap: () {
                    setState(() {
                      isTimeframeMenuOpen = !isTimeframeMenuOpen;
                    });
                  },
                  child: Row(
                    children: [
                      const Text(
                        'Timeframe:',
                        style: TextStyle(fontSize: 16, color: Colors.black),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        selectedTimeframe,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Icon(
                        isTimeframeMenuOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // --- Metric Cards ---
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                    childAspectRatio: 1.2,
                    children: [
                      MetricCard(title: 'Top Sales', value: '₱${_totalRevenue.toStringAsFixed(0)}'),
                      MetricCard(title: 'Total Orders', value: '$_totalOrders'),
                      MetricCard(title: 'Avg Order', value: '₱${_avgOrder.toStringAsFixed(0)}'),
                      MetricCard(title: 'Top Selling', value: _topSelling),
                    ],
                  ),
                const SizedBox(height: 30),

                // --- Product Sales Table Header ---
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Manually space the headers to match the image layout
                      SizedBox(width: 80, child: Text('Product', style: TextStyle(color: Colors.grey))),
                      SizedBox(width: 60, child: Text('Sold', style: TextStyle(color: Colors.grey))),
                      SizedBox(width: 80, child: Text('Revenue', style: TextStyle(color: Colors.grey))),
                      Text('Stock Left', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.grey),
                const SizedBox(height: 10),

                // --- Product Sales List ---
                if (!_isLoading && _productSalesData.isNotEmpty)
                  ..._productSalesData.map((sale) => ProductSaleRow(sale: sale)),

                const SizedBox(height: 50),
              ],
            ),
          ),
          
          // --- Timeframe Menu Overlay (Conditional) ---
          if (isTimeframeMenuOpen)
            Positioned(
              top: 170, // Adjust this value to position the dropdown below the Timeframe label
              left: 20,
              child: TimeframeMenu(
                quickPeriods: quickPeriods,
                selectedPeriod: selectedQuickPeriod,
                onSelect: (period) {
                  setState(() {
                    selectedQuickPeriod = period;
                    selectedTimeframe = period; // Update main display text
                    isTimeframeMenuOpen = false;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
}

// --- Metric Card Widget ---
class MetricCard extends StatelessWidget {
  final String title;
  final String value;

  const MetricCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Product Sale Row Widget (Custom Table) ---
class ProductSaleRow extends StatelessWidget {
  final Map<String, dynamic> sale;

  const ProductSaleRow({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          SizedBox(width: 80, child: Text(sale['Product']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
          SizedBox(width: 60, child: Text(sale['Sold']?.toString() ?? '')),
          SizedBox(width: 80, child: Text(sale['Revenue']?.toString() ?? '')),
          Text(sale['StockLeft']?.toString() ?? ''),
        ],
      ),
    );
  }
}

// --- Timeframe Selection Menu Overlay Widget ---
class TimeframeMenu extends StatelessWidget {
  final List<String> quickPeriods;
  final String selectedPeriod;
  final Function(String) onSelect;

  const TimeframeMenu({
    super.key,
    required this.quickPeriods,
    required this.selectedPeriod,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 5,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 150, // Fixed width based on image size
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 10, 10, 5),
              child: Text(
                'Timeframe: This Month', // Based on the visual in the overlay
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
              ),
            ),
            const Divider(height: 1),
            ...quickPeriods.map((period) {
              final isSelected = period == selectedPeriod;
              return GestureDetector(
                onTap: () => onSelect(period),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  color: isSelected ? Colors.blue[50] : Colors.white,
                  child: Text(
                    period,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.blue[800] : Colors.black,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}