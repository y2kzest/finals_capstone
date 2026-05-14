import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';

/// A driving route from OSRM with the road geometry and ETA.
class OsrmRoute {
  const OsrmRoute({
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

/// Process-wide OSRM client: one shared HttpClient (no TLS handshake per call)
/// and a tiny in-memory cache keyed by rounded coordinates so revisits hit
/// cache even with small GPS jitter.
class OsrmRouteService {
  OsrmRouteService._();
  static final OsrmRouteService instance = OsrmRouteService._();

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 30);

  final Map<String, OsrmRoute> _cache = {};

  String _key(LatLng a, LatLng b) {
    String r(double v) => v.toStringAsFixed(4);
    return '${r(a.latitude)},${r(a.longitude)}>${r(b.latitude)},${r(b.longitude)}';
  }

  OsrmRoute? cachedRoute(LatLng from, LatLng to) => _cache[_key(from, to)];

  Future<OsrmRoute?> fetchRoute(LatLng from, LatLng to) async {
    final key = _key(from, to);
    final cached = _cache[key];
    if (cached != null) return cached;

    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${from.longitude},${from.latitude};'
      '${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final req =
          await _http.getUrl(uri).timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
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
      final result = OsrmRoute(
        points: coords,
        distanceMeters: (r['distance'] as num).toDouble(),
        durationSeconds: (r['duration'] as num).toDouble(),
      );
      if (_cache.length > 24) _cache.remove(_cache.keys.first);
      _cache[key] = result;
      return result;
    } catch (_) {
      return null;
    }
  }
}
