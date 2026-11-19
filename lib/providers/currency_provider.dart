import 'package:flutter/material.dart';
import '../services/currency_service.dart';
import '../models/currency_model.dart';
import '../utils/formatters.dart';

/// Provider untuk konversi mata uang secara real-time.
///
/// Pendekatan: fetch rates FROM USD (paling universal & stabil).
/// Semua data expense disimpan di Firestore dengan nilai aslinya
/// (tidak di-convert). Konversi hanya terjadi saat TAMPIL di UI.
///
/// Alur konversi: storedAmount (baseCurrency) → USD → displayCurrency
///   amount_usd  = storedAmount / usdRates[baseCurrency]
///   displayAmt  = amount_usd  * usdRates[displayCurrency]
class CurrencyProvider with ChangeNotifier {
  /// Currency asal tempat amount disimpan di Firestore.
  /// Ini adalah currency yang dipakai user saat PERTAMA KALI mendaftar
  /// dan TIDAK berubah saat user ganti display currency.
  /// Hanya berubah ketika user benar-benar ingin ganti base (re-denominate).
  String _baseCurrency = 'USD';

  /// Currency yang ditampilkan ke user saat ini (bisa diubah kapan saja).
  String _displayCurrency = 'USD';

  /// Rates FROM USD ke semua currency lain.
  /// { 'USD': 1.0, 'MYR': 4.47, 'IDR': 16200.0, 'EUR': 0.92, ... }
  /// Artinya: 1 USD = rates[X] unit of X.
  Map<String, double> _usdRates = {};

  bool _isLoading = false;
  bool _hasError = false;
  DateTime? _lastFetched;

  String get baseCurrency => _baseCurrency;
  String get displayCurrency => _displayCurrency;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  DateTime? get lastFetched => _lastFetched;

  /// True only when base and display are the same — skip math entirely.
  bool get isSameCurrency => _baseCurrency == _displayCurrency;

  // ─── Core ────────────────────────────────────────────────────────────────────

  /// Init saat user login atau saat shell pertama kali dibuild.
  /// [storedCurrency]  = currency yang dipakai saat expenses disimpan di DB
  /// [displayCurrency] = currency yang ingin ditampilkan ke user saat ini
  Future<void> init(String storedCurrency, String displayCurrency) async {
    _baseCurrency    = storedCurrency.toUpperCase();
    _displayCurrency = displayCurrency.toUpperCase();
    await _fetchUsdRates();
  }

  /// Dipanggil saat user mengganti currency pilihan di Settings.
  /// Hanya mengubah TAMPILAN — data di Firestore tidak tersentuh.
  Future<void> changeDisplayCurrency(String newCurrencyCode) async {
    final newCode = newCurrencyCode.toUpperCase();
    if (_displayCurrency == newCode) return;

    _displayCurrency = newCode;

    // Pastikan rates sudah tersedia sebelum me-rebuild UI.
    if (_usdRates.isEmpty) {
      await _fetchUsdRates();   // fetch sekaligus notify di dalam
    } else {
      notifyListeners();
    }
  }

  /// Dipanggil ketika user mengganti base currency (re-denominate).
  /// Ini mengubah KEDUANYA sekaligus dan memastikan provider sinkron.
  Future<void> changeBaseCurrency(String newBaseCurrencyCode) async {
    final newCode = newBaseCurrencyCode.toUpperCase();
    _baseCurrency    = newCode;
    _displayCurrency = newCode;

    if (_usdRates.isEmpty) {
      await _fetchUsdRates();
    } else {
      notifyListeners();
    }
  }

  /// Reset saat user logout.
  void reset() {
    _baseCurrency    = 'USD';
    _displayCurrency = 'USD';
    _usdRates        = {};
    _isLoading       = false;
    _hasError        = false;
    _lastFetched     = null;
    notifyListeners();
  }

  // ─── Conversion ──────────────────────────────────────────────────────────────

  /// Rate: 1 USD = how many units of baseCurrency.
  double get _baseToUsdRate {
    if (_baseCurrency == 'USD') return 1.0;
    final rate = _usdRates[_baseCurrency];
    if (rate == null || rate <= 0) return 1.0;
    return rate;
  }

  /// Rate: 1 USD = how many units of displayCurrency.
  double get _usdToDisplayRate {
    if (_displayCurrency == 'USD') return 1.0;
    final rate = _usdRates[_displayCurrency];
    if (rate == null || rate <= 0) return 1.0;
    return rate;
  }

  /// Final conversion rate: how many displayCurrency units = 1 baseCurrency unit.
  /// Formula: (1 / _baseToUsdRate) * _usdToDisplayRate
  double get conversionRate {
    if (isSameCurrency) return 1.0;
    if (_usdRates.isEmpty) return 1.0;
    return _usdToDisplayRate / _baseToUsdRate;
  }

  /// Convert [amount] stored in baseCurrency → displayCurrency.
  double convert(double amount) {
    if (isSameCurrency) return amount;
    if (_usdRates.isEmpty) return amount;
    return amount * conversionRate;
  }

  /// Format [amount] (stored in baseCurrency) with the display currency symbol.
  String format(double amount) {
    return Formatters.currency(convert(amount), _displayCurrency);
  }

  /// Format compact (K, M) with the display currency symbol.
  String formatCompact(double amount) {
    return Formatters.currencyCompact(convert(amount), _displayCurrency);
  }

  /// Format an amount that is ALREADY in displayCurrency (no conversion).
  String formatDisplay(double amount) {
    return Formatters.currency(amount, _displayCurrency);
  }

  /// Format compact amount that is ALREADY in displayCurrency (no conversion).
  String formatCompactDisplay(double amount) {
    return Formatters.currencyCompact(amount, _displayCurrency);
  }

  /// Convert [amount] from any [fromCode] to any [toCode] via USD pivot.
  /// Fetches rates automatically if not yet loaded.
  Future<double> convertBetween(
    double amount,
    String fromCode,
    String toCode,
  ) async {
    final from = fromCode.toUpperCase();
    final to   = toCode.toUpperCase();
    if (from == to || amount == 0) return amount;

    if (_usdRates.isEmpty) {
      await _fetchUsdRates();
    }
    // Second attempt via CurrencyService directly (belt-and-suspenders).
    if (_usdRates.isEmpty) {
      final rates = await CurrencyService.fetchRates('USD');
      if (rates.isNotEmpty) _usdRates = rates;
    }

    if (_usdRates.isEmpty) return amount; // offline & no cache

    return CurrencyService.convertWithRates(amount, from, to, _usdRates);
  }

  /// Display symbol for the currently selected display currency.
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
