import 'package:supabase_flutter/supabase_flutter.dart';

const String kFallbackAdminEmail = 'maicasulla13@gmail.com';

Future<Set<String>> fetchAdminUserIds(SupabaseClient supabase) async {
  final adminIds = <String>{};

  try {
    final roleRows = await supabase
        .from('user_roles')
        .select('user_id')
        .eq('role', 'admin');

    for (final row in roleRows as List) {
      final userId = row['user_id']?.toString();
      if (userId != null && userId.isNotEmpty) {
        adminIds.add(userId);
      }
    }
  } catch (_) {}

  try {
    final profile = await supabase
        .from('profile')
        .select('user_id')
        .eq('email', kFallbackAdminEmail)
        .maybeSingle();
    final userId = profile?['user_id']?.toString();
    if (userId != null && userId.isNotEmpty) {
      adminIds.add(userId);
    }
  } catch (_) {}

  return adminIds;
}