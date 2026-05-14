import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/buyer_location_service.dart';
import 'market_geo.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kPrimaryDark = Color(0xFF153075);
const Color _kRouteBlue = Color(0xFF1A73E8);

// ─────────────────────────────────────────────────────────────────────────────
// OSRM road-routing helpers
// ─────────────────────────────────────────────────────────────────────────────

class _RouteResult {
  const _RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  String get durationLabel {
    final mins = (durationSeconds / 60).round();
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String get distanceLabel {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
}

Future<_RouteResult?> _callOsrm(LatLng from, LatLng to) async {
  final uri = Uri.parse(
    'https://router.project-osrm.org/route/v1/driving/'
    '${from.longitude},${from.latitude};'
    '${to.longitude},${to.latitude}'
    '?overview=full&geometries=geojson',
  );
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 12));
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final r = routes[0] as Map<String, dynamic>;
    final geo = r['geometry'] as Map<String, dynamic>;
    final coords = (geo['coordinates'] as List)
        .map(
          (c) => LatLng(
            (c[1] as num).toDouble(),
            (c[0] as num).toDouble(),
          ),
        )
        .toList();
    return _RouteResult(
      points: coords,
      distanceMeters: (r['distance'] as num).toDouble(),
      durationSeconds: (r['duration'] as num).toDouble(),
    );
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StoreMapPreview  (small non-interactive thumbnail)
// ─────────────────────────────────────────────────────────────────────────────

/// Small non-interactive map thumbnail. Tapping opens [StoreMapFullScreen].
class StoreMapPreview extends StatelessWidget {
  const StoreMapPreview({
    super.key,
    required this.lat,
    required this.lng,
    this.address,
    this.storeName,
    this.height = 140,
  });

