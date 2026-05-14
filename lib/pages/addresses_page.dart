import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/buyer_location_service.dart';
import 'pick_location_page.dart';

const Color _kPrimary = Color(0xFF2A4BA0);
const Color _kSurface = Color(0xFFF5F6FB);

// Per-label theming
_LabelTheme _labelTheme(String? label) {
  switch (label) {
    case 'Work':
      return _LabelTheme(
        icon: Icons.work_rounded,
        bg: const Color(0xFFEEF2FF),
        fg: const Color(0xFF4F46E5),
      );
    case 'Other':
      return _LabelTheme(
        icon: Icons.place_rounded,
        bg: const Color(0xFFFFF7ED),
        fg: const Color(0xFFEA580C),
      );
    default: // Home
      return _LabelTheme(
        icon: Icons.home_rounded,
        bg: const Color(0xFFEFF6FF),
        fg: _kPrimary,
      );
  }
}

class _LabelTheme {
  final IconData icon;
  final Color bg;
  final Color fg;
  const _LabelTheme({required this.icon, required this.bg, required this.fg});
}

class AddressesPage extends StatefulWidget {
  const AddressesPage({super.key});

  @override
  State<AddressesPage> createState() => _AddressesPageState();
}

class _AddressesPageState extends State<AddressesPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _addresses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final res = await _supabase
          .from('delivery_addresses')
          .select()
          .eq('user_id', user.id)
          .order('is_default', ascending: false)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() {
          _addresses = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _setDefault(String id) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    await _supabase
        .from('delivery_addresses')
        .update({'is_default': false})
        .eq('user_id', user.id);
    await _supabase
        .from('delivery_addresses')
        .update({'is_default': true})
        .eq('id', id);
    final chosen =
        _addresses.firstWhere((a) => a['id'] == id, orElse: () => {});
    if (chosen.isNotEmpty) {
      await _supabase
          .from('profile')
          .update({'delivery_address': chosen['address']})
          .eq('user_id', user.id);
    }
    BuyerLocationService.instance.invalidate();
    await _load();
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: const Text('Delete address?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: const Text(
            'This address will be permanently removed from your saved list.',
            style: TextStyle(color: Color(0xFF6B7280), height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _supabase.from('delivery_addresses').delete().eq('id', id);
    BuyerLocationService.instance.invalidate();
    await _load();
  }

  Future<void> _openMapPicker({Map<String, dynamic>? existing}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    LatLng? initialPoint;
    final lat = (existing?['lat'] as num?)?.toDouble();
    final lng = (existing?['lng'] as num?)?.toDouble();
    if (lat != null && lng != null) initialPoint = LatLng(lat, lng);

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => PickLocationPage(
          initialPoint: initialPoint,
          initialLabel: existing?['label']?.toString(),
          initialAddress: existing?['address']?.toString(),
          title: existing == null ? 'Set Delivery Location' : 'Edit Address',
        ),
      ),
    );

    if (result == null) return;
    final payload = <String, dynamic>{
      'label': result['label'],
      'address': result['address'],
      'lat': result['lat'],
      'lng': result['lng'],
    };

    try {
      if (existing != null) {
        await _supabase
            .from('delivery_addresses')
            .update(payload)
            .eq('id', existing['id']);
      } else {
        final isFirst = _addresses.isEmpty;
        await _supabase.from('delivery_addresses').insert({
          'user_id': user.id,
          ...payload,
          'is_default': isFirst,
        });
        if (isFirst) {
          await _supabase
              .from('profile')
              .update({'delivery_address': result['address']})
              .eq('user_id', user.id);
        }
      }
      BuyerLocationService.instance.invalidate();
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: ${e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      body: CustomScrollView(
        slivers: [
          // Gradient app bar
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2A4BA0), Color(0xFF153075)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(30),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Saved Addresses',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: 2),
                            Text('Manage your delivery locations',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Body
          if (_isLoading)
            const SliverFillRemaining(
              child:
                  Center(child: CircularProgressIndicator(color: _kPrimary)),
            )
          else if (_addresses.isEmpty)
            SliverFillRemaining(
              child: _EmptyState(onAdd: _openMapPicker),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '${_addresses.length} address${_addresses.length == 1 ? '' : 'es'} saved',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 0.3),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
              sliver: SliverList.separated(
                itemCount: _addresses.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _AddressCard(
                  address: _addresses[i],
                  onSetDefault: () => _setDefault(_addresses[i]['id']),
                  onEdit: () => _openMapPicker(existing: _addresses[i]),
                  onDelete: () => _delete(_addresses[i]['id']),
                ),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _openMapPicker,
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Pin on Map',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
    );
  }
}

// ── Address Card ──────────────────────────────────────
class _AddressCard extends StatelessWidget {
  final Map<String, dynamic> address;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AddressCard({
    required this.address,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDefault = address['is_default'] == true;
    final label = address['label']?.toString() ?? 'Home';
    final theme = _labelTheme(label);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isDefault
            ? Border.all(color: _kPrimary.withAlpha(80), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: isDefault
                ? _kPrimary.withAlpha(18)
                : Colors.black.withAlpha(10),
            blurRadius: isDefault ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top: icon + label + badge + menu
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 0),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.bg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(theme.icon, color: theme.fg, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Color(0xFF111827))),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2A4BA0), Color(0xFF153075)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Default',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3)),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F6FB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.more_horiz_rounded,
                        color: Color(0xFF6B7280), size: 18),
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 3,
                  onSelected: (val) {
                    if (val == 'default') onSetDefault();
                    if (val == 'edit') onEdit();
                    if (val == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    if (!isDefault)
                      PopupMenuItem(
                        value: 'default',
                        child: Row(children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                                color: _kPrimary.withAlpha(15),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.check_circle_rounded,
                                size: 16, color: _kPrimary),
                          ),
                          const SizedBox(width: 10),
                          const Text('Set as Default',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.edit_rounded,
                              size: 16, color: Colors.grey.shade600),
                        ),
                        const SizedBox(width: 10),
                        const Text('Edit',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.delete_rounded,
                              size: 16, color: Colors.red.shade500),
                        ),
                        const SizedBox(width: 10),
                        Text('Delete',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.red.shade600)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Address text
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              address['address']?.toString() ?? '',
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF4B5563),
                  height: 1.55),
            ),
          ),

          if (address['lat'] != null && address['lng'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.place_rounded,
                      size: 13, color: _kPrimary.withAlpha(180)),
                  const SizedBox(width: 4),
                  Text(
                    'Pinned on map',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),

          // Bottom action row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                if (!isDefault)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onSetDefault,
                      icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 15),
                      label: const Text('Set Default'),
                      style: TextButton.styleFrom(
                        foregroundColor: _kPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Row(children: [
                      Icon(Icons.verified_rounded,
                          size: 14, color: _kPrimary.withAlpha(160)),
                      const SizedBox(width: 4),
                      Text('Default for deliveries',
                          style: TextStyle(
                              fontSize: 11,
                              color: _kPrimary.withAlpha(160),
                              fontWeight: FontWeight.w500)),
                    ]),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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

// ── Empty state ───────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_location_alt_rounded,
                  size: 42, color: _kPrimary),
            ),
            const SizedBox(height: 20),
            const Text('No saved addresses yet',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Color(0xFF111827))),
            const SizedBox(height: 8),
            const Text(
              'Save your home, work, or any\nfrequent delivery location here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF9CA3AF),
                  height: 1.55),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add First Address',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: _kPrimary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
