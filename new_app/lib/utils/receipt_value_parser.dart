class ReceiptValueParser {
  static double? parseAmount(String input) {
    const currencyCodes =
        r'(?:rp|rm|idr|usd|eur|gbp|jpy|cny|inr|aud|cad|sgd|myr|thb|php|vnd|krw)';
    final withoutCurrency = input.replaceAll(
      RegExp('^\\s*$currencyCodes\\s*|\\s*$currencyCodes\\s*\$', caseSensitive: false),
      '',
    );
    final value = withoutCurrency.replaceAll(RegExp(r'[\s$€£¥₹]'), '');
    if (value.isEmpty ||
        value.contains('-') ||
        value.startsWith('(') ||
        value.endsWith(')')) {
      return null;
    }

    final separators = RegExp(r'[,.]').allMatches(value).length;
    if (separators == 0) return double.tryParse(value);

    final lastComma = value.lastIndexOf(',');
    final lastDot = value.lastIndexOf('.');
    if (lastComma >= 0 && lastDot >= 0) {
      final decimalSeparator = lastComma > lastDot ? ',' : '.';
      final groupingSeparator = decimalSeparator == ',' ? '.' : ',';
      final decimalIndex = value.lastIndexOf(decimalSeparator);
      final fraction = value.substring(decimalIndex + 1);
      if (fraction.isEmpty || fraction.length > 2 || !_isDigits(fraction)) {
        return null;
      }

      final integer = value.substring(0, decimalIndex);
      final groups = integer.split(groupingSeparator);
      if (!_hasValidGrouping(groups)) return null;
      return double.tryParse(
        '${groups.join()}.$fraction',
      );
    }

    final separator = lastComma >= 0 ? ',' : '.';
    final groups = value.split(separator);
    if (groups.any((group) => !_isDigits(group))) return null;

    if (groups.length == 2) {
      final fraction = groups[1];
      if (fraction.length <= 2) {
        return double.tryParse('${groups[0]}.$fraction');
      }
      if (fraction.length == 3 && groups[0].length <= 3) {
        return double.tryParse(groups.join());
      }
      return null;
    }

    if (!_hasValidGrouping(groups)) return null;
    return double.tryParse(groups.join());
  }

  static DateTime? parseDate(String input) {
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})$',
    ).firstMatch(input.trim());
    if (match == null) return null;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static bool _isDigits(String value) => RegExp(r'^\d+$').hasMatch(value);

  static bool _hasValidGrouping(List<String> groups) {
    if (groups.length < 2 ||
        groups.first.isEmpty ||
        groups.first.length > 3 ||
        !_isDigits(groups.first)) {
      return false;
    }
    return groups.skip(1).every((group) => group.length == 3 && _isDigits(group));
  }
}
