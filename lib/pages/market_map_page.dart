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
  int productCount = 0;

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
  bool _isSatellite = false;
  bool _followMe = false;
  // True once we've animated to the user's first GPS fix. Prevents the
  // camera from snapping back every time the stream fires.
  bool _hasAutoCentered = false;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final DraggableScrollableController _sheetCtrl = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _searchCtrl.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchCtrl.text.toLowerCase().trim());
    });

    _loadStalls();
    _startLocationStream();
    _subscribeToStallChanges();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _moveCtrl?.dispose();
    _pulseCtrl.dispose();
    _searchCtrl.dispose();
    _sheetCtrl.dispose();
    _stallsChannel?.unsubscribe();
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

      // Batch-fetch product counts for all stalls in one query.
      final sellerIds =
          list.map((s) => s.userId).where((id) => id.isNotEmpty).toList();
      if (sellerIds.isNotEmpty) {
        try {
          final products = await _supabase
              .from('product')
              .select('user_id')
              .inFilter('user_id', sellerIds);
          final counts = <String, int>{};
          for (final p in (products as List)) {
            final uid = p['user_id']?.toString();
            if (uid != null) counts[uid] = (counts[uid] ?? 0) + 1;
          }
          for (final s in list) {
            s.productCount = counts[s.userId] ?? 0;
          }
        } catch (_) {}
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
          _maybeAutoCenter();
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
        _maybeAutoCenter();
        if (_followMe) {
          _animatedMove(_myLocation!, _mapController.camera.zoom);
        }
      });
    } catch (_) {}
  }

  /// Smoothly animate to the user's first GPS fix on map load, like Google
  /// Maps. Subsequent stream updates won't re-center (the user might have
  /// panned away on purpose); follow-mode handles continuous tracking.
  void _maybeAutoCenter() {
    if (_hasAutoCentered) return;
    final loc = _myLocation;
    if (loc == null) return;
    _hasAutoCentered = true;
    // Defer one frame so the map controller has a viewport ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animatedMove(loc, 18);
    });
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
    var list = _showOpenOnly
        ? _stalls.where((s) => s.isOpen).toList()
        : List<_Stall>.from(_stalls);
    if (_searchQuery.isNotEmpty) {
      list = list.where((s) => s.storeName.toLowerCase().contains(_searchQuery)).toList();
    }
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

  /// Three-state "my location" handler, mirroring Google Maps:
  ///   1. Not centered → recenter (no follow).
  ///   2. Centered but not following → enable follow mode.
  ///   3. Following → exit follow mode.
  void _onMyLocationPressed() {
    final loc = _myLocation;
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for your location…')),
      );
      return;
    }
    if (_followMe) {
      setState(() => _followMe = false);
      return;
    }
    // Distance between current camera center and the user, in meters.
    final cam = _mapController.camera.center;
    final delta = distanceMeters(cam, loc);
    // If the camera is already roughly on the user, escalate to follow mode.
    // Otherwise just recenter.
    if (delta < 8) {
      setState(() => _followMe = true);
      _animatedMove(loc, 19);
    } else {
      _animatedMove(loc, 19);
    }
  }

  void _showStallSheet(_Stall stall) {
    final dist = stall.distanceMetersFrom(_myLocation);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _kPrimary.withValues(alpha: 0.18),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: const Color(0xFFEEF2FF),
                        backgroundImage: stall.logoUrl != null &&
                                stall.logoUrl!.isNotEmpty
                            ? NetworkImage(stall.logoUrl!)
                            : null,
                        child: stall.logoUrl == null || stall.logoUrl!.isEmpty
                            ? const Icon(Icons.storefront_rounded,
                                color: _kPrimary, size: 28)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stall.storeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: Color(0xFF111827),
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
                          const SizedBox(height: 6),
                          _statusChip(stall.isOpen),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_walk_rounded,
                          size: 18, color: _kPrimary),
                      const SizedBox(width: 8),
                      Text(
                        dist != null ? _walkTime(dist) : 'Location available',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF374151)),
                      ),
                      if (dist != null) ...[
                        const Spacer(),
                        Text(
                          formatDistance(dist),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _kPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (stall.productCount > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 18, color: _kPrimary),
                        const SizedBox(width: 8),
                        Text(
                          '${stall.productCount} products available',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
          Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing glow ring for open stalls
              if (stall.isOpen)
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (context, child) {
                    final t = _pulseCtrl.value;
                    final size = 34.0 + t * 20;
                    return Opacity(
                      opacity: (1 - t) * 0.42,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: const BoxDecoration(
                          color: _kPrimary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                ),
              // Marker body
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: stall.isOpen ? _kPrimary : const Color(0xFF9CA3AF),
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
                      ? const Icon(Icons.storefront_rounded, color: _kPrimary, size: 16)
                      : null,
                ),
              ),
            ],
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

  // ── Walk-time estimate ───────────────────────────────────────
  String _walkTime(double meters) {
    if (meters < 50) return "You're here";
    final mins = (meters / 67).ceil(); // ~4 km/h
    return '~$mins min walk';
  }

  // ── Floating search / back / filter bar ─────────────────────
  Widget _buildTopBar() {
    return Row(
      children: [
        // Back button
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 3,
          shadowColor: Colors.black26,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _kPrimary),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Search field
        Expanded(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 3,
            shadowColor: Colors.black26,
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Search stalls…',
                hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF9CA3AF)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: const Color(0xFF9CA3AF),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Open-only filter toggle
        Material(
          color: _showOpenOnly ? _kPrimary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 3,
          shadowColor: Colors.black26,
          child: InkWell(
            onTap: () => setState(() => _showOpenOnly = !_showOpenOnly),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                _showOpenOnly ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
                size: 20,
                color: _showOpenOnly ? Colors.white : _kPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Draggable bottom sheet content ───────────────────────────
  Widget _buildBottomSheet(
      List<_Stall> stalls, ScrollController scrollCtrl, int openCount) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F6FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Color(0x22000000), blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: ListView(
        controller: scrollCtrl,
        padding: EdgeInsets.zero,
        children: [
          // Drag handle
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Text(
                  '${stalls.length} stall${stalls.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const Spacer(),
                if (_myLocation == null)
                  TextButton.icon(
                    onPressed: _startLocationStream,
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text('Use my location'),
                    style: TextButton.styleFrom(foregroundColor: _kPrimary),
                  ),
              ],
            ),
          ),
          // Stall tiles
          if (stalls.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  _searchQuery.isNotEmpty
                      ? 'No stalls match "$_searchQuery".'
                      : 'No stalls have shared their location yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),
              ),
            )
          else
            for (int i = 0; i < stalls.length; i++)
              _buildStallListTile(stalls[i]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Single stall row in the bottom sheet list ────────────────
  Widget _buildStallListTile(_Stall stall) {
    final dist = stall.distanceMetersFrom(_myLocation);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _focusStall(stall),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFEEF2FF),
                  backgroundImage: stall.logoUrl != null && stall.logoUrl!.isNotEmpty
                      ? NetworkImage(stall.logoUrl!)
                      : null,
                  child: stall.logoUrl == null || stall.logoUrl!.isEmpty
                      ? const Icon(Icons.storefront_rounded, color: _kPrimary)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stall.storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (stall.stallNo.isNotEmpty)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  stall.stallNo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                                ),
                              ),
                            ),
                          if (stall.productCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${stall.productCount} items',
                                  style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600, color: _kPrimary,
                                  ),
                                ),
                              ),
                            ),
                          if (dist != null)
                            Text(
                              formatDistance(dist),
                              style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700, color: _kPrimary,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stalls = _visibleStalls;
    final openCount = _stalls.where((s) => s.isOpen).length;
    final top = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFE8EAF0),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Stack(
              children: [
                // ── Full-screen map ──────────────────────────────────
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: kMarketPlaza,
                      initialZoom: 18,
                      minZoom: 14,
                      maxZoom: 19,
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
                        urlTemplate: _isSatellite
                            ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                            : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                        subdomains:
                            _isSatellite ? const [] : const ['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'com.example.caps_finals',
                        maxNativeZoom: 19,
                        tileProvider: NetworkTileProvider(),
                        retinaMode: !_isSatellite,
                      ),
                      if (_myLocation != null && _myAccuracyMeters != null)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: _myLocation!,
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
                              width: 64,
                              height: 72,
                              alignment: Alignment.bottomCenter,
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
                ),

                // ── Draggable stall list ─────────────────────────────
                DraggableScrollableSheet(
                  controller: _sheetCtrl,
                  initialChildSize: 0.27,
                  minChildSize: 0.12,
                  maxChildSize: 0.65,
                  snap: true,
                  snapSizes: const [0.12, 0.27, 0.65],
                  builder: (ctx, scrollCtrl) =>
                      _buildBottomSheet(stalls, scrollCtrl, openCount),
                ),

                // ── FABs (above bottom sheet minimum) ───────────────
                Positioned(
                  right: 12,
                  bottom: screenH * 0.14,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'mapSatellite',
                        backgroundColor: _isSatellite ? _kPrimary : Colors.white,
                        foregroundColor: _isSatellite ? Colors.white : _kPrimary,
                        elevation: 4,
                        tooltip: _isSatellite ? 'Switch to map view' : 'Switch to satellite',
                        onPressed: () => setState(() => _isSatellite = !_isSatellite),
                        child: Icon(_isSatellite
                            ? Icons.map_rounded
                            : Icons.satellite_alt_rounded),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'mapMyLocation',
                        backgroundColor: _followMe ? _kPrimary : Colors.white,
                        foregroundColor: _followMe
                            ? Colors.white
                            : (_myLocation == null
                                ? const Color(0xFF9CA3AF)
                                : _kPrimary),
                        elevation: 4,
                        onPressed: _onMyLocationPressed,
                        child: Icon(_followMe
                            ? Icons.my_location
                            : Icons.near_me_rounded),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'mapPlaza',
                        backgroundColor: Colors.white,
                        foregroundColor: _kPrimary,
                        elevation: 4,
                        tooltip: 'Show market overview',
                        onPressed: () {
                          setState(() => _followMe = false);
                          _animatedMove(kMarketPlaza, 18);
                        },
                        child: const Icon(Icons.center_focus_strong),
                      ),
                    ],
                  ),
                ),

                // ── Legend pill ──────────────────────────────────────
                Positioned(
                  left: 12,
                  top: top + 72,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _legendPill(openCount, _stalls.length),
                  ),
                ),

                // ── Floating top bar ─────────────────────────────────
                Positioned(
                  top: top + 8,
                  left: 12,
                  right: 12,
                  child: _buildTopBar(),
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
