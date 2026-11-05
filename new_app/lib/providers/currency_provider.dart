import 'package:flutter/material.dart';
import '../services/currency_service.dart';
import '../models/currency_model.dart';
import '../utils/formatters.dart';

/// Provider untuk konversi mata uang secara real-time.
///
/// Pendekatan: fetch rates FROM USD (paling universal & stabil).
/// Semua konversi melalui USD sebagai intermediate:
///   amount_usd = amount / rate_base_to_usd
///   result     = amount_usd * rate_display_to_usd
///
/// Dengan cara ini, tidak perlu khawatir soal baseCurrency — semua
/// currency pair bisa dikonversi dengan akurat tanpa fetch ulang
/// setiap kali ganti currency.
class CurrencyProvider with ChangeNotifier {
  /// Currency asal tempat amount disimpan di Firestore
  String _baseCurrency = 'USD';

  /// Currency yang ditampilkan ke user saat ini
  String _displayCurrency = 'USD';

  /// Rates FROM USD ke semua currency lain
  /// { 'USD': 1.0, 'MYR': 4.47, 'IDR': 16200.0, 'SGD': 1.35, ... }
  /// Artinya: 1 USD = rates[X] unit X
  Map<String, double> _usdRates = {};

  bool _isLoading = false;
  bool _hasError = false;
  DateTime? _lastFetched;

  String get baseCurrency => _baseCurrency;
  String get displayCurrency => _displayCurrency;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  DateTime? get lastFetched => _lastFetched;

  bool get isSameCurrency => _baseCurrency == _displayCurrency;

  // ─── Core ────────────────────────────────────────────────────────────────────

  /// Init saat user login.
  /// [baseCurrency] = currency tersimpan di DB
  /// [displayCurrency] = currency yang user pilih untuk ditampilkan
  Future<void> init(String baseCurrency, String displayCurrency) async {
    _baseCurrency = baseCurrency.toUpperCase();
    _displayCurrency = displayCurrency.toUpperCase();
    await _fetchUsdRates();
  }

  /// Dipanggil saat user mengganti currency di settings.
  Future<void> changeDisplayCurrency(String newCurrencyCode) async {
    final newCode = newCurrencyCode.toUpperCase();
    if (_displayCurrency == newCode) return;
    _displayCurrency = newCode;
    notifyListeners(); // rebuild UI optimistic
    // Rates sudah ada (FROM USD), tidak perlu fetch ulang
    // Tapi kalau belum pernah fetch, fetch sekarang
    if (_usdRates.isEmpty) {
      await _fetchUsdRates();
    } else {
      notifyListeners(); // trigger rebuild dengan rates baru
    }
  }

  /// Reset saat user logout
  void reset() {
    _baseCurrency = 'USD';
    _displayCurrency = 'USD';
    _usdRates = {};
    _isLoading = false;
    _hasError = false;
    _lastFetched = null;
    notifyListeners();
  }

  // ─── Conversion ──────────────────────────────────────────────────────────────

  /// Rate dari baseCurrency ke USD.
  /// Jika base = IDR dan rates['IDR'] = 16200, maka 1 USD = 16200 IDR
  /// → 1 IDR = 1/16200 USD
  double get _baseToUsdRate {
    if (_baseCurrency == 'USD') return 1.0;
    final rate = _usdRates[_baseCurrency];
    if (rate == null || rate == 0) return 1.0;
    return rate; // 1 USD = rate units of baseCurrency
  }

  /// Rate dari USD ke displayCurrency.
  double get _usdToDisplayRate {
    if (_displayCurrency == 'USD') return 1.0;
    return _usdRates[_displayCurrency] ?? 1.0;
  }

  /// Rate final: berapa unit displayCurrency = 1 unit baseCurrency
  double get conversionRate {
    if (isSameCurrency) return 1.0;
    if (_usdRates.isEmpty) return 1.0;
    // base → USD → display
    // 1 baseCurrency = (1 / _baseToUsdRate) USD = (1 / _baseToUsdRate) * _usdToDisplayRate display
    return _usdToDisplayRate / _baseToUsdRate;
  }

  /// Konversi [amount] dari baseCurrency ke displayCurrency.
  double convert(double amount) {
    if (isSameCurrency || _usdRates.isEmpty) return amount;
    return amount * conversionRate;
  }

  /// Format dengan simbol mata uang display.
  String format(double amount) {
    final converted = convert(amount);
    return Formatters.currency(converted, _displayCurrency);
  }

  /// Format compact (K, M) dengan simbol mata uang display.
  String formatCompact(double amount) {
    final converted = convert(amount);
    return Formatters.currencyCompact(converted, _displayCurrency);
  }

  /// Simbol mata uang yang ditampilkan saat ini
  String get displaySymbol {
    return AppCurrencies.getByCode(_displayCurrency).symbol;
  }

  // ─── Private ─────────────────────────────────────────────────────────────────

  Future<void> _fetchUsdRates() async {
    _isLoading = true;
    _hasError = false;
    notifyListeners();

    try {
      // Selalu fetch FROM USD — paling stabil dan universal
      final rates = await CurrencyService.fetchRates('USD');
      if (rates.isNotEmpty) {
        _usdRates = rates;
        _lastFetched = DateTime.now();
        _hasError = false;
      } else {
        _hasError = true;
      }
    } catch (_) {
      _hasError = true;
    }

    _isLoading = false;
    notifyListeners();
  }
}
