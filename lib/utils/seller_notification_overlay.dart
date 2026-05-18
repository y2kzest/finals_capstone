import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../seller_pages/order.dart';

class SellerNotificationOverlay extends StatefulWidget {
  const SellerNotificationOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<SellerNotificationOverlay> createState() =>
      _SellerNotificationOverlayState();
}

class _SellerNotificationOverlayState extends State<SellerNotificationOverlay>
    with TickerProviderStateMixin {
  final List<Map<String, dynamic>> _queue = [];
  Map<String, dynamic>? _current;

  late final AnimationController _cardCtrl;
  late final AnimationController _iconCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _iconScaleAnim;

  RealtimeChannel? _channel;
  Timer? _dismissTimer;
  Timer? _progressTimer;
  double _progress = 1.0;
  double _dragOffset = 0.0;

  static const _showDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();

    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
      reverseDuration: const Duration(milliseconds: 280),
    );
    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutBack));

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      ),
    );

    _scaleAnim = Tween<double>(begin: 0.84, end: 1.0).animate(
      CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutBack),
    );

    _iconScaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _iconCtrl, curve: Curves.elasticOut),
    );

    _subscribe();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _progressTimer?.cancel();
    _cardCtrl.dispose();
    _iconCtrl.dispose();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribe() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _channel = Supabase.instance.client
        .channel('seller-notif-overlay-${userId.substring(0, 8)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'seller_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'seller_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            _enqueue(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .subscribe();
  }

  void _enqueue(Map<String, dynamic> notif) {
    _queue.add(notif);
    if (_current == null) _showNext();
  }

  void _showNext() {
    if (_queue.isEmpty) {
      if (mounted) setState(() { _current = null; _dragOffset = 0; });
      return;
    }
    final next = _queue.removeAt(0);
    setState(() {
      _current = next;
      _progress = 1.0;
      _dragOffset = 0;
    });
    _cardCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _iconCtrl.forward(from: 0);
    });
    HapticFeedback.mediumImpact();
    _startAutoTimer();
  }

  void _startAutoTimer() {
    _dismissTimer?.cancel();
    _progressTimer?.cancel();
    const tickMs = 80;
    final totalTicks = _showDuration.inMilliseconds / tickMs;
    var tick = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      if (!mounted) { t.cancel(); return; }
      tick++;
      setState(() => _progress = 1.0 - (tick / totalTicks).clamp(0.0, 1.0));
    });
    _dismissTimer = Timer(_showDuration, _dismiss);
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    _progressTimer?.cancel();
    _cardCtrl.reverse().then((_) {
      if (mounted) _showNext();
    });
  }

  void _viewOrders() {
    _dismiss();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrdersPage()),
    );
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.delta.dy < 0) setState(() => _dragOffset += d.delta.dy);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragOffset < -48 || d.velocity.pixelsPerSecond.dy < -600) {
      _dismiss();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_current != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 12,
            right: 12,
            child: GestureDetector(
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: _SellerNotifCard(
                        notif: _current!,
                        progress: _progress,
                        iconAnim: _iconScaleAnim,
                        queueCount: _queue.length,
                        onDismiss: _dismiss,
                        onViewOrders: _viewOrders,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Notification card ─────────────────────────────────────────────────────────

class _SellerNotifCard extends StatelessWidget {
  const _SellerNotifCard({
    required this.notif,
    required this.progress,
    required this.iconAnim,
    required this.queueCount,
    required this.onDismiss,
    required this.onViewOrders,
  });

  final Map<String, dynamic> notif;
  final double progress;
  final Animation<double> iconAnim;
  final int queueCount;
  final VoidCallback onDismiss;
  final VoidCallback onViewOrders;

  static const _kBlue  = Color(0xFF2A4BA0);
  static const _kBlueL = Color(0xFF4F7FE8);
  static const _kGreen  = Color(0xFF059669);
  static const _kGreenL = Color(0xFF10B981);

  static Color _accent(String type) =>
      type == 'payment_received' ? _kGreen : _kBlue;

  static Color _accentLight(String type) =>
      type == 'payment_received' ? _kGreenL : _kBlueL;

  static IconData _icon(String type) =>
      type == 'payment_received'
          ? Icons.payments_rounded
          : Icons.shopping_bag_rounded;

  static bool _hasAction(String type) =>
      type == 'new_order' || type == 'payment_received';

  String _extractPaymentBadge(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('gcash')) return 'GCash';
    if (lower.contains('maya') || lower.contains('paymaya')) return 'Maya';
    return '';
  }

  String _cleanTitle(String title) => title
      .replaceAll(RegExp(r'\s*[—–-]\s*GCash Paid[!]?', caseSensitive: false), '!')
      .replaceAll(RegExp(r'\s*[—–-]\s*Maya Paid[!]?', caseSensitive: false), '!');

  @override
  Widget build(BuildContext context) {
    final type = notif['type']?.toString() ?? 'new_order';
    final rawTitle = notif['title']?.toString() ?? 'New Notification';
    final title = _cleanTitle(rawTitle);
    final body = notif['body']?.toString() ?? '';
    final accent = _accent(type);
    final accentLight = _accentLight(type);
    final badge = _extractPaymentBadge(rawTitle);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFBFCFF),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.26),
              blurRadius: 38,
              spreadRadius: -6,
              offset: const Offset(0, 12),
            ),
            const BoxShadow(
              color: Color(0x1C000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent strip
              Container(
                width: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [accent, accent.withValues(alpha: 0.22)],
                  ),
                ),
              ),

              // Main content
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 13, 6, 13),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Icon with elastic bounce
                          ScaleTransition(
                            scale: iconAnim,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [accent, accentLight],
                                ),
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.42),
                                    blurRadius: 14,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Icon(
                                _icon(type),
                                color: Colors.white,
                                size: 23,
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),

                          // Text + chips
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                    if (badge.isNotEmpty)
                                      _PaymentBadge(label: badge),
                                    if (queueCount > 0)
                                      _QueueBadge(count: queueCount),
                                  ],
                                ),
                                if (body.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF64748B),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                                if (_hasAction(type)) ...[
                                  const SizedBox(height: 9),
                                  Row(
                                    children: [
                                      _GradientChip(
                                        label: 'View Orders',
                                        accent: accent,
                                        accentLight: accentLight,
                                        onTap: onViewOrders,
                                      ),
                                      const SizedBox(width: 7),
                                      _GhostChip(
                                        label: 'Dismiss',
                                        onTap: onDismiss,
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Close
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              color: const Color(0xFF94A3B8),
                              padding: EdgeInsets.zero,
                              onPressed: onDismiss,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom draining progress strip
                    SizedBox(
                      height: 3,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(color: const Color(0xFFE2E8F0)),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [accent, accentLight],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 5, top: 1),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF059669).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF059669).withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF059669),
            size: 11,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Color(0xFF059669),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueBadge extends StatelessWidget {
  const _QueueBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4, top: 1),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '+$count',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF475569),
        ),
      ),
    );
  }
}

class _GradientChip extends StatelessWidget {
  const _GradientChip({
    required this.label,
    required this.accent,
    required this.accentLight,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final Color accentLight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [accent, accentLight]),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.36),
              blurRadius: 9,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new_rounded, size: 11, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostChip extends StatelessWidget {
  const _GhostChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}
