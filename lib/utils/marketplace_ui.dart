import 'package:flutter/material.dart';
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
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(fade);
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.988 : (_hovered ? 1.01 : 1.0);
    final translateY = _pressed ? 2.0 : (_hovered ? -4.0 : 0.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          transform: Matrix4.translationValues(0, translateY, 0),
          child: Material(
            color: Colors.transparent,
            borderRadius: widget.borderRadius,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: widget.borderRadius,
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