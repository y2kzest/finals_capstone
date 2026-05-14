import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/market_geo.dart';
import 'seller_profile_page.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);

class _Stall {
  _Stall({
    required this.userId,
    required this.storeName,
    required this.stallNo,
    required this.isOpen,
    required this.point,
    required this.logoUrl,
  });

  final String userId;
  final String storeName;
  final String stallNo;
  final bool isOpen;
  final LatLng point;
  final String? logoUrl;

  double? distanceMetersFrom(LatLng? me) =>
      me == null ? null : distanceMeters(me, point);
}

class MarketMapPage extends StatefulWidget {
  const MarketMapPage({super.key});

  @override
  State<MarketMapPage> createState() => _MarketMapPageState();
}

class _MarketMapPageState extends State<MarketMapPage> {
  final _supabase = Supabase.instance.client;
  final _mapController = MapController();

  List<_Stall> _stalls = [];
  LatLng? _myLocation;
  bool _isLoading = true;
  bool _showOpenOnly = false;

  @override
  void initState() {
    super.initState();
    // Run both in parallel — stalls come from the DB and GPS from the OS,
    // there's no reason to wait for one before kicking off the other.
    _loadStalls();
    _tryGetLocation();
  }

  Future<void> _loadStalls() async {
    try {
      final rows = await _supabase
          .from('seller_profiles')
          .select(
              'user_id, store_name, stall_no, is_open, stall_lat, stall_lng, logo_url, approval_status')
          .not('stall_lat', 'is', null)
          .not('stall_lng', 'is', null);

      final list = <_Stall>[];
      for (final row in (rows as List)) {
        final lat = (row['stall_lat'] as num?)?.toDouble();
        final lng = (row['stall_lng'] as num?)?.toDouble();
        final status =
            row['approval_status']?.toString().toLowerCase() ?? 'approved';
        if (lat == null || lng == null) continue;
        if (status != 'approved') continue;
        list.add(_Stall(
          userId: row['user_id']?.toString() ?? '',
          storeName: row['store_name']?.toString().trim().isNotEmpty == true
              ? row['store_name'].toString()
              : 'Unnamed Stall',
          stallNo: row['stall_no']?.toString() ?? '',
          isOpen: row['is_open'] == true,
          point: LatLng(lat, lng),
          logoUrl: row['logo_url']?.toString(),
        ));
      }

      if (mounted) {
        setState(() {
          _stalls = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load stalls: $e')),
        );
      }
    }
  }

  Future<void> _tryGetLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      // Show the last known fix instantly (usually <100 ms) so distances
      // start rendering before a fresh GPS lock comes back.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          setState(() =>
              _myLocation = LatLng(last.latitude, last.longitude));
        }
      } catch (_) {}

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      // silently ignore — distance just won't be shown
    }
  }

  List<_Stall> get _visibleStalls {
    final list = _showOpenOnly
        ? _stalls.where((s) => s.isOpen).toList()
        : List<_Stall>.from(_stalls);
    list.sort((a, b) {
      final da = a.distanceMetersFrom(_myLocation) ?? double.infinity;
      final db = b.distanceMetersFrom(_myLocation) ?? double.infinity;
      return da.compareTo(db);
    });
    return list;
  }

  void _focusStall(_Stall stall) {
    _mapController.move(stall.point, 19);
    _showStallSheet(stall);
  }

  void _showStallSheet(_Stall stall) {
    final dist = stall.distanceMetersFrom(_myLocation);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFFEEF2FF),
                      backgroundImage: stall.logoUrl != null &&
                              stall.logoUrl!.isNotEmpty
                          ? NetworkImage(stall.logoUrl!)
                          : null,
                      child: stall.logoUrl == null || stall.logoUrl!.isEmpty
                          ? const Icon(Icons.storefront_rounded,
                              color: _kPrimary)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stall.storeName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          if (stall.stallNo.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                stall.stallNo,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _statusChip(stall.isOpen),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 18, color: _kPrimary),
                    const SizedBox(width: 6),
                    Text(
                      '${stall.point.latitude.toStringAsFixed(5)}, ${stall.point.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                    if (dist != null) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.directions_walk,
                          size: 18, color: _kPrimary),
                      const SizedBox(width: 4),
                      Text(
                        formatDistance(dist),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _kPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SellerProfilePage(
                                sellerId: stall.userId,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text('View Store'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kPrimary,
                          side: const BorderSide(color: _kPrimary),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final ok = await launchExternalNavigation(
                            stall.point,
                            label: stall.storeName,
                          );
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Could not open a maps app.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.navigation_rounded),
                        label: const Text('Navigate'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusChip(bool open) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: open ? const Color(0xFFE6F6EC) : const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: open ? const Color(0xFF1F9D4D) : const Color(0xFFD23B3B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            open ? 'Open' : 'Closed',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: open ? const Color(0xFF1F6F3A) : const Color(0xFFA12121),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stalls = _visibleStalls;
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kPrimary,
        elevation: 0,
        title: const Text(
          'Market Map',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
        ),
        actions: [
          IconButton(
            tooltip: _showOpenOnly ? 'Showing open only' : 'Show open only',
            icon: Icon(
              _showOpenOnly
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_outlined,
              color: _kPrimary,
            ),
            onPressed: () =>
                setState(() => _showOpenOnly = !_showOpenOnly),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.42,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: const MapOptions(
                          initialCenter: kMarketPlaza,
                          initialZoom: 18,
                          minZoom: 14,
                          maxZoom: 19,
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
                              if (_myLocation != null)
                                Marker(
                                  point: _myLocation!,
                                  width: 22,
                                  height: 22,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x55000000),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              for (final stall in stalls)
                                Marker(
                                  point: stall.point,
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.topCenter,
                                  child: GestureDetector(
                                    onTap: () => _showStallSheet(stall),
                                    child: Icon(
                                      Icons.location_on,
                                      size: 44,
                                      color: stall.isOpen
                                          ? _kPrimary
                                          : const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'mapRecenter',
                          backgroundColor: Colors.white,
                          foregroundColor: _kPrimary,
                          onPressed: () =>
                              _mapController.move(kMarketPlaza, 18),
                          child: const Icon(Icons.center_focus_strong),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        '${stalls.length} stall${stalls.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      if (_myLocation == null)
                        TextButton.icon(
                          onPressed: _tryGetLocation,
                          icon: const Icon(Icons.my_location, size: 16),
                          label: const Text('Use my location'),
                          style: TextButton.styleFrom(
                            foregroundColor: _kPrimary,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: stalls.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No stalls have shared their location yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                          itemCount: stalls.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final stall = stalls[i];
                            final dist =
                                stall.distanceMetersFrom(_myLocation);
                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _focusStall(stall),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor:
                                            const Color(0xFFEEF2FF),
                                        backgroundImage:
                                            stall.logoUrl != null &&
                                                    stall.logoUrl!.isNotEmpty
                                                ? NetworkImage(stall.logoUrl!)
                                                : null,
                                        child: stall.logoUrl == null ||
                                                stall.logoUrl!.isEmpty
                                            ? const Icon(
                                                Icons.storefront_rounded,
                                                color: _kPrimary)
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              stall.storeName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                if (stall.stallNo.isNotEmpty)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 8),
                                                    child: Text(
                                                      stall.stallNo,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            Color(0xFF6B7280),
                                                      ),
                                                    ),
                                                  ),
                                                if (dist != null)
                                                  Text(
                                                    formatDistance(dist),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: _kPrimary,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      _statusChip(stall.isOpen),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
