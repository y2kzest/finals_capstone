import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/buyer_location_service.dart';
import 'market_geo.dart';

/// Pill badge that shows the distance from the buyer's saved default
/// address to a given store point. Reads from [BuyerLocationService]
/// (cached) and quietly disappears when no buyer location is on file.
class DistanceBadge extends StatefulWidget {
  const DistanceBadge({
    super.key,
    required this.storeLat,
    required this.storeLng,
    this.compact = false,
    this.foreground = const Color(0xFF2A4BA0),
    this.background = const Color(0xFFEEF2FF),
  });

  final double storeLat;
  final double storeLng;
  final bool compact;
  final Color foreground;
  final Color background;

  @override
  State<DistanceBadge> createState() => _DistanceBadgeState();
}

class _DistanceBadgeState extends State<DistanceBadge> {
  double? _meters;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DistanceBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeLat != widget.storeLat ||
        oldWidget.storeLng != widget.storeLng) {
      _load();
    }
  }

  Future<void> _load() async {
    final buyerPoint = await BuyerLocationService.instance.getPoint();
    if (!mounted) return;
    if (buyerPoint == null) {
      setState(() => _meters = null);
      return;
    }
    final dist = distanceMeters(
      buyerPoint,
      LatLng(widget.storeLat, widget.storeLng),
    );
    if (!mounted) return;
    setState(() => _meters = dist);
  }

  @override
  Widget build(BuildContext context) {
    if (_meters == null) return const SizedBox.shrink();
    final text = '${formatDistance(_meters!)} away';
    final padding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 5);
    final iconSize = widget.compact ? 12.0 : 13.0;
    final fontSize = widget.compact ? 10.5 : 11.5;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: padding,
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me_rounded, size: iconSize, color: widget.foreground),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: widget.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
