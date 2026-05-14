import 'dart:async';
import 'dart:ui' as ui;

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

class _MarketMapPageState extends State<MarketMapPage>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _mapController = MapController();

  StreamSubscription<Position>? _posSub;
  RealtimeChannel? _stallsChannel;

  // Animation controllers for smooth map transitions and the pulsing
  // "you are here" indicator.
  late final AnimationController _pulseCtrl;
  AnimationController? _moveCtrl;

  List<_Stall> _stalls = [];
  LatLng? _myLocation;
  double? _myAccuracyMeters;
  bool _isLoading = true;
  bool _showOpenOnly = false;
  bool _followMe = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _loadStalls();
    _startLocationStream();
    _subscribeToStallChanges();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _moveCtrl?.dispose();
    _pulseCtrl.dispose();
    if (_stallsChannel != null) {
      _supabase.removeChannel(_stallsChannel!);
    }
    super.dispose();
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

  // Push live edits from sellers (toggling open/closed, moving their stall
  // pin) into the map without forcing a manual refresh.
  void _subscribeToStallChanges() {
    _stallsChannel = _supabase
        .channel('public:seller_profiles:map')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'seller_profiles',
          callback: (_) => _loadStalls(),
        )
        .subscribe();
  }

  Future<void> _startLocationStream() async {
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

      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          setState(() {
            _myLocation = LatLng(last.latitude, last.longitude);
            _myAccuracyMeters = last.accuracy;
          });
        }
      } catch (_) {}

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen((pos) {
        if (!mounted) return;
        setState(() {
          _myLocation = LatLng(pos.latitude, pos.longitude);
          _myAccuracyMeters = pos.accuracy;
        });
        if (_followMe) {
          _animatedMove(_myLocation!, _mapController.camera.zoom);
        }
      });
    } catch (_) {}
  }

  // Tween the map camera so panning to a stall (or recentering) feels
  // smooth instead of teleporting.
  void _animatedMove(LatLng dest, double zoom) {
    _moveCtrl?.stop();
    _moveCtrl?.dispose();

    final start = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;
    _moveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    final curve = CurvedAnimation(
      parent: _moveCtrl!,
      curve: Curves.easeInOutCubic,
    );
    curve.addListener(() {
      final t = curve.value;
      final lat = start.latitude + (dest.latitude - start.latitude) * t;
      final lng = start.longitude + (dest.longitude - start.longitude) * t;
      final z = startZoom + (zoom - startZoom) * t;
      _mapController.move(LatLng(lat, lng), z);
    });
    _moveCtrl!.forward();
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
    setState(() => _followMe = false);
    _animatedMove(stall.point, 19);
    _showStallSheet(stall);
  }

  void _toggleFollowMe() {
    if (_myLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for your location…')),
      );
      return;
    }
    setState(() => _followMe = !_followMe);
    if (_followMe) {
      _animatedMove(_myLocation!, 19);
    }
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

  Widget _buildStallMarker(_Stall stall) {
    return GestureDetector(
      onTap: () => _focusStall(stall),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: stall.isOpen
                    ? _kPrimary
                    : const Color(0xFF9CA3AF),
                width: 2.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(2),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFFEEF2FF),
              backgroundImage:
                  stall.logoUrl != null && stall.logoUrl!.isNotEmpty
                      ? NetworkImage(stall.logoUrl!)
                      : null,
              child: stall.logoUrl == null || stall.logoUrl!.isEmpty
                  ? const Icon(Icons.storefront_rounded,
                      color: _kPrimary, size: 16)
                  : null,
            ),
          ),
          // Triangular tail anchors the marker to the geographic point.
          CustomPaint(
            size: const Size(10, 6),
            painter: _MarkerTailPainter(
              color: stall.isOpen ? _kPrimary : const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyLocationMarker() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final t = _pulseCtrl.value;
        final outer = 14 + t * 22;
        final opacity = (1 - t).clamp(0.0, 1.0);
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: opacity * 0.5,
              child: Container(
                width: outer,
                height: outer,
                decoration: const BoxDecoration(
                  color: Color(0xFF2A4BA0),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: const Color(0xFF2A4BA0),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stalls = _visibleStalls;
    final openCount = _stalls.where((s) => s.isOpen).length;
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
                  height: MediaQuery.of(context).size.height * 0.46,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: kMarketPlaza,
                          initialZoom: 18,
                          minZoom: 14,
                          maxZoom: 19,
                          // Any manual gesture should stop the camera from
                          // sticking to the user's GPS.
                          onPositionChanged: (pos, hasGesture) {
                            if (hasGesture && _followMe) {
                              setState(() => _followMe = false);
                            }
                          },
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.caps_finals',
                            maxNativeZoom: 19,
                            tileProvider: NetworkTileProvider(),
                            retinaMode: true,
                          ),
                          if (_myLocation != null && _myAccuracyMeters != null)
                            CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: _myLocation!,
                                  // Accuracy is in meters — flutter_map renders
                                  // this as a real geo-accurate disc.
                                  radius: _myAccuracyMeters!,
                                  useRadiusInMeter: true,
                                  color: const Color(0x222A4BA0),
                                  borderColor: const Color(0x882A4BA0),
                                  borderStrokeWidth: 1.2,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              for (final stall in stalls)
                                Marker(
                                  key: ValueKey(stall.userId),
                                  point: stall.point,
                                  width: 44,
                                  height: 50,
                                  alignment: Alignment.topCenter,
                                  child: _buildStallMarker(stall),
                                ),
                              if (_myLocation != null)
                                Marker(
                                  point: _myLocation!,
                                  width: 60,
                                  height: 60,
                                  child: _buildMyLocationMarker(),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'mapFollow',
                              backgroundColor: _followMe
                                  ? _kPrimary
                                  : Colors.white,
                              foregroundColor: _followMe
                                  ? Colors.white
                                  : _kPrimary,
                              onPressed: _toggleFollowMe,
                              elevation: 4,
                              child: Icon(_followMe
                                  ? Icons.my_location
                                  : Icons.location_searching),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: 'mapRecenter',
                              backgroundColor: Colors.white,
                              foregroundColor: _kPrimary,
                              elevation: 4,
                              onPressed: () {
                                setState(() => _followMe = false);
                                _animatedMove(kMarketPlaza, 18);
                              },
                              child: const Icon(Icons.center_focus_strong),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _legendPill(openCount, _stalls.length),
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
                          onPressed: _startLocationStream,
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

  Widget _legendPill(int open, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF1F9D4D),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$open open · $total stalls',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkerTailPainter extends CustomPainter {
  _MarkerTailPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MarkerTailPainter old) =>
      old.color != color;
}
