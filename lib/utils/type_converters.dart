/// Utility functions for type conversion
/// Centralized helper methods to avoid code duplication across models

class TypeConverters {
  /// Convert dynamic value to int with default value
  static int toInt(dynamic value, {int defaultValue = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? defaultValue;
  }

  /// Convert dynamic value to double
  static double toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Convert dynamic value to nullable int
  static int? toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  /// Convert dynamic value to nullable string
  static String? toNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  /// Parse an API timestamp and normalize it to the device timezone.
  static DateTime? toLocalDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    final text = value.toString();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  /// Format a date key using the local calendar day.
  static String localDateKey(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  /// Parse a date-like API value and return its local yyyy-MM-dd key.
  static String? localDateKeyFromValue(dynamic value) {
    final date = toLocalDateTime(value);
    if (date == null) {
      final text = value?.toString() ?? '';
      return text.length >= 10 ? text.substring(0, 10) : null;
    }
    return localDateKey(date);
  }
}
