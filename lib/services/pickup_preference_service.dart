import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PickupPreferenceService {
  PickupPreferenceService._();

  static final PickupPreferenceService instance = PickupPreferenceService._();

  static const String defaultWindow = 'Today, all day';

  final ValueNotifier<String> preferredPickup = ValueNotifier<String>(
    defaultWindow,
  );

  StreamSubscription<AuthState>? _authSubscription;
  String? _activeUserId;
  bool _initialized = false;

  void ensureInitialized() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    if (_initialized) {
      if (_activeUserId != currentUserId) {
        _activeUserId = currentUserId;
        reload();
      }
      return;
    }

    _initialized = true;
    _activeUserId = currentUserId;
    if (_authSubscription == null) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
        (data) {
          _activeUserId = data.session?.user.id;
          reload();
        },
      );
    }
    reload();
  }

  String get currentValue => preferredPickup.value;

  Future<String> reload() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      preferredPickup.value = defaultWindow;
      return preferredPickup.value;
    }

    try {
      final profile = await Supabase.instance.client
          .from('profile')
          .select('preferred_pickup_window')
          .eq('user_id', userId)
          .maybeSingle();

      final value = profile?['preferred_pickup_window']?.toString().trim();
      preferredPickup.value = value == null || value.isEmpty
          ? defaultWindow
          : value;
    } catch (_) {
      preferredPickup.value = defaultWindow;
    }

    return preferredPickup.value;
  }

  Future<void> save(String value) async {
    final normalized = value.trim().isEmpty ? defaultWindow : value.trim();
    preferredPickup.value = normalized;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client
          .from('profile')
          .update({'preferred_pickup_window': normalized})
          .eq('user_id', userId);
    } catch (_) {}
  }
}
