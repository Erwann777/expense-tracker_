import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service untuk fetch dan cache nilai tukar mata uang.
/// Menggunakan open.er-api.com (gratis, update setiap 24 jam).
class CurrencyService {
  static const String _baseUrl = 'https://open.er-api.com/v6/latest';
  static const Duration _cacheDuration = Duration(hours: 6);

  // Cache: baseCurrency -> {targetCode: rate}
  static final Map<String, Map<String, double>> _rateCache = {};
  // Timestamp per baseCurrency
  static final Map<String, DateTime> _cacheTime = {};

  /// Fetch exchange rates dengan base [baseCurrency].
  /// Return map: { 'USD': 1.0, 'IDR': 15800.0, 'MYR': 4.47, ... }
  /// Jika gagal (offline/error), return empty map.
  static Future<Map<String, double>> fetchRates(String baseCurrency) async {
    final code = baseCurrency.toUpperCase();

    // Cek cache
    final cached = _rateCache[code];
    final cacheTime = _cacheTime[code];
    if (cached != null &&
        cacheTime != null &&
        DateTime.now().difference(cacheTime) < _cacheDuration) {
      return cached;
    }

    try {
      final uri = Uri.parse('$_baseUrl/$code');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['result'] == 'success') {
          final rawRates = json['rates'] as Map<String, dynamic>;
          final rates = rawRates.map(
            (key, value) => MapEntry(key, (value as num).toDouble()),
          );
          _rateCache[code] = rates;
          _cacheTime[code] = DateTime.now();
          return rates;
        }
      }
    } catch (_) {
      // offline atau error — return cache lama jika ada
      if (cached != null) return cached;
    }

    return {};
  }

  /// Convert [amount] dari [fromCode] ke [toCode] menggunakan rates yang sudah di-fetch.
  /// Jika rates kosong atau kode tidak ada, return amount apa adanya (rate = 1.0).
  static double convertWithRates(
    double amount,
    String fromCode,
    String toCode,
    Map<String, double> ratesFromBase,
  ) {
    if (fromCode == toCode) return amount;
    if (ratesFromBase.isEmpty) return amount;

    // ratesFromBase = rates dari baseCurrency ke semua mata uang
    // Misal base = MYR, ratesFromBase = {USD: 0.22, IDR: 3450, MYR: 1.0, ...}
    final rateFrom = ratesFromBase[fromCode.toUpperCase()] ?? 1.0;
    final rateTo = ratesFromBase[toCode.toUpperCase()] ?? 1.0;

    // Convert: amount (in fromCode) -> base -> toCode
    // amount_in_base = amount / rateFrom
    // amount_in_to   = amount_in_base * rateTo
    return (amount / rateFrom) * rateTo;
  }

  /// Invalidate cache untuk baseCurrency tertentu (paksa re-fetch).
  static void invalidateCache(String baseCurrency) {
    _cacheTime.remove(baseCurrency.toUpperCase());
  }

  /// Invalidate semua cache.
  static void invalidateAll() {
    _rateCache.clear();
    _cacheTime.clear();
  }
}

