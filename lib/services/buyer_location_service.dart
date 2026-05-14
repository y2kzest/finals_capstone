import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cache + accessor for the signed-in buyer's saved delivery location.
///
/// Reads the buyer's default row from `delivery_addresses`; falls back to
/// the first row with `lat`/`lng` available. Cached for the session so
/// repeat reads (seller profile, product detail, map preview) don't hit
/// the database every time.
class BuyerLocationService {
  BuyerLocationService._();
  static final BuyerLocationService instance = BuyerLocationService._();

  LatLng? _cached;
  String? _cachedAddress;
  String? _cachedForUserId;
  Future<void>? _inFlight;

  LatLng? get cachedPoint => _cached;
  String? get cachedAddress => _cachedAddress;

  /// Returns the buyer's current delivery point, loading it on demand.
  /// Returns null when no saved address with coordinates exists.
  Future<LatLng?> getPoint() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    if (_cachedForUserId == userId && _cached != null) {
      return _cached;
    }

    _inFlight ??= _load(userId);
    await _inFlight;
    _inFlight = null;
    return _cached;
  }

  Future<void> _load(String userId) async {
    try {
      final rows = await Supabase.instance.client
          .from('delivery_addresses')
          .select('lat, lng, address, is_default')
          .eq('user_id', userId)
          .order('is_default', ascending: false)
          .limit(5);

      final list = (rows as List).cast<Map<String, dynamic>>();
      for (final row in list) {
        final lat = (row['lat'] as num?)?.toDouble();
        final lng = (row['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          _cached = LatLng(lat, lng);
          _cachedAddress = row['address']?.toString();
          _cachedForUserId = userId;
          return;
        }
      }
      _cached = null;
      _cachedAddress = null;
      _cachedForUserId = userId;
    } catch (e) {
      debugPrint('BuyerLocationService load failed: $e');
    }
  }

  /// Drops the cache (e.g. after the buyer edits their default address).
  void invalidate() {
    _cached = null;
    _cachedAddress = null;
    _cachedForUserId = null;
    _inFlight = null;
  }
}
