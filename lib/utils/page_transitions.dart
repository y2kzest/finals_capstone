import 'package:flutter/material.dart';

/// Slide-from-right + fade transition, commonly used for forward navigation.
Route<T> fadeSlideRoute<T>(WidgetBuilder builder, {Duration duration = const Duration(milliseconds: 280)}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, _) => builder(context),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Fade transition that also scales subtly. Good for dialog-like full pages.
Route<T> fadeScaleRoute<T>(WidgetBuilder builder, {Duration duration = const Duration(milliseconds: 240)}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, _) => builder(context),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Slide-from-bottom transition for modal-style screens.
Route<T> slideUpRoute<T>(WidgetBuilder builder, {Duration duration = const Duration(milliseconds: 280)}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, _) => builder(context),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// Fade-in wrapper that animates a child as soon as it mounts.
/// Useful for staggered list/grid item appearances.
class FadeInOnMount extends StatefulWidget {
  const FadeInOnMount({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
    this.offsetY = 12,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  @override
  State<FadeInOnMount> createState() => _FadeInOnMountState();
}

class _FadeInOnMountState extends State<FadeInOnMount>
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

/// Small bounce/tap feedback animation for buttons or cards.
class TapBounce extends StatefulWidget {
  const TapBounce({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<TapBounce> createState() => _TapBounceState();
}

class _TapBounceState extends State<TapBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    lowerBound: 0,
    upperBound: 0.06,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) =>
            Transform.scale(scale: 1 - _ctrl.value, child: child),
        child: widget.child,
      ),
    );
  }
}
