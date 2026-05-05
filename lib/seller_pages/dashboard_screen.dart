import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/seller_approval_notifications.dart';
import '../bahay.dart';
import 'addproduct.dart';
import 'inventory.dart';
import 'order.dart';
import 'analytics.dart';
import 'seller_messages_page.dart';
import '../pages/seller_profile_page.dart';

// ── Design tokens ──────────────────────────────────────────
const Color kPrimary = Color(0xFF2A4BA0);
const Color kPrimaryDark = Color(0xFF153075);
const Color kSurface = Color(0xFFF8F9FC);
const Color kCard = Colors.white;
const Color kTextPrimary = Color(0xFF111827);
const Color kTextSecondary = Color(0xFF6B7280);
const double kRadius = 20;

class ShopDashboardScreen extends StatefulWidget {
  const ShopDashboardScreen({super.key});

  @override
  State<ShopDashboardScreen> createState() => _ShopDashboardScreenState();
}

class _ShopDashboardScreenState extends State<ShopDashboardScreen> {
  String _userName = 'Seller';
  String _storeName = 'My Store';
  String _approvalStatus = 'pending';
  String _approvalMessage =
      'Your seller account is under review. You will be notified once approved.';
  String? _logoUrl;
  bool _isLoading = true;
  int _pendingOrderCount = 0;
  int _productCount = 0;
  double _salesToday = 0.0;
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _recentOrders = [];
  bool _isShopOpen = false;
  bool _deliveryEnabled = false;
  String _openingTime = '05:00';
  String _closingTime = '19:00';

  @override
  void initState() {
    super.initState();
    _fetchSellerData();
    _syncApprovalStatus();
  }

  // ── Approval sync ─────────────────────────────────────────
  Future<void> _syncApprovalStatus() async {
    try {
      final result =
          await SellerApprovalNotifications().checkApprovalAndNotify();
      if (!mounted || result == null) return;
      final status = (result['status'] ?? 'pending').toString().toLowerCase();
      // Use clean messages — ignore raw API error details from edge functions
      String displayMessage;
      if (status == 'approved') {
        displayMessage = 'Congratulations! Your seller account has been approved.';
      } else if (status == 'rejected') {
        displayMessage = result['message']?.toString() ?? 'Your seller application was not approved.';
      } else {
        displayMessage = 'Your seller account is under review. You will be notified once approved.';
      }
      setState(() {
        _approvalStatus = status;
        _approvalMessage = displayMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _approvalStatus = 'pending';
        _approvalMessage =
            'Your seller account is under review. Notification service unavailable.';
      });
    }
  }

