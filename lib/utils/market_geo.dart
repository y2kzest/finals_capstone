import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Default centre for the map: San Fernando Market Plaza, San Fernando, Pampanga.
/// Plus Code 2MHV+JC2 (https://plus.codes/7Q222MHV+JC2). Adjust if the
/// pin sits slightly off in your build — vendor pins override this anyway.
const LatLng kMarketPlaza = LatLng(15.0341, 120.6855);

/// Returns the great-circle distance in metres between two points.
double distanceMeters(LatLng a, LatLng b) {
  const earthRadius = 6371000.0;
  final dLat = _deg2rad(b.latitude - a.latitude);
  final dLng = _deg2rad(b.longitude - a.longitude);
  final lat1 = _deg2rad(a.latitude);
  final lat2 = _deg2rad(b.latitude);

  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(lat1) * math.cos(lat2);
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return earthRadius * c;
}

double _deg2rad(double deg) => deg * math.pi / 180;

/// Friendly formatter — "120 m" under 1 km, "2.3 km" beyond.
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// Opens the destination in the device's preferred maps app.
/// Tries `geo:` first (Android), then falls back to Google Maps web URL.
Future<bool> launchExternalNavigation(
  LatLng dest, {
  String? label,
}) async {
  final encodedLabel =
      label == null ? '' : '(${Uri.encodeComponent(label)})';
  final geoUri = Uri.parse(
    'geo:${dest.latitude},${dest.longitude}?q=${dest.latitude},${dest.longitude}$encodedLabel',
  );
  try {
    if (await canLaunchUrl(geoUri)) {
      return launchUrl(geoUri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    debugPrint('geo: launch failed: $e');
  }

  final webUri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}',
  );
  return launchUrl(webUri, mode: LaunchMode.externalApplication);
}
