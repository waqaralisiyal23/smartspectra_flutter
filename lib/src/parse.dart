import 'models.dart';

/// Matches a native enum name in either `SCREAMING_SNAKE` (Kotlin) or
/// `lowerCamel` (Swift) form to a Dart enum value, or returns `null`.
T? tryParseEnum<T extends Enum>(List<T> values, String? raw) {
  if (raw == null) return null;
  final key = raw.replaceAll('_', '').toLowerCase();
  for (final value in values) {
    if (value.name.toLowerCase() == key) return value;
  }
  return null;
}

/// Like [tryParseEnum] but returns [fallback] when nothing matches.
T parseEnum<T extends Enum>(List<T> values, String? raw, T fallback) =>
    tryParseEnum(values, raw) ?? fallback;

/// Parses a native processing status. Swift prints an enum case with an
/// associated value as `error(...)` and may call idle `stopped`; anything
/// unknown counts as idle.
ProcessingStatus parseStatus(String? raw) {
  if (raw == null) return ProcessingStatus.idle;
  final name = raw.split('(').first.split('.').last.trim();
  if (name.toLowerCase() == 'stopped') return ProcessingStatus.idle;
  return parseEnum(ProcessingStatus.values, name, ProcessingStatus.idle);
}

/// Reads a number that may arrive as `int` or `double`.
double? asDouble(Object? value) => value is num ? value.toDouble() : null;

/// Reads an integer that may arrive as `int` or `double`.
int asInt(Object? value) => value is num ? value.toInt() : 0;