  final double lat;
  final double lng;
  final String? address;
  final String? storeName;
  final double height;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lng);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: AbsorbPointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 17,
                  minZoom: 5,
                  maxZoom: 19,
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
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 44,
                        height: 44,
                        alignment: Alignment.topCenter,
                        child: const Icon(
                          Icons.location_on,
                          color: _kPrimary,
                          size: 38,
                          shadows: [
                            Shadow(
                              color: Color(0x66000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_out_map_rounded,
                      size: 12, color: _kPrimary),
                  SizedBox(width: 4),
                  Text(
                    'Tap to expand',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: _kPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place_rounded,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      (address?.isNotEmpty == true)
                          ? address!
                          : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 280),
                    pageBuilder: (ctx, anim, _) => FadeTransition(
                      opacity: anim,
                      child: StoreMapFullScreen(
                        lat: lat,
                        lng: lng,
                        address: address,
                        storeName: storeName,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StoreMapFullScreen  (Google Maps-style routing experience)
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen interactive map with real road routing via OSRM,
/// drive time, road distance, and an "Open in Maps" button.
class StoreMapFullScreen extends StatefulWidget {
  const StoreMapFullScreen({
    super.key,
    required this.lat,
    required this.lng,
    this.address,
    this.storeName,
  });

  final double lat;
  final double lng;
  final String? address;
  final String? storeName;

  @override
  State<StoreMapFullScreen> createState() => _StoreMapFullScreenState();
}

class _StoreMapFullScreenState extends State<StoreMapFullScreen> {
  final _mapController = MapController();

  LatLng? _buyerPoint;
  bool _isLocating = false;

  // Route state
  bool _routeVisible = false;
  bool _isFetchingRoute = false;
  _RouteResult? _routeResult;
  bool _routeFailed = false;

  bool _opening = false;

  LatLng get _store => LatLng(widget.lat, widget.lng);

  @override
  void initState() {
    super.initState();
    _loadBuyerPoint();
  }

  Future<void> _loadBuyerPoint() async {
    final p = await BuyerLocationService.instance.getPoint();
    if (!mounted) return;
    setState(() => _buyerPoint = p);
    // Auto-show route as soon as buyer location is available (like Google Maps)
    if (p != null) _showRoute();
  }

  Future<void> _showRoute() async {
    if (_buyerPoint == null) return;
    setState(() {
      _routeVisible = true;
      _isFetchingRoute = true;
      _routeResult = null;
      _routeFailed = false;
    });
    _fitBothPoints();
    final result = await _callOsrm(_buyerPoint!, _store);
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _isFetchingRoute = false;
        _routeFailed = true;
      });
      _snack('Route unavailable — check your connection.');
    } else {
      setState(() {
        _routeResult = result;
        _isFetchingRoute = false;
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _snack('Turn on device location to use GPS.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Location permission denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final next = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _buyerPoint = next;
        _routeResult = null;
        _routeFailed = false;
      });
      _showRoute();
    } catch (e) {
      _snack('Could not get location: $e');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _fitBothPoints() {
    if (_buyerPoint == null) return;
    final bounds = LatLngBounds.fromPoints([_store, _buyerPoint!]);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(60, 120, 60, 240),
      ),
    );
  }

  void _recenterOnStore() => _mapController.move(_store, 18);

  Future<void> _openDirections() async {
    setState(() => _opening = true);
    try {
      final ok =
          await launchExternalNavigation(_store, label: widget.storeName);
      if (!ok && mounted) _snack('Could not open a maps app.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasBuyer = _buyerPoint != null;
    final straightDist =
        hasBuyer ? distanceMeters(_buyerPoint!, _store) : null;
    final routePoints = _routeResult?.points;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _store,
              initialZoom: 18,
              minZoom: 5,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.caps_finals',
                maxNativeZoom: 19,
              ),
              // Dashed fallback line shown while OSRM is loading
              if (_routeVisible && _buyerPoint != null && routePoints == null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_buyerPoint!, _store],
                      strokeWidth: 3,
                      color: _kPrimary.withValues(alpha: 0.5),
                      pattern:
                          StrokePattern.dashed(segments: const [8, 6]),
                    ),
                  ],
                ),
              // Actual road route polyline
              if (routePoints != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePoints,
                      strokeWidth: 6,
                      color: _kRouteBlue,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white.withValues(alpha: 0.35),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Buyer location dot
                  if (_routeVisible && _buyerPoint != null)
                    Marker(
                      point: _buyerPoint!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border:
                              Border.all(color: _kRouteBlue, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x44000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.person_pin_circle_rounded,
                            color: _kRouteBlue,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  // Store pin
                  Marker(
                    point: _store,
                    width: 56,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on,
                      color: _kPrimary,
                      size: 50,
                      shadows: [
                        Shadow(
                          color: Color(0x66000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Top bar ──────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _circleBtn(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.storeName?.isNotEmpty == true
                                ? widget.storeName!
                                : 'Store Location',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          if (widget.address?.isNotEmpty == true) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.address!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Floating side controls ────────────────────────────────────
          Positioned(
            right: 14,
            bottom: 210,
            child: Column(
              children: [
                _circleBtn(
                  icon: Icons.center_focus_strong_rounded,
                  tooltip: 'Recenter on store',
                  onTap: _recenterOnStore,
                ),
                const SizedBox(height: 10),
                _circleBtn(
                  icon: _isLocating
                      ? Icons.hourglass_top_rounded
                      : Icons.my_location_rounded,
                  tooltip: 'Use my current location',
                  onTap: _isLocating ? null : _useCurrentLocation,
                ),
                if (hasBuyer) ...[
                  const SizedBox(height: 10),
                  _circleBtn(
                    icon: _isFetchingRoute
                        ? Icons.hourglass_top_rounded
                        : Icons.refresh_rounded,
                    tooltip: 'Recalculate route',
                    background: _kPrimary,
                    foreground: Colors.white,
                    onTap: (_isFetchingRoute || _isLocating)
                        ? null
                        : _showRoute,
                  ),
                ],
              ],
            ),
          ),

          // ── Bottom panel (Google Maps-style) ──────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(hasBuyer, straightDist),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom info panel
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBottomPanel(bool hasBuyer, double? straightDist) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon badge
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      key: ValueKey(_isFetchingRoute
                          ? 'loading'
                          : _routeResult != null
                              ? 'route'
                              : 'pin'),
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _isFetchingRoute
                            ? _kRouteBlue.withValues(alpha: 0.10)
                            : _routeResult != null
                                ? _kRouteBlue.withValues(alpha: 0.10)
                                : _kPrimary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: _isFetchingRoute
                          ? const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: _kRouteBlue,
                                ),
                              ),
                            )
                          : Icon(
                              _routeResult != null
                                  ? Icons.directions_car_rounded
                                  : Icons.place_rounded,
                              color: _routeResult != null
                                  ? _kRouteBlue
                                  : _kPrimary,
                              size: 26,
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Route text
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _buildRouteText(hasBuyer, straightDist),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Go / Directions button
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _opening ? null : _openDirections,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kRouteBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        elevation: 0,
                      ),
                      icon: _opening
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.navigation_rounded, size: 18),
                      label: const Text(
                        'Go',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteText(bool hasBuyer, double? straightDist) {
    // Route successfully loaded
    if (_routeResult != null) {
      return Column(
        key: const ValueKey('result'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _routeResult!.durationLabel,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _kPrimaryDark,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _routeResult!.distanceLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Fastest route · by road',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      );
    }

    // Route fetch in progress
    if (_isFetchingRoute) {
      return const Column(
        key: ValueKey('loading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Getting route…',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _kRouteBlue,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'Calculating fastest road route',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      );
    }

    // Route fetch failed — fall back to straight-line distance
    if (_routeFailed && straightDist != null) {
      return Column(
        key: const ValueKey('failed'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatDistance(straightDist),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _kPrimaryDark,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'away',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Road route unavailable · straight-line',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFFDC2626),
            ),
          ),
        ],
      );
    }

    // Buyer location exists but route not yet requested
    if (hasBuyer && straightDist != null) {
      return Column(
        key: const ValueKey('distance'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatDistance(straightDist),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: _kPrimaryDark,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'away',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Loading road route…',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      );
    }

    // No buyer location at all
    return Column(
      key: const ValueKey('none'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.storeName?.isNotEmpty == true
              ? widget.storeName!
              : 'Store Location',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _kPrimaryDark,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Add a delivery address to see route',
          style: TextStyle(
            fontSize: 11.5,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Floating circular button
  // ─────────────────────────────────────────────────────────────────────────

  Widget _circleBtn({
    required IconData icon,
    VoidCallback? onTap,
    String? tooltip,
    Color background = Colors.white,
    Color foreground = _kPrimary,
  }) {
    final btn = Material(
      color: background,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: foreground, size: 22),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }
}
