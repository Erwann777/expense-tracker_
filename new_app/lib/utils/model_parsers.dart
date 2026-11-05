import 'package:cloud_firestore/cloud_firestore.dart';

/// Robust parsers for Firestore documents that prevent crashes from unexpected field types
class ModelParsers {
  /// Safely parse DateTime from String, Timestamp, int (epoch ms), or DateTime
  static DateTime parseDateTime(dynamic value, [DateTime? fallback]) {
    if (value == null) return fallback ?? DateTime.now();
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback ?? DateTime.now();
  }

  /// Safely parse optional DateTime
  static DateTime? parseOptionalDateTime(dynamic value) {
    if (value == null) return null;
    return parseDateTime(value);
  }

  /// Safely parse double from num or String
  static double parseDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Safely parse int from num or String
  static int parseInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Safely parse bool from bool, num, or String
  static bool parseBool(dynamic value, [bool fallback = false]) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value == 1;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      return lower == 'true' || lower == '1';
    }
    return fallback;
  }

  /// Safely parse String
  static String parseString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    return value.toString();
  }
}
