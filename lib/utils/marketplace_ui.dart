import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class MarketplaceUi {
  static const Color primary = Color(0xFF24439B);
  static const Color primaryDark = Color(0xFF132A63);
  static const Color accent = Color(0xFF0EA5A4);
  static const Color surface = Color(0xFFF4F7FB);
  static const Color card = Colors.white;
  static const Color line = Color(0xFFE3EAF4);
  static const Color textStrong = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF667085);
  static const Color textSubtle = Color(0xFF94A3B8);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);

  static LinearGradient get heroGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );

  static BorderRadius get radiusLg => BorderRadius.circular(22);
  static BorderRadius get radiusXl => BorderRadius.circular(28);

  static EdgeInsets pagePadding(
    BuildContext context, {
    double top = 0,
    double bottom = 24,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 360 ? 14.0 : width < 420 ? 16.0 : 20.0;
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }

  /// Returns a sensible cross-axis count for a product grid based on the
  /// available width. Keeps cards from getting unreadably narrow on large
  /// phones / tablets / desktop browsers.
  static int gridCrossAxisCount(double maxWidth, {double targetCardWidth = 190}) {
    if (maxWidth <= 0) return 2;
    final count = (maxWidth / targetCardWidth).floor();
    if (count < 2) return 2;
    if (count > 5) return 5;
    return count;
  }

  /// Helper that picks one of several values based on screen width.
  /// Lets callers fluently scale type/spacing without re-writing the same
  /// breakpoint ladder in every widget.
  static T responsiveValue<T>(
    BuildContext context, {
    required T base,
    T? small,
    T? medium,
    T? large,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360 && small != null) return small;
    if (width >= 600 && large != null) return large;
    if (width >= 420 && medium != null) return medium;
    return base;
  }

  static BoxDecoration panel({
    Color color = card,
    BorderRadius? radius,
    bool highlighted = false,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: radius ?? radiusLg,
      border: Border.all(
        color: highlighted ? primary.withValues(alpha: 0.18) : line,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x140F172A),
          blurRadius: 18,
          offset: Offset(0, 10),
        ),
      ],
    );
  }

  static TextTheme textTheme(TextTheme base) {
    final themed = GoogleFonts.manropeTextTheme(base);
    return themed.copyWith(
      displayLarge: themed.displayLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: textStrong,
      ),
      displayMedium: themed.displayMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: textStrong,
      ),
      headlineLarge: themed.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: textStrong,
      ),
      headlineMedium: themed.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: textStrong,
      ),
      titleLarge: themed.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: textStrong,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: textStrong,
      ),
      bodyLarge: themed.bodyLarge?.copyWith(color: textMuted),
      bodyMedium: themed.bodyMedium?.copyWith(color: textMuted),
      bodySmall: themed.bodySmall?.copyWith(color: textSubtle),
      labelLarge: themed.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      labelMedium: themed.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      labelSmall: themed.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

Route<T> buildMarketplaceRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final secondaryCurved = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.05),
        end: Offset.zero,
      ).animate(curved);
      // The outgoing screen drifts upward slightly and fades a touch, which
      // gives the layered marketplace feel rather than a flat replace.
      final outgoingSlide = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(0, -0.025),
      ).animate(secondaryCurved);
      final outgoingFade = Tween<double>(begin: 1, end: 0.92).animate(
        secondaryCurved,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: slide,
          child: SlideTransition(
            position: outgoingSlide,
            child: FadeTransition(opacity: outgoingFade, child: child),
          ),
        ),
      );
    },
  );
}

/// Tap feedback configuration applied to the pressable card primitives.
class PressableTapStyle {
  const PressableTapStyle({
    this.haptic = true,
    this.scale = 0.985,
    this.hoverScale = 1.01,
    this.lift = 4.0,
  });

  /// Triggers a light selection click on tap-down — small, polished feedback
  /// that gives the marketplace a more "production-ready" tactile feel
  /// without being noisy.
  final bool haptic;
  final double scale;
  final double hoverScale;
  final double lift;
}

class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final PressableTapStyle style;

  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.style = const PressableTapStyle(),
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale =
        _pressed ? widget.style.scale : (_hovered ? widget.style.hoverScale : 1.0);
    final translateY =
        _pressed ? 2.0 : (_hovered ? -widget.style.lift : 0.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: scale,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, translateY, 0),
          child: Material(
            color: Colors.transparent,
            borderRadius: widget.borderRadius,
            child: InkWell(
              onTap: widget.onTap == null
                  ? null
                  : () {
                      if (widget.style.haptic) {
                        HapticFeedback.selectionClick();
                      }
                      widget.onTap!();
                    },
              onLongPress: widget.onLongPress,
              borderRadius: widget.borderRadius,
              splashColor: MarketplaceUi.primary.withValues(alpha: 0.08),
              highlightColor: MarketplaceUi.primary.withValues(alpha: 0.04),
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Light-weight shimmer loader used as a placeholder for cards and tiles
/// while remote data is being fetched. Looks much nicer than a single
/// spinner and makes loading states feel intentional rather than blank.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.baseColor = const Color(0xFFE9EEF7),
    this.highlightColor = const Color(0xFFF6F8FC),
  });

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Color baseColor;
  final Color highlightColor;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(14);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final t = _ctrl.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + t * 2, -0.3),
              end: Alignment(1.0 + t * 2, 0.3),
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// Fades children in with a subtle vertical drift the moment they mount.
/// Use [delay] to stagger sibling items in a list/grid.
class AppearOnMount extends StatefulWidget {
  const AppearOnMount({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 360),
    this.offsetY = 14,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  @override
  State<AppearOnMount> createState() => _AppearOnMountState();
}

class _AppearOnMountState extends State<AppearOnMount>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _fade = Tween<double>(begin: 0, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY / 100),
      end: Offset.zero,
    ).animate(curved);
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Convenience helper to produce a staggered fade-in delay for the n-th item
/// in a list/grid. Caps the delay so very long lists don't end up with the
/// last items taking forever to appear.
Duration staggerDelay(int index, {int step = 45, int maxMs = 360}) {
  final ms = (index * step).clamp(0, maxMs);
  return Duration(milliseconds: ms);
}
