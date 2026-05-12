import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'market_geo.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);

class StallPoint {
  final String name;
  final LatLng point;
  const StallPoint({required this.name, required this.point});
}

/// Compact, non-interactive map that draws every vendor stall and the buyer's
/// delivery pin, with a dashed line and the total distance overlay.
/// Designed to sit inside the cart delivery sheet.
class DeliveryRoutePreview extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final hasShops = shops.isNotEmpty;
    if (!hasShops && buyer == null) {
      return _emptyState();
    }

    final allPoints = <LatLng>[
      ...shops.map((s) => s.point),
      if (buyer != null) buyer!,
    ];

    final bounds = _boundsFor(allPoints);
    final nearest = buyer == null || shops.isEmpty
        ? null
        : _nearestDistance(buyer!, shops);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: height,
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
                    if (buyer != null && shops.length == 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [shops.first.point, buyer!],
                            color: _kPrimary.withAlpha(150),
                            strokeWidth: 3,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final shop in shops)
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
                        if (buyer != null)
                          Marker(
                            point: buyer!,
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
                if (nearest != null)
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
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
                          const Icon(
                            Icons.straighten_rounded,
                            size: 14,
                            color: _kPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatDistance(nearest),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _kPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
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
              label: 'Ordering from ${shops.length} stall${shops.length == 1 ? '' : 's'}',
            ),
            const SizedBox(width: 6),
            if (buyer != null)
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
          ],
        ),
      ],
    );
  }

  Widget _emptyState() => Container(
        height: height,
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
      // small box around the single point so flutter_map doesn't crash
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
