import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/market_geo.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);

class EditStallLocationPage extends StatefulWidget {
  const EditStallLocationPage({super.key});

  @override
  State<EditStallLocationPage> createState() => _EditStallLocationPageState();
}

class _EditStallLocationPageState extends State<EditStallLocationPage> {
  final _supabase = Supabase.instance.client;
  final _mapController = MapController();
  final _stallNoCtrl = TextEditingController();

  LatLng _pin = kMarketPlaza;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _stallNoCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final data = await _supabase
          .from('seller_profiles')
          .select('stall_lat, stall_lng, stall_no')
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null) {
        final lat = (data['stall_lat'] as num?)?.toDouble();
        final lng = (data['stall_lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          _pin = LatLng(lat, lng);
        }
        _stallNoCtrl.text = data['stall_no']?.toString() ?? '';
      }
    } catch (_) {
      // non-critical
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      // Use the last known fix first so the pin snaps somewhere useful
      // immediately, then upgrade with a fresh high-accuracy lock.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          final approx = LatLng(last.latitude, last.longitude);
          setState(() => _pin = approx);
          _mapController.move(approx, 18);
        }
      } catch (_) {}

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final next = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _pin = next);
      _mapController.move(next, 18);
    } catch (e) {
      _snack('Could not get location: $e');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _save() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _isSaving = true);
    try {
      await _supabase.from('seller_profiles').update({
        'stall_lat': _pin.latitude,
        'stall_lng': _pin.longitude,
        'stall_no': _stallNoCtrl.text.trim(),
      }).eq('user_id', userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stall location saved!'),
          backgroundColor: _kPrimary,
        ),
      );
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _snack('Error: ${e.message}');
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _recenter() => _mapController.move(kMarketPlaza, 18);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kPrimary,
        elevation: 0,
        title: const Text(
          'Set Stall Location',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
        ),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: _kPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _pin,
                          initialZoom: 18,
                          minZoom: 14,
                          maxZoom: 19,
                          onTap: (_, latLng) =>
                              setState(() => _pin = latLng),
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
                                point: _pin,
                                width: 48,
                                height: 48,
                                alignment: Alignment.topCenter,
                                child: const Icon(
                                  Icons.location_on,
                                  color: _kPrimary,
                                  size: 48,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 10,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: _kPrimary, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tap the map to place your stall pin, or use GPS.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'recenter',
                              onPressed: _recenter,
                              backgroundColor: Colors.white,
                              foregroundColor: _kPrimary,
                              child: const Icon(Icons.center_focus_strong),
                            ),
                            const SizedBox(height: 10),
                            FloatingActionButton.small(
                              heroTag: 'gps',
                              onPressed: _isLocating ? null : _useCurrentLocation,
                              backgroundColor: _kPrimary,
                              foregroundColor: Colors.white,
                              child: _isLocating
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.my_location),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 12,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Stall Number / Label',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _stallNoCtrl,
                        decoration: InputDecoration(
                          hintText: 'e.g. Stall 12B / Row 3',
                          filled: true,
                          fillColor: const Color(0xFFF5F6FB),
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
                      const SizedBox(height: 10),
                      Text(
                        'Pin: ${_pin.latitude.toStringAsFixed(6)}, ${_pin.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
