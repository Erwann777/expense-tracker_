import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/utils/receipt_value_parser.dart';

void main() {
  group('ReceiptValueParser.parseAmount', () {
    test('parses decimal separators and currency symbols', () {
      expect(ReceiptValueParser.parseAmount(r'$1,234.56'), 1234.56);
      expect(ReceiptValueParser.parseAmount('1.234,56 €'), 1234.56);
      expect(ReceiptValueParser.parseAmount('Rp 1.234,56'), 1234.56);
      expect(ReceiptValueParser.parseAmount('RM 1,234.56'), 1234.56);
      expect(ReceiptValueParser.parseAmount('12,50'), 12.5);
      expect(ReceiptValueParser.parseAmount('12.50'), 12.5);
    });

    test('parses grouped integer amounts', () {
      expect(ReceiptValueParser.parseAmount('1,234'), 1234);
      expect(ReceiptValueParser.parseAmount('1.234.567'), 1234567);
      expect(ReceiptValueParser.parseAmount('12'), 12);
    });

    test('rejects malformed, negative, and ambiguous amounts', () {
      expect(ReceiptValueParser.parseAmount('1,23,456.78'), isNull);
      expect(ReceiptValueParser.parseAmount('1,234.567'), isNull);
      expect(ReceiptValueParser.parseAmount('-12.50'), isNull);
      expect(ReceiptValueParser.parseAmount('(12.50)'), isNull);
      expect(ReceiptValueParser.parseAmount('not an amount'), isNull);
    });
  });

  group('ReceiptValueParser.parseDate', () {
    test('parses valid ISO dates', () {
      expect(ReceiptValueParser.parseDate('2026-11-09'), DateTime(2026, 11, 9));
    });

    test('rejects invalid or non-ISO dates', () {
      expect(ReceiptValueParser.parseDate('2026-02-30'), isNull);
      expect(ReceiptValueParser.parseDate('09/11/2026'), isNull);
      expect(ReceiptValueParser.parseDate('2026-2-9'), isNull);
    });
  });
}
