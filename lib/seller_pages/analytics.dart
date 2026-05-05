import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Design tokens ──────────────────────────────────────────────
const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kPrimaryDark = Color(0xFF153075);
const Color _kSurface = Color(0xFFF8F9FC);
const Color _kText = Color(0xFF111827);
const Color _kSub = Color(0xFF6B7280);
const Color _kGreen = Color(0xFF059669);
const Color _kAmber = Color(0xFFF59E0B);
const Color _kPurple = Color(0xFF8B5CF6);
const Color _kRed = Color(0xFFDC2626);

class AnalyticsReportScreen extends StatefulWidget {
  const AnalyticsReportScreen({super.key});

  @override
  State<AnalyticsReportScreen> createState() => _AnalyticsReportScreenState();
}

class _AnalyticsReportScreenState extends State<AnalyticsReportScreen> {
  String _selectedPeriod = 'This Month';
  final List<String> _periods = ['Last 7 Days', 'This Month', 'This Year', 'All-time'];

  bool _isLoading = true;
  double _totalRevenue = 0;
  int _totalOrders = 0;
  double _avgOrder = 0;
  String _topSelling = '—';
  int _completedOrders = 0;
  int _pendingOrders = 0;
  List<Map<String, dynamic>> _productSalesData = [];
  List<MapEntry<String, double>> _revenueChartData = [];

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  DateTime _periodStart() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Last 7 Days':
        return now.subtract(const Duration(days: 7));
      case 'This Month':
        return DateTime(now.year, now.month, 1);
      case 'This Year':
        return DateTime(now.year, 1, 1);
      default:
        return DateTime(2000);
    }
  }

  Future<void> _loadAnalytics() async {
    if (mounted) setState(() => _isLoading = true);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final periodStart = _periodStart();
      final List<Map<String, dynamic>> orders = List<Map<String, dynamic>>.from(
        await supabase
            .from('orders')
            .select()
            .eq('seller_id', userId)
            .gte('created_at', periodStart.toIso8601String()),
      );

      double revenue = 0;
      int completed = 0;
      int pending = 0;
      final productCount = <String, int>{};
      final productRevenue = <String, double>{};
      final dailyRevenue = <String, double>{};

      for (final o in orders) {
        final price = (o['price'] as num?)?.toDouble() ?? 0;
        final qty = (o['qty'] as num?)?.toInt() ?? 1;
        final amount = price * qty;
        final status = o['status']?.toString() ?? '';

        if (status == 'completed') {
          revenue += amount;
          completed++;
          try {
            final dt = DateTime.parse(o['created_at'].toString()).toLocal();
            String key;
            if (_selectedPeriod == 'Last 7 Days') {
              const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              key = weekdays[dt.weekday - 1];
            } else if (_selectedPeriod == 'This Month') {
              key = '${dt.day}';
            } else {
              const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
              key = months[dt.month - 1];
            }
            dailyRevenue[key] = (dailyRevenue[key] ?? 0) + amount;
          } catch (_) {}
        }
        if (status == 'pending') pending++;

        final pName = o['product_name']?.toString() ?? '';
        if (pName.isNotEmpty) {
          productCount[pName] = (productCount[pName] ?? 0) + qty;
          if (status == 'completed') {
            productRevenue[pName] = (productRevenue[pName] ?? 0) + amount;
          }
        }
      }

      String topSelling = '—';
      if (productCount.isNotEmpty) {
        topSelling = productCount.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
      }

      List<MapEntry<String, double>> chartEntries;
      if (_selectedPeriod == 'Last 7 Days') {
        const order = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        chartEntries = order.map((d) => MapEntry(d, dailyRevenue[d] ?? 0)).toList();
      } else if (_selectedPeriod == 'This Month') {
        final now = DateTime.now();
        chartEntries = List.generate(now.day,
            (i) => MapEntry('${i + 1}', dailyRevenue['${i + 1}'] ?? 0));
      } else {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        chartEntries = months.map((m) => MapEntry(m, dailyRevenue[m] ?? 0)).toList();
      }

      final products = List<Map<String, dynamic>>.from(
        await supabase.from('product').select('name, stock_quantity').eq('user_id', userId),
      );
      final salesData = products.map((p) {
        final pName = p['name']?.toString() ?? '';
        final sold = productCount[pName] ?? 0;
        final rev = productRevenue[pName] ?? 0;
        return {'name': pName, 'sold': sold, 'revenue': rev, 'stock': p['stock_quantity'] ?? 0};
      }).toList();
      salesData.sort((a, b) => (b['sold'] as int).compareTo(a['sold'] as int));

      if (mounted) {
        setState(() {
          _totalRevenue = revenue;
          _totalOrders = orders.length;
          _completedOrders = completed;
          _pendingOrders = pending;
          _avgOrder = completed > 0 ? revenue / completed : 0;
          _topSelling = topSelling;
          _productSalesData = salesData;
          _revenueChartData = chartEntries;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Analytics error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 2.5))
                  : RefreshIndicator(
                      color: _kPrimary,
                      onRefresh: _loadAnalytics,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        children: [
                          const SizedBox(height: 16),
                          _buildPeriodChips(),
                          const SizedBox(height: 20),
                          _buildKpiGrid(),
                          const SizedBox(height: 20),
                          _buildRevenueChart(),
                          const SizedBox(height: 20),
                          _buildProductTable(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kPrimary, _kPrimaryDark],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Analytics',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(_selectedPeriod,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          _HeroMini(icon: Icons.trending_up_rounded,
              value: '₱${_formatNumber(_totalRevenue)}', label: 'Revenue'),
          const SizedBox(width: 10),
          _HeroMini(icon: Icons.receipt_long_rounded,
              value: '$_totalOrders', label: 'Orders'),
        ],
      ),
    );
  }

  Widget _buildPeriodChips() {
    return Row(
      children: _periods.map((p) {
        final active = p == _selectedPeriod;
        return Expanded(
          child: GestureDetector(
            onTap: () { setState(() => _selectedPeriod = p); _loadAnalytics(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: active ? _kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: active
                    ? [BoxShadow(color: _kPrimary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
                    : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
              ),
              child: Text(p,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: active ? Colors.white : _kSub),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKpiGrid() {
    final kpis = [
      _KpiData('Total Revenue', '₱${_formatNumber(_totalRevenue)}', Icons.payments_rounded, _kGreen),
      _KpiData('Total Orders', '$_totalOrders', Icons.receipt_long_rounded, _kPrimary),
      _KpiData('Avg. Order', '₱${_formatNumber(_avgOrder)}', Icons.analytics_rounded, _kPurple),
      _KpiData('Top Selling', _topSelling, Icons.star_rounded, _kAmber, smallValue: true),
      _KpiData('Completed', '$_completedOrders', Icons.check_circle_rounded, _kGreen),
      _KpiData('Pending', '$_pendingOrders', Icons.schedule_rounded, _kAmber),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.92,
      children: kpis.map((k) => _KpiCard(data: k)).toList(),
    );
  }

  Widget _buildRevenueChart() {
    if (_revenueChartData.isEmpty || _revenueChartData.every((e) => e.value == 0)) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Center(child: Column(children: [
          Icon(Icons.bar_chart_rounded, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text('No revenue data for this period', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        ])),
      );
    }

    final maxVal = _revenueChartData.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    bool showLabel(int index) {
      if (_selectedPeriod == 'This Month') return (index + 1) % 5 == 0 || index == 0;
      return true;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.bar_chart_rounded, color: _kPrimary, size: 18)),
              const SizedBox(width: 10),
              const Expanded(child: Text('Revenue Over Time',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _kText))),
              Text('₱${_formatNumber(_totalRevenue)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _kGreen)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _revenueChartData.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                final barH = maxVal > 0 ? (item.value / maxVal) * 110 : 0.0;
                final isTop = item.value == maxVal && maxVal > 0;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isTop)
                        Text('₱${_formatNumber(item.value)}',
                            style: const TextStyle(fontSize: 8, color: _kGreen, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: barH.toDouble(),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: isTop
                                ? [_kPrimary, _kPrimaryDark]
                                : [_kPrimary.withValues(alpha: 0.5), _kPrimary.withValues(alpha: 0.8)],
                          ),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (showLabel(i))
                        Text(item.key, style: const TextStyle(fontSize: 8, color: _kSub), textAlign: TextAlign.center)
                      else
                        const SizedBox(height: 10),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(width: 32, height: 32,
                    decoration: BoxDecoration(color: _kAmber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.inventory_2_rounded, color: _kAmber, size: 18)),
                const SizedBox(width: 10),
                const Expanded(child: Text('Product Performance',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _kText))),
                Text('${_productSalesData.length} items',
                    style: const TextStyle(fontSize: 11, color: _kSub)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: const [
              Expanded(flex: 4, child: Text('Product', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kSub))),
              SizedBox(width: 36, child: Text('Sold', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kSub))),
              Expanded(flex: 3, child: Text('Revenue', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kSub))),
              SizedBox(width: 48, child: Text('Stock', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kSub))),
            ]),
          ),
          if (_productSalesData.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No products to show', style: TextStyle(color: _kSub, fontSize: 13))))
          else
            ..._productSalesData.asMap().entries.map((entry) {
              final i = entry.key;
              final p = entry.value;
              final isLast = i == _productSalesData.length - 1;
              final sold = (p['sold'] as int? ?? 0);
              final rev = (p['revenue'] as double? ?? 0.0);
              final stock = p['stock'];
              final stockNum = stock is int ? stock : (int.tryParse(stock?.toString() ?? '') ?? 0);
              final isLowStock = stockNum < 5;
              final isTopSeller = i == 0 && sold > 0;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Row(children: [
                            if (isTopSeller)
                              Container(width: 16, height: 16, margin: const EdgeInsets.only(right: 4),
                                  decoration: BoxDecoration(color: _kAmber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                  child: const Icon(Icons.star_rounded, size: 10, color: _kAmber)),
                            Expanded(child: Text(p['name']?.toString() ?? '—',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kText),
                                maxLines: 2, overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                        SizedBox(width: 36, child: Text('$sold',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                color: sold > 0 ? _kPrimary : _kSub))),
                        Expanded(flex: 3, child: Text('₱${_formatNumber(rev)}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                color: rev > 0 ? _kGreen : _kSub))),
                        SizedBox(
                          width: 48,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isLowStock ? _kRed.withValues(alpha: 0.1) : _kGreen.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('$stockNum',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                      color: isLowStock ? _kRed : _kGreen)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast) const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF3F4F6)),
                ],
              );
            }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  String _formatNumber(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

class _HeroMini extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _HeroMini({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white70, size: 14),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
        ]),
      ]),
    );
  }
}

class _KpiData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool smallValue;
  const _KpiData(this.label, this.value, this.icon, this.color, {this.smallValue = false});
}

class _KpiCard extends StatelessWidget {
  final _KpiData data;
  const _KpiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(width: 32, height: 32,
              decoration: BoxDecoration(color: data.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(data.icon, color: data.color, size: 16)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(data.value,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: data.smallValue ? 13 : 17,
                    fontWeight: FontWeight.w800, color: _kText)),
            const SizedBox(height: 2),
            Text(data.label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: _kSub, fontWeight: FontWeight.w500)),
          ]),
        ],
      ),
    );
  }
}