  // ── Approval banner helpers ───────────────────────────────
  IconData get _approvalIcon {
    switch (_approvalStatus) {
      case 'approved':
        return Icons.verified_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  Color get _approvalAccent {
    switch (_approvalStatus) {
      case 'approved':
        return const Color(0xFF059669);
      case 'rejected':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  // ── Data fetch ────────────────────────────────────────────
  Future<void> _fetchSellerData() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await supabase
          .from('seller_profiles')
          .select('full_name, store_name, logo_url, is_open, opening_time, closing_time, delivery_enabled')
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted && response != null) {
        setState(() {
          _userName = response['full_name']?.split(' ').first ?? 'Seller';
          _storeName = response['store_name'] ?? 'My Store';
          _logoUrl = response['logo_url']?.toString();
          _isShopOpen = response['is_open'] == true;
          _openingTime = response['opening_time']?.toString() ?? '05:00';
          _closingTime = response['closing_time']?.toString() ?? '19:00';
          _deliveryEnabled = response['delivery_enabled'] == true;
        });
      }

      final productResp =
          await supabase.from('product').select('id').eq('user_id', userId);
      final pendingResp = await supabase
          .from('orders')
          .select('id')
          .eq('seller_id', userId)
          .eq('status', 'pending');

      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayOrdersResp = List<Map<String, dynamic>>.from(
        await supabase
            .from('orders')
            .select('price, qty')
            .eq('seller_id', userId)
            .eq('status', 'completed')
            .gte('created_at', todayStart.toIso8601String()),
      );
      double sales = 0;
      for (final o in todayOrdersResp) {
        sales += ((o['price'] as num?)?.toDouble() ?? 0) *
            ((o['qty'] as num?)?.toInt() ?? 1);
      }

      // Fetch recent orders for the feed
      final recentResp = List<Map<String, dynamic>>.from(
        await supabase
            .from('orders')
            .select('id, status, price, qty, created_at')
            .eq('seller_id', userId)
            .order('created_at', ascending: false)
            .limit(5),
      );

      if (mounted) {
        setState(() {
          _productCount = (productResp as List).length;
          _pendingOrderCount = (pendingResp as List).length;
          _salesToday = sales;
          _recentOrders = recentResp;
        });
      }
    } on PostgrestException catch (e) {
      debugPrint('Dashboard fetch error: ${e.message}');
    } catch (e) {
      debugPrint('Dashboard error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goBackToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Bahay()),
      (route) => false,
    );
  }

  String _formatTime12hr(String time24) {
    try {
      final parts = time24.split(':');
      int hour = int.parse(parts[0]);
      final min = parts.length > 1 ? parts[1] : '00';
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour == 0) hour = 12;
      if (hour > 12) hour -= 12;
      return '$hour:$min $period';
    } catch (_) {
      return time24;
    }
  }

  Future<void> _toggleShopOpen(bool value) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _isShopOpen = value);
    try {
      await supabase
          .from('seller_profiles')
          .update({'is_open': value})
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Toggle shop open error: $e');
      if (mounted) setState(() => _isShopOpen = !value);
    }
  }

  Future<void> _toggleDelivery(bool value) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _deliveryEnabled = value);
    try {
      await supabase
          .from('seller_profiles')
          .update({'delivery_enabled': value})
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Toggle delivery error: $e');
      if (mounted) setState(() => _deliveryEnabled = !value);
    }
  }

  void _goToTab(int idx) => setState(() => _selectedIndex = idx);

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(),
          const OrdersPage(),
          InventoryManagementScreen(onBack: () => _goToTab(0)),
          const AnalyticsReportScreen(),
        ],
      ),
      bottomNavigationBar: _ModernNavBar(
        currentIndex: _selectedIndex,
        onTap: _goToTab,
      ),
    );
  }

  // ── Home tab ──────────────────────────────────────────────
  Widget _buildHomeTab() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: kPrimary, strokeWidth: 3));
    }
    return SafeArea(
      child: RefreshIndicator(
        color: kPrimary,
        onRefresh: () async {
          await Future.wait([_fetchSellerData(), _syncApprovalStatus()]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // ── Top bar (greeting + avatar) ──
            _buildTopBar(),
            const SizedBox(height: 20),

            // ── Hero stat card ──
            _buildHeroCard(),
            const SizedBox(height: 12),

            // ── Shop Open/Closed toggle ──
            _buildShopStatusToggle(),
            const SizedBox(height: 10),

            // ── Delivery toggle ──
            _buildDeliveryToggle(),
            const SizedBox(height: 16),

            // ── Approval banner ──
            _buildApprovalBanner(),
            const SizedBox(height: 20),

            // ── Stat row ──
            Row(
              children: [
                Expanded(
                    child: _StatCard(
                        label: 'Pending Orders',
                        value: '$_pendingOrderCount',
                        icon: Icons.receipt_long_rounded,
                        color: const Color(0xFFF59E0B),
                        onTap: () => _goToTab(1))),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatCard(
                        label: 'Products',
                        value: '$_productCount',
                        icon: Icons.inventory_2_rounded,
                        color: const Color(0xFF8B5CF6),
                        onTap: () => _goToTab(2))),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatCard(
                        label: 'Today',
                        value: '₱${_salesToday.toStringAsFixed(0)}',
                        icon: Icons.trending_up_rounded,
                        color: const Color(0xFF10B981),
                        onTap: () => _goToTab(3))),
              ],
            ),
            const SizedBox(height: 24),

            // ── Quick actions ──
            const Text('Quick Actions',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary)),
            const SizedBox(height: 12),
            _buildQuickActions(),
            const SizedBox(height: 24),

            // ── Recent orders ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Orders',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kTextPrimary)),
                TextButton(
                  onPressed: () => _goToTab(1),
                  child: const Text('View All',
                      style: TextStyle(
                          color: kPrimary, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildRecentOrders(),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────
  Widget _buildTopBar() {
    return Row(
      children: [
        // Avatar / Logo
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: _logoUrl == null
                ? const LinearGradient(colors: [kPrimary, kPrimaryDark])
                : null,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: _logoUrl != null && _logoUrl!.isNotEmpty
              ? Image.network(_logoUrl!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(_userName.isNotEmpty ? _userName[0].toUpperCase() : 'S',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  ))
              : Center(
                  child: Text(_userName.isNotEmpty ? _userName[0].toUpperCase() : 'S',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hey,',
                  style: const TextStyle(
                      fontSize: 13,
                      color: kTextSecondary,
                      fontWeight: FontWeight.w500)),
              Text(_userName,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: kTextPrimary)),
            ],
          ),
        ),
        _CircleAction(
          icon: Icons.arrow_back_rounded,
          onTap: _goBackToHome,
        ),
      ],
    );
  }

  // ── Hero card (store overview) ────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A4BA0), Color(0xFF153075)],
        ),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded,
                  color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text("Today's Revenue",
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            '₱${_salesToday.toStringAsFixed(2)}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -1),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HeroPill(
                  icon: Icons.shopping_bag_rounded,
                  label: '$_pendingOrderCount pending'),
              const SizedBox(width: 10),
              _HeroPill(
                  icon: Icons.inventory_2_rounded,
                  label: '$_productCount products'),
            ],
          ),
        ],
      ),
    );
  }

  // ── Approval banner ───────────────────────────────────────
  Widget _buildShopStatusToggle() {
    final statusColor = _isShopOpen ? const Color(0xFF059669) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isShopOpen ? Icons.storefront_rounded : Icons.store_outlined,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isShopOpen ? 'Shop is Open' : 'Shop is Closed',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Hours: ${_formatTime12hr(_openingTime)} \u2013 ${_formatTime12hr(_closingTime)}',
                  style: const TextStyle(fontSize: 12, color: kTextSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isShopOpen,
            onChanged: _toggleShopOpen,
            activeTrackColor: const Color(0xFF059669),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryToggle() {
    const deliveryColor = Color(0xFF0891B2);
    const offColor = Color(0xFF6B7280);
    final activeColor = _deliveryEnabled ? deliveryColor : offColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.delivery_dining_rounded,
              color: activeColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _deliveryEnabled ? 'Delivery Available' : 'Delivery Unavailable',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: activeColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _deliveryEnabled
                      ? 'Buyers can request door-to-door delivery'
                      : 'Buyers can only pick up orders at your store',
                  style: const TextStyle(fontSize: 12, color: kTextSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _deliveryEnabled,
            onChanged: _toggleDelivery,
            activeTrackColor: deliveryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _approvalAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _approvalAccent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _approvalAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_approvalIcon, color: _approvalAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _approvalMessage,
              style: TextStyle(
                  color: _approvalAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick actions grid ────────────────────────────────────
  Widget _buildQuickActions() {
    final actions = [
      _QuickAction(
          icon: Icons.add_box_rounded,
          label: 'Add Product',
          color: const Color(0xFF2A4BA0),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddProductPage()))),
      _QuickAction(
          icon: Icons.receipt_long_rounded,
          label: 'Orders',
          color: const Color(0xFFF59E0B),
          badge: _pendingOrderCount,
          onTap: () => _goToTab(1)),
      _QuickAction(
          icon: Icons.bar_chart_rounded,
          label: 'Analytics',
          color: const Color(0xFF10B981),
          onTap: () => _goToTab(3)),
      _QuickAction(
          icon: Icons.inventory_2_rounded,
          label: 'Inventory',
          color: const Color(0xFF8B5CF6),
          onTap: () => _goToTab(2)),
      _QuickAction(
          icon: Icons.storefront_rounded,
          label: 'My Store',
          color: const Color(0xFF0891B2),
          onTap: () async {
            final userId =
                Supabase.instance.client.auth.currentUser?.id;
            if (userId == null) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SellerProfilePage(
                  sellerId: userId,
                  initialStoreName: _storeName,
                ),
              ),
            );
            _fetchSellerData();
          }),
      _QuickAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Messages',
          color: const Color(0xFF7C3AED),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SellerMessagesPage()))),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 3.2,
      children: actions.map((a) {
        return GestureDetector(
          onTap: a.onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: a.color.withValues(alpha: 0.18),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: a.color.withValues(alpha: 0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: a.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(a.icon, color: a.color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Notification badge
              if (a.badge != null && a.badge! > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Text(
                      a.badge! > 99 ? '99+' : '${a.badge}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Recent orders list ────────────────────────────────────
  Widget _buildRecentOrders() {
    if (_recentOrders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.inbox_rounded, size: 40, color: Color(0xFFD1D5DB)),
              SizedBox(height: 8),
              Text('No orders yet',
                  style: TextStyle(color: kTextSecondary, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: _recentOrders.asMap().entries.map((entry) {
          final order = entry.value;
          final isLast = entry.key == _recentOrders.length - 1;
          final status =
              (order['status'] ?? 'pending').toString().toLowerCase();
          final total = ((order['price'] as num?)?.toDouble() ?? 0) *
              ((order['qty'] as num?)?.toInt() ?? 1);

          Color statusColor;
          IconData statusIcon;
          switch (status) {
            case 'completed':
            case 'delivered':
              statusColor = const Color(0xFF059669);
              statusIcon = Icons.check_circle_rounded;
              break;
            case 'cancelled':
              statusColor = const Color(0xFFDC2626);
              statusIcon = Icons.cancel_rounded;
              break;
            default:
              statusColor = const Color(0xFFF59E0B);
              statusIcon = Icons.schedule_rounded;
          }

          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #${order['id'].toString().substring(0, 8)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                color: kTextPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            status[0].toUpperCase() + status.substring(1),
                            style: TextStyle(
                                fontSize: 12,
                                color: statusColor,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₱${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: kTextPrimary),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                    height: 1,
                    indent: 68,
                    color: Colors.grey.withValues(alpha: 0.12)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ── MODERN NAVIGATION BAR ─────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

class _ModernNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _ModernNavBar({required this.currentIndex, required this.onTap});

  static const _items = [
    _NavItem(icon: Icons.space_dashboard_outlined,
        activeIcon: Icons.space_dashboard_rounded, label: 'Home'),
    _NavItem(icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long_rounded, label: 'Orders'),
    _NavItem(icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2_rounded, label: 'Products'),
    _NavItem(icon: Icons.insights_rounded,
        activeIcon: Icons.insights_rounded, label: 'Analytics'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isActive = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                        vertical: 6, horizontal: isActive ? 10 : 0),
                    decoration: BoxDecoration(
                      color: isActive
                          ? kPrimary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive ? item.activeIcon : item.icon,
                          size: 24,
                          color: isActive ? kPrimary : const Color(0xFFADB5BD),
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w500,
                            color:
                                isActive ? kPrimary : const Color(0xFFADB5BD),
                          ),
                          child: Text(item.label),
                        ),
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          width: isActive ? 20 : 0,
                          height: 3,
                          decoration: BoxDecoration(
                            color: kPrimary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(
      {required this.icon, required this.activeIcon, required this.label});
}

// ═══════════════════════════════════════════════════════════════
// ── HELPER WIDGETS ────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: kTextSecondary),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 12),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kTextPrimary)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5, color: kTextSecondary)),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int? badge;
  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap,
      this.badge});
}
