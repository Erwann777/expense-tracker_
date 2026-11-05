class CurrencyModel {
  final String code;
  final String name;
  final String symbol;
  final String flag;

  const CurrencyModel({
    required this.code,
    required this.name,
    required this.symbol,
    required this.flag,
  });
}

class AppCurrencies {
  static const List<CurrencyModel> currencies = [
    CurrencyModel(code: 'USD', name: 'US Dollar', symbol: '\$', flag: '🇺🇸'),
    CurrencyModel(code: 'EUR', name: 'Euro', symbol: '€', flag: '🇪🇺'),
    CurrencyModel(code: 'GBP', name: 'British Pound', symbol: '£', flag: '🇬🇧'),
    CurrencyModel(code: 'JPY', name: 'Japanese Yen', symbol: '¥', flag: '🇯🇵'),
    CurrencyModel(code: 'MYR', name: 'Malaysian Ringgit', symbol: 'RM', flag: '🇲🇾'),
    CurrencyModel(code: 'SGD', name: 'Singapore Dollar', symbol: 'S\$', flag: '🇸🇬'),
    CurrencyModel(code: 'THB', name: 'Thai Baht', symbol: '฿', flag: '🇹🇭'),
    CurrencyModel(code: 'CNY', name: 'Chinese Yuan', symbol: '¥', flag: '🇨🇳'),
    CurrencyModel(code: 'INR', name: 'Indian Rupee', symbol: '₹', flag: '🇮🇳')
  ];

  static CurrencyModel getByCode(String code) {
    return currencies.firstWhere(
      (c) => c.code == code,
      orElse: () => currencies.first,
    );
  }
}
// updated: 2026-09-23
