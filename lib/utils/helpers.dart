// lib/utils/helpers.dart
import 'package:supabase_flutter/supabase_flutter.dart';

bool isEmail(String input) {
  return RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$').hasMatch(input);
}

/// Converts a 24hr "HH:mm" string to 12hr "h:mm AM/PM" format.
String to12Hour(String time24) {
  try {
    final parts = time24.split(':');
    int hour = int.parse(parts[0]);
    final min = parts[1];
    final amPm = hour >= 12 ? 'PM' : 'AM';
    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }
    return '$hour:$min $amPm';
  } catch (_) {
    return time24;
  }
}

String preferredProfileName(User user) {
  final metadataName =
      user.userMetadata?['name']?.toString().trim() ??
      user.userMetadata?['full_name']?.toString().trim();
  if (metadataName != null && metadataName.isNotEmpty) {
    return metadataName;
  }

  final emailPrefix = user.email?.split('@').first.trim();
  if (emailPrefix != null && emailPrefix.isNotEmpty) {
    return emailPrefix;
  }

  return 'Buyer';
}

Future<void> ensureOwnProfileRow(SupabaseClient client) async {
  final user = client.auth.currentUser;
  if (user == null) return;

  final desiredName = preferredProfileName(user);
  final desiredEmail = user.email ?? '';

  try {
    final existing = await client
        .from('profile')
        .select('user_id, name, email')
        .eq('user_id', user.id)
        .maybeSingle();

    if (existing == null) {
      await client.from('profile').insert({
        'user_id': user.id,
        'email': desiredEmail,
        'name': desiredName,
      });
      return;
    }

    final updates = <String, dynamic>{};
    final currentName = existing['name']?.toString().trim() ?? '';
    final currentEmail = existing['email']?.toString().trim() ?? '';

    if (currentName.isEmpty || currentName == 'Buyer') {
      updates['name'] = desiredName;
    }
    if (currentEmail.isEmpty && desiredEmail.isNotEmpty) {
      updates['email'] = desiredEmail;
    }

    if (updates.isNotEmpty) {
      await client.from('profile').update(updates).eq('user_id', user.id);
    }
  } catch (_) {
    // Best-effort only. Messaging should still work even if profile sync fails.
  }
}