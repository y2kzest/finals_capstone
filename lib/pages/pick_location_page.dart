import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../utils/market_geo.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);

/// Foodpanda/Grab-style location picker.
/// The pin stays at the centre of the screen; the user drags the map
/// underneath it. Returns `{lat, lng, label, address}` on confirm,
/// or `null` if the user cancels.
class PickLocationPage extends StatefulWidget {
  const PickLocationPage({
    super.key,
    this.initialPoint,
    this.initialLabel,
    this.initialAddress,
    this.title = 'Set Delivery Location',
  });

  final LatLng? initialPoint;
  final String? initialLabel;
  final String? initialAddress;
  final String title;

  @override
  State<PickLocationPage> createState() => _PickLocationPageState();
}

class _PickLocationPageState extends State<PickLocationPage>
    with SingleTickerProviderStateMixin {
  final _mapController = MapController();
  late final TextEditingController _addrCtrl;
  late final AnimationController _bounceCtrl;
  late final Animation<double> _bounce;

  LatLng _center = kMarketPlaza;
  String _label = 'Home';
  bool _isDragging = false;
  bool _isLocating = false;

  static const _labels = ['Home', 'Work', 'Other'];

  @override
  void initState() {
    super.initState();
    _center = widget.initialPoint ?? kMarketPlaza;
    _label = _labels.contains(widget.initialLabel)
        ? widget.initialLabel!
        : (widget.initialLabel?.isNotEmpty == true ? 'Other' : 'Home');
    _addrCtrl = TextEditingController(text: widget.initialAddress ?? '');
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _bounce = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeOut),
    );
    if (widget.initialPoint == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useGps(silent: true));
    }
  }

  @override
  void dispose() {
    _addrCtrl.dispose();
    _bounceCtrl.dispose();
    super.dispose();
  }

  Future<void> _useGps({bool silent = false}) async {
    setState(() => _isLocating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!silent) _snack('Turn on device location to use GPS.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!silent) _snack('Location permission denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final next = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _center = next);
      _mapController.move(next, 18);
    } catch (e) {
      if (!silent) _snack('Could not get location: $e');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveStart) {
      _bounceCtrl.forward();
      setState(() => _isDragging = true);
    } else if (event is MapEventMoveEnd) {
      _bounceCtrl.reverse();
      setState(() {
        _isDragging = false;
        _center = event.camera.center;
      });
    }
  }

  void _confirm() {
    final addr = _addrCtrl.text.trim();
    if (addr.isEmpty) {
      _snack('Please type the address (house no., street, barangay…).');
      return;
    }
    Navigator.pop(context, {
      'lat': _center.latitude,
      'lng': _center.longitude,
      'label': _label,
      'address': addr,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: Stack(
        children: [
          // ── Map fills the screen ──
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 18,
                minZoom: 5,
                maxZoom: 19,
                onMapEvent: _onMapEvent,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.caps_finals',
                  maxNativeZoom: 19,
                ),
              ],
            ),
          ),

          // ── Floating centre pin ──
          IgnorePointer(
            child: Center(
              child: AnimatedBuilder(
                animation: _bounce,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, _bounce.value - 22),
                  child: child,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 52,
                      color: _kPrimary,
                      shadows: [
                        Shadow(
                          color: Color(0x66000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    Container(
                      width: 10,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(60),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Top app bar ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _circleBtn(
                    icon: Icons.arrow_back,
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
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            color: _kPrimary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
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

          // ── GPS button (above the bottom sheet) ──
          Positioned(
            right: 14,
            bottom: 280,
            child: _circleBtn(
              icon: _isLocating ? Icons.hourglass_top_rounded : Icons.my_location,
              onTap: _isLocating ? null : () => _useGps(),
            ),
          ),

          // ── Bottom card ──
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 18,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_rounded,
                          color: _kPrimary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _isDragging
                                ? 'Move the map to your spot…'
                                : '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _isDragging
                                  ? _kPrimary
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final l in _labels) ...[
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _label = l),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _label == l
                                      ? _kPrimary.withAlpha(22)
                                      : _kSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _label == l
                                        ? _kPrimary
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  l,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _label == l
                                        ? _kPrimary
                                        : const Color(0xFF9CA3AF),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (l != _labels.last) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addrCtrl,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'House no., street, barangay, city',
                        filled: true,
                        fillColor: _kSurface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: _isDragging ? null : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Confirm Location',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn({required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: _kPrimary, size: 22),
        ),
      ),
    );
  }
}
