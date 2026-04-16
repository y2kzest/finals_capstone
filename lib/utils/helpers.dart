// lib/utils/helpers.dart
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