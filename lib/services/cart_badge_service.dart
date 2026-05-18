import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CartBadgeService {
  CartBadgeService._();

  static final CartBadgeService instance = CartBadgeService._();

  final ValueNotifier<int> count = ValueNotifier<int>(0);

  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _cartChannel;
  String? _activeUserId;
  bool _initialized = false;

  void ensureInitialized() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    if (_initialized) {
      if (_activeUserId != currentUserId) {
        _activeUserId = currentUserId;
        _resubscribe(currentUserId);
        refreshCount();
      }
      return;
    }

    _initialized = true;
    _activeUserId = currentUserId;

    _authSubscription ??= Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        final newId = data.session?.user.id;
        if (newId != _activeUserId) {
          _activeUserId = newId;
          _resubscribe(newId);
        }
        refreshCount();
      },
    );

    _resubscribe(currentUserId);
    refreshCount();
  }

  void _resubscribe(String? userId) {
    _cartChannel?.unsubscribe();
    _cartChannel = null;
    if (userId == null) return;

    _cartChannel = Supabase.instance.client
        .channel('cart_badge_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cart',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'buyer_id',
            value: userId,
          ),
          callback: (_) => refreshCount(),
        )
        .subscribe();
  }

  Future<void> refreshCount() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _setCount(0);
      return;
    }

    try {
      final rows = await Supabase.instance.client
          .from('cart')
          .select('qty')
          .eq('buyer_id', userId);

      syncFromRows(List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      _setCount(0);
    }
  }

  void syncFromRows(List<Map<String, dynamic>> rows) {
    var total = 0;
    for (final row in rows) {
      total += _parseQty(row['qty']);
    }
    _setCount(total);
  }

  int _parseQty(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _setCount(int nextCount) {
    if (count.value != nextCount) {
      count.value = nextCount;
    }
  }
}
