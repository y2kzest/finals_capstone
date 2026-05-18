import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile.dart';
import 'pages/home_page.dart';
import 'pages/category_page.dart';
import 'pages/buyer_messages_page.dart';
import 'pages/login_page.dart';
import 'pages/orders_page.dart';
import 'services/paymongo_service.dart';
import 'utils/buyer_notification_overlay.dart';

class Bahay extends StatelessWidget {
  const Bahay({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainNavigation();
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkSuspensionStatus();
    _handlePaymongoWebReturn();
  }

  /// On Flutter web, PayMongo redirects the user back to this app's origin
  /// with `?paymongo=success|failed`. main.dart captures the flag at startup;
  /// this method consumes it once we have a Scaffold to show feedback in.
  /// On native, [PaymongoService.pendingWebReturn] is always null — no-op.
  Future<void> _handlePaymongoWebReturn() async {
    final flag = PaymongoService.pendingWebReturn;
    if (flag == null) return;
    PaymongoService.pendingWebReturn = null;

    final orderId = await PaymongoService.instance.takePendingOrder();
    if (!mounted) return;

    if (flag == 'success') {
      // Webhook may take a moment to flip payment_status to 'paid'. Poll
      // briefly so the dialog wording matches reality.
      String status = 'pending';
      if (orderId != null) {
        status = await PaymongoService.instance.waitForPaymentResult(
          orderId,
          timeout: const Duration(seconds: 15),
        );
      }
      if (!mounted) return;

      // Clear the buyer's cart. On native, cart_page does this itself after
      // the WebView resolves — but on web the cart_page route was destroyed
      // when the browser navigated away, so we have to do it here.
      final user = _supabase.auth.currentUser;
      if (user != null) {
        try {
          await _supabase.from('cart').delete().eq('buyer_id', user.id);
        } catch (_) {
          // Non-fatal — buyer can clear manually if needed.
        }
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            status == 'paid'
                ? Icons.check_circle_rounded
                : Icons.schedule_rounded,
            color: status == 'paid'
                ? const Color(0xFF10B981)
                : const Color(0xFF2A4BA0),
            size: 56,
          ),
          title: Text(
            status == 'paid' ? 'Payment received!' : 'Payment processing',
          ),
          content: Text(
            status == 'paid'
                ? 'Your order is confirmed. View it in Orders.'
                : 'We received your payment and are confirming with the '
                      'bank. Check Orders in a moment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Continue shopping'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OrdersPage()),
                );
              },
              child: const Text('View Orders'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Payment was cancelled or declined. Your orders are saved — '
            'try again from Orders.',
          ),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _checkSuspensionStatus() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final profile = await _supabase
          .from('profiles')
          .select('status')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (profile?['status'] == 'suspended') {
        await _supabase.auth.signOut();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your account has been suspended. Please contact the administrator.',
            ),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
    } catch (_) {
      // Non-critical — if check fails, allow the user to continue
    }
  }

  // Keep only the tabs that are needed in the buyer app.
  final List<Widget> _pages = const [
    HomePage(),
    CategoryPage(),
    BuyerMessagesPage(),
    Profile(),
  ];

  final List<_NavItemData> _navItems = const [
    _NavItemData(
      label: 'Home',
      icon: Icons.home_rounded,
      activeIcon: Icons.home,
    ),
    _NavItemData(
      label: 'Categories',
      icon: Icons.grid_view_rounded,
      activeIcon: Icons.dashboard_rounded,
    ),
    _NavItemData(
      label: 'Messages',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
    ),
    _NavItemData(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person,
    ),
  ];

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BuyerNotificationOverlay(child: Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IgnorePointer(
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFEAF1FF), Color(0xFFF7FAFF)],
                    ),
                  ),
                ),
                Positioned(
                  top: -120,
                  right: -70,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2A4BA0).withValues(alpha: 0.10),
                    ),
                  ),
                ),
                Positioned(
                  top: 260,
                  left: -90,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF9B023).withValues(alpha: 0.10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey(_selectedIndex),
              child: _pages[_selectedIndex],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE7ECF7)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: List.generate(_navItems.length, (index) {
              final item = _navItems[index];
              final isActive = _selectedIndex == index;

              return Expanded(
                child: InkWell(
                  onTap: () => _onItemTapped(index),
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: isActive
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFF9B023), Color(0xFFFFC83A)],
                            )
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) {
                            return ScaleTransition(
                              scale: animation,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            );
                          },
                          child: Icon(
                            isActive ? item.activeIcon : item.icon,
                            key: ValueKey('${item.label}-$isActive'),
                            color: isActive
                                ? const Color(0xFF153075)
                                : const Color(0xFF96A0B5),
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          style: TextStyle(
                            color: isActive
                                ? const Color(0xFF153075)
                                : const Color(0xFF96A0B5),
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 12,
                          ),
                          child: Text(item.label),
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
    ));
  }
}

class _NavItemData {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _NavItemData({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}
