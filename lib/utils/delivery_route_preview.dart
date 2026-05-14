import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/osrm_route_service.dart';
import 'market_geo.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);
const Color _kRouteBlue = Color(0xFF1A73E8);

class StallPoint {
  final String name;
  final LatLng point;
  const StallPoint({required this.name, required this.point});
}

/// Compact, non-interactive map that draws every vendor stall and the buyer's
/// delivery pin. When there's exactly one shop and one buyer pin, this
/// fetches a real road route from OSRM and renders the navigation polyline
/// (the straight-line dashed fallback is only used while the route is
/// loading or if the OSRM call fails).
class DeliveryRoutePreview extends StatefulWidget {
  const DeliveryRoutePreview({
    super.key,
    required this.shops,
    this.buyer,
    this.height = 160,
  });

  final List<StallPoint> shops;
  final LatLng? buyer;
  final double height;

  @override
  State<DeliveryRoutePreview> createState() => _DeliveryRoutePreviewState();
}

class _DeliveryRoutePreviewState extends State<DeliveryRoutePreview> {
  OsrmRoute? _route;
  bool _routeFailed = false;

  bool get _canRoute =>
      widget.buyer != null && widget.shops.length == 1;

  @override
  void initState() {
    super.initState();
    _maybeFetchRoute();
  }

  @override
  void didUpdateWidget(covariant DeliveryRoutePreview old) {
    super.didUpdateWidget(old);
    final movedBuyer = old.buyer != widget.buyer;
    final movedShop = old.shops.length != widget.shops.length ||
        (widget.shops.isNotEmpty &&
            old.shops.isNotEmpty &&
            old.shops.first.point != widget.shops.first.point);
    if (movedBuyer || movedShop) {
      _route = null;
      _routeFailed = false;
      _maybeFetchRoute();
    }
  }

  Future<void> _maybeFetchRoute() async {
    if (!_canRoute) return;
    final from = widget.shops.first.point;
    final to = widget.buyer!;

    // If we already have this route cached, paint it on the very first
    // frame — no spinner, no flicker.
    final cached = OsrmRouteService.instance.cachedRoute(from, to);
    if (cached != null) {
      _route = cached;
      _routeFailed = false;
      if (mounted) setState(() {});
      return;
    }

    final fresh = await OsrmRouteService.instance.fetchRoute(from, to);
    if (!mounted) return;
    setState(() {
      _route = fresh;
      _routeFailed = fresh == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasShops = widget.shops.isNotEmpty;
    if (!hasShops && widget.buyer == null) {
      return _emptyState();
    }

    final allPoints = <LatLng>[
      ...widget.shops.map((s) => s.point),
      if (widget.buyer != null) widget.buyer!,
      if (_route != null) ..._route!.points,
    ];

    final bounds = _boundsFor(allPoints);
    final routePoints = _route?.points;
    final showStraightFallback = _canRoute && routePoints == null;
    final distanceLabel = _route?.distanceLabel ??
        (widget.buyer != null && widget.shops.isNotEmpty
            ? formatDistance(_nearestDistance(widget.buyer!, widget.shops))
            : null);
    final durationLabel = _route?.durationLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(28),
                      maxZoom: 18,
                    ),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.caps_finals',
                      maxNativeZoom: 19,
                    ),
                    // Dashed fallback while OSRM is loading (or if it fails).
                    if (showStraightFallback)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [
                              widget.shops.first.point,
                              widget.buyer!,
                            ],
                            color: _kPrimary.withAlpha(150),
                            strokeWidth: 3,
                            pattern: StrokePattern.dashed(
                              segments: const [8, 6],
                            ),
                          ),
                        ],
                      ),
                    // Real road route.
                    if (routePoints != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePoints,
                            strokeWidth: 5,
                            color: _kRouteBlue,
                            borderStrokeWidth: 2,
                            borderColor: Colors.white.withValues(alpha: 0.35),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final shop in widget.shops)
                          Marker(
                            point: shop.point,
                            width: 36,
                            height: 36,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.storefront_rounded,
                              color: _kPrimary,
                              size: 30,
                              shadows: [
                                Shadow(
                                  color: Color(0x66000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        if (widget.buyer != null)
                          Marker(
                            point: widget.buyer!,
                            width: 36,
                            height: 36,
                            alignment: Alignment.topCenter,
                            child: const Icon(
                              Icons.location_on,
                              color: Color(0xFFE53935),
                              size: 36,
                              shadows: [
                                Shadow(
                                  color: Color(0x66000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (distanceLabel != null)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Container(
                        key: ValueKey(
                          '${distanceLabel}_${durationLabel ?? ''}',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              durationLabel != null
                                  ? Icons.directions_car_rounded
                                  : Icons.straighten_rounded,
                              size: 14,
                              color: durationLabel != null
                                  ? _kRouteBlue
                                  : _kPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              durationLabel != null
                                  ? '$durationLabel · $distanceLabel'
                                  : distanceLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: durationLabel != null
                                    ? _kRouteBlue
                                    : _kPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (showStraightFallback)
                  const Positioned(
                    right: 10,
                    top: 10,
                    child: _RoutingChip(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _legendChip(
              icon: Icons.storefront_rounded,
              color: _kPrimary,
              label:
                  'Ordering from ${widget.shops.length} stall${widget.shops.length == 1 ? '' : 's'}',
            ),
            const SizedBox(width: 6),
            if (widget.buyer != null)
              _legendChip(
                icon: Icons.location_on,
                color: const Color(0xFFE53935),
                label: 'Your address',
              )
            else
              _legendChip(
                icon: Icons.location_off_outlined,
                color: const Color(0xFF9CA3AF),
                label: 'No pin on this address',
              ),
            if (_routeFailed) ...[
              const SizedBox(width: 6),
              _legendChip(
                icon: Icons.wifi_off_rounded,
                color: const Color(0xFFB45309),
                label: 'Road route unavailable',
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _emptyState() => Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Text(
            'No locations to preview',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
        ),
      );

  Widget _legendChip({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static LatLngBounds _boundsFor(List<LatLng> points) {
    if (points.length == 1) {
      final p = points.first;
      return LatLngBounds(
        LatLng(p.latitude - 0.001, p.longitude - 0.001),
        LatLng(p.latitude + 0.001, p.longitude + 0.001),
      );
    }
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  static double _nearestDistance(LatLng buyer, List<StallPoint> shops) {
    var best = double.infinity;
    for (final s in shops) {
      final d = distanceMeters(buyer, s.point);
      if (d < best) best = d;
    }
    return best;
  }
}

/// Tiny pulsing pill shown in the corner while the road route is fetched.
class _RoutingChip extends StatelessWidget {
  const _RoutingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: _kRouteBlue,
            ),
          ),
          SizedBox(width: 6),
          Text(
            'Routing…',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _kRouteBlue,
            ),
          ),
        ],
      ),
    );
  }
}
