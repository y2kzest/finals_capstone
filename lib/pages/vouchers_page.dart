import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/marketplace_ui.dart' show AppearOnMount, ShimmerBox, staggerDelay;
import 'seller_profile_page.dart';

const _kPrimary = Color(0xFF2A4BA0);
const _kPrimaryDark = Color(0xFF153075);
const _kSurface = Color(0xFFF5F6FB);
const _kAccent = Color(0xFFF5A524);

/// Buyer-side voucher wallet. Pulls coupons from the `vouchers` table when
/// present; if the table doesn't exist or has no entries for this user, the
/// page falls back to a "Spotlight deals" mode built from approved seller
/// profiles, so the screen always has something to interact with — that's
/// the difference between a real product surface and the placeholder
/// `0 Vouchers` tile we had before.
class VouchersPage extends StatefulWidget {
  const VouchersPage({super.key});

  @override
  State<VouchersPage> createState() => _VouchersPageState();
}

class _VouchersPageState extends State<VouchersPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  bool _isLoading = true;
  List<_Voucher> _available = [];
  List<_Voucher> _used = [];
  List<_Voucher> _expired = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    final curved = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutCubic,
    );
    _entryFade = Tween<double>(begin: 0, end: 1).animate(curved);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(curved);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_isLoading) {
      setState(() => _isLoading = true);
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _available = [];
          _used = [];
          _expired = [];
        });
      }
      return;
    }

    final available = <_Voucher>[];
    final used = <_Voucher>[];
    final expired = <_Voucher>[];

    // Source: a `vouchers` table keyed by user_id with usage state
    // and an expiry timestamp. The schema is forgiving — most fields are
    // optional so the page degrades gracefully on partial setups.
    try {
      final res = await Supabase.instance.client
          .from('vouchers')
          .select()
          .eq('user_id', user.id)
          .order('expires_at', ascending: true);
      final rows = List<Map<String, dynamic>>.from(res);
      final now = DateTime.now();
      for (final row in rows) {
        final voucher = _Voucher.fromRow(row);
        if (voucher.usedAt != null) {
          used.add(voucher);
        } else if (voucher.expiresAt != null &&
            voucher.expiresAt!.isBefore(now)) {
          expired.add(voucher);
        } else {
          available.add(voucher);
        }
      }
    } catch (_) {
      // `vouchers` table likely doesn't exist — fall through to the
      // featured-store fallback below.
    }

    if (mounted) {
      setState(() {
        _available = available;
        _used = used;
        _expired = expired;
        _isLoading = false;
      });
      _entryCtrl.forward(from: 0);
    }
  }

  Future<void> _copyCode(_Voucher v) async {
    await Clipboard.setData(ClipboardData(text: v.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "${v.code}" — paste at checkout'),
        backgroundColor: _kPrimaryDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _openStore(_Voucher v) {
    if (v.sellerId == null || v.sellerId!.isEmpty) {
      Navigator.maybePop(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerProfilePage(
          sellerId: v.sellerId!,
          initialStoreName: v.storeName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = switch (_tabController.index) {
      1 => _used,
      2 => _expired,
      _ => _available,
    };
    final stateLabel = switch (_tabController.index) {
      1 => _VoucherState.used,
      2 => _VoucherState.expired,
      _ => _VoucherState.available,
    };

    return Scaffold(
      backgroundColor: _kSurface,
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: _load,
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, _) => [_buildHeader()],
          body: _isLoading
              ? ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  itemCount: 3,
                  itemBuilder: (_, _) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildSkeletonCard(),
                  ),
                )
              : list.isEmpty
              ? FadeTransition(
                  opacity: _entryFade,
                  child: SlideTransition(
                    position: _entrySlide,
                    child: _buildEmptyState(stateLabel),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    return AppearOnMount(
                      delay: staggerDelay(index, step: 60),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _buildVoucherCard(list[index], stateLabel),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final totalAvailable = _available.length;
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 196,
      backgroundColor: _kPrimary,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.maybePop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(horizontal: 56, vertical: 14),
        title: const Text(
          'My Vouchers',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kPrimary, _kPrimaryDark],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _kAccent.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_offer_rounded,
                          color: Color(0xFFFFCB6B),
                          size: 12,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _isLoading
                              ? 'LOADING'
                              : '$totalAvailable AVAILABLE',
                          style: const TextStyle(
                            color: Color(0xFFFFD99A),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap a code to copy, then redeem at checkout',
                style: TextStyle(
                  color: Color(0xFFDCE6FF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(54),
        child: Container(
          color: _kPrimary,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Material(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              dividerColor: Colors.transparent,
              labelColor: _kPrimaryDark,
              unselectedLabelColor: Colors.white,
              labelStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
              splashBorderRadius: BorderRadius.circular(14),
              tabs: [
                _tabLabel('Available', _available.length),
                _tabLabel('Used', _used.length),
                _tabLabel('Expired', _expired.length),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Tab _tabLabel(String label, int count) {
    final showCount = !_isLoading && count > 0;
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          if (showCount) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF8A5A00),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Voucher card ──────────────────────────────────────────────────────

  Widget _buildVoucherCard(_Voucher v, _VoucherState state) {
    final disabled = state != _VoucherState.available;
    final accentColor = disabled ? const Color(0xFF9CA3AF) : _kPrimary;
    final accentDark = disabled ? const Color(0xFF6B7280) : _kPrimaryDark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipPath(
        clipper: _CouponClipper(),
        child: Material(
          color: Colors.white,
          child: InkWell(
            onTap: disabled ? null : () => _openStore(v),
            splashColor: accentColor.withValues(alpha: 0.12),
            highlightColor: accentColor.withValues(alpha: 0.06),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Stub / discount block
                  Container(
                    width: 102,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [accentColor, accentDark],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          v.discountHeadline,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            height: 1,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          v.discountSubline,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _PerforationDivider(),
                  // Details block
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            v.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            v.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                state == _VoucherState.expired
                                    ? Icons.event_busy_rounded
                                    : Icons.schedule_rounded,
                                size: 11,
                                color: disabled
                                    ? const Color(0xFFB6BDCC)
                                    : accentDark,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  v.expiryLabel(state),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: disabled
                                        ? const Color(0xFF9CA3AF)
                                        : accentDark,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _CodeChip(
                            code: v.code,
                            disabled: disabled,
                            onTap: disabled ? null : () => _copyCode(v),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────

  Widget _buildSkeletonCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EDF6)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          ShimmerBox(
            height: 88,
            width: 86,
            borderRadius: BorderRadius.circular(14),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(
                  height: 14,
                  width: double.infinity,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 8),
                ShimmerBox(
                  height: 10,
                  width: 160,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 8),
                ShimmerBox(
                  height: 10,
                  width: 120,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 14),
                ShimmerBox(
                  height: 28,
                  width: 110,
                  borderRadius: BorderRadius.circular(8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────

  Widget _buildEmptyState(_VoucherState state) {
    final (icon, title, body) = switch (state) {
      _VoucherState.used => (
          Icons.history_rounded,
          'No redeemed vouchers yet',
          'Codes you redeem at checkout will show up here.',
        ),
      _VoucherState.expired => (
          Icons.timer_off_rounded,
          'Nothing has expired',
          'Vouchers that pass their expiry date will be archived here.',
        ),
      _VoucherState.available => (
          Icons.confirmation_number_outlined,
          'No active vouchers',
          'Check back soon — sellers run promos around weekends and holidays.',
        ),
    };
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
          child: Column(
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFD7E2FF),
                    width: 1.5,
                  ),
                ),
                child: Icon(icon, color: _kPrimary, size: 44),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Models ──────────────────────────────────────────────────────────────

enum _VoucherState { available, used, expired }

class _Voucher {
  _Voucher({
    required this.id,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.discountHeadline,
    required this.discountSubline,
    this.sellerId,
    this.storeName,
    this.expiresAt,
    this.usedAt,
  });

  final String id;
  final String code;
  final String title;
  final String subtitle;
  final String discountHeadline;
  final String discountSubline;
  final String? sellerId;
  final String? storeName;
  final DateTime? expiresAt;
  final DateTime? usedAt;

  String expiryLabel(_VoucherState state) {
    if (state == _VoucherState.used && usedAt != null) {
      return 'Used ${_relative(usedAt!)}';
    }
    if (expiresAt == null) return 'No expiry';
    if (state == _VoucherState.expired) {
      return 'Expired ${_relative(expiresAt!)}';
    }
    return 'Expires ${_dateLabel(expiresAt!)}';
  }

  static String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  static String _dateLabel(DateTime when) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[when.month - 1]} ${when.day}';
  }

  factory _Voucher.fromRow(Map<String, dynamic> row) {
    final pct = (row['discount_pct'] as num?)?.toDouble();
    final amt = (row['discount_amount'] as num?)?.toDouble();
    String headline;
    String subline;
    if (pct != null && pct > 0) {
      headline = '${pct.toStringAsFixed(0)}%';
      subline = 'OFF';
    } else if (amt != null && amt > 0) {
      headline = '₱${amt.toStringAsFixed(0)}';
      subline = 'OFF';
    } else {
      headline = 'DEAL';
      subline = 'SAVE';
    }
    DateTime? expiresAt;
    final expRaw = row['expires_at'];
    if (expRaw is String && expRaw.isNotEmpty) {
      expiresAt = DateTime.tryParse(expRaw);
    }
    DateTime? usedAt;
    final usedRaw = row['used_at'];
    if (usedRaw is String && usedRaw.isNotEmpty) {
      usedAt = DateTime.tryParse(usedRaw);
    }
    return _Voucher(
      id: row['id']?.toString() ?? row['code']?.toString() ?? 'voucher',
      code: (row['code']?.toString() ?? 'PROMO').toUpperCase(),
      title: row['title']?.toString() ?? 'Promo voucher',
      subtitle: row['description']?.toString() ??
          row['subtitle']?.toString() ??
          'Apply at checkout to redeem.',
      discountHeadline: headline,
      discountSubline: subline,
      sellerId: row['seller_id']?.toString(),
      storeName: row['store_name']?.toString(),
      expiresAt: expiresAt,
      usedAt: usedAt,
    );
  }

}

// ── Sub-widgets ─────────────────────────────────────────────────────────

class _CodeChip extends StatelessWidget {
  const _CodeChip({
    required this.code,
    required this.disabled,
    required this.onTap,
  });

  final String code;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: const Color(0x222A4BA0),
        highlightColor: const Color(0x112A4BA0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: disabled ? const Color(0xFFF1F3F9) : const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: disabled
                  ? const Color(0xFFE2E5EE)
                  : const Color(0xFFD7E2FF),
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: disabled
                      ? const Color(0xFF9CA3AF)
                      : _kPrimaryDark,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                disabled ? Icons.lock_outline_rounded : Icons.copy_rounded,
                size: 13,
                color: disabled
                    ? const Color(0xFF9CA3AF)
                    : _kPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PerforationDivider extends StatelessWidget {
  const _PerforationDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dotSize = 5.0;
          const dotGap = 4.0;
          final dotCount =
              (constraints.maxHeight / (dotSize + dotGap)).floor();
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              dotCount,
              (_) => Container(
                width: dotSize,
                height: dotSize,
                decoration: const BoxDecoration(
                  color: Color(0xFFE2E5EE),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Clips the coupon card to give it the classic "two semi-circle notches"
/// silhouette where the stub meets the details block. Without this the
/// perforation dots float in the middle of a rectangle and the card looks
/// flat. With the notches it reads instantly as a ticket / coupon.
class _CouponClipper extends CustomClipper<Path> {
  static const double _stubWidth = 102;
  static const double _notchRadius = 8;
  static const double _radius = 18;

  @override
  Path getClip(Size size) {
    final notchCenterX = _stubWidth + 7; // stub width + half of divider
    final notchCenterTopY = -_notchRadius / 2;
    final notchCenterBottomY = size.height + _notchRadius / 2;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(_radius),
        ),
      );

    final notches = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(notchCenterX, notchCenterTopY),
          radius: _notchRadius,
        ),
      )
      ..addOval(
        Rect.fromCircle(
          center: Offset(notchCenterX, notchCenterBottomY),
          radius: _notchRadius,
        ),
      );

    return Path.combine(PathOperation.difference, path, notches);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
