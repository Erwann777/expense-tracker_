// Result model for a receipt scan performed by Gemini AI.
class ReceiptScanResult {
  /// Total amount paid, or null if it could not be found.
  final double? totalAmount;

  /// Merchant or store name.
  final String? merchantName;

  /// ISO 4217 currency code detected on the receipt, if available.
  final String? currencyCode;

  /// Transaction date, or null if it could not be found.
  final DateTime? transactionDate;

  /// AI-suggested category that matches an app category.
  final String? suggestedCategory;

  /// Model-reported confidence for the result (0.0 to 1.0).
  final double confidence;

  /// Model-reported confidence for each extracted field.
  final Map<String, double> fieldConfidence;

  /// Brief explanation for the suggested category.
  final String? categoryReason;

  /// Error message, if the scan failed.
  final String? errorMessage;

  /// Raw text returned by the model, for debugging.
  final String? rawText;

  const ReceiptScanResult({
    this.totalAmount,
    this.merchantName,
    this.currencyCode,
    this.transactionDate,
    this.suggestedCategory,
    this.confidence = 0.0,
    this.fieldConfidence = const {},
    this.categoryReason,
    this.errorMessage,
    this.rawText,
  });

  bool get hasError => errorMessage != null;
  bool get hasAmount => totalAmount != null && totalAmount! > 0;
  bool get isSuccess => !hasError && hasAmount;

  factory ReceiptScanResult.error(String message) =>
      ReceiptScanResult(errorMessage: message, confidence: 0.0);

  ReceiptScanResult copyWith({
    String? suggestedCategory,
    String? categoryReason,
  }) {
    return ReceiptScanResult(
      totalAmount: totalAmount,
      merchantName: merchantName,
      currencyCode: currencyCode,
      transactionDate: transactionDate,
      suggestedCategory: suggestedCategory ?? this.suggestedCategory,
      confidence: confidence,
      fieldConfidence: fieldConfidence,
      categoryReason: categoryReason ?? this.categoryReason,
      errorMessage: errorMessage,
      rawText: rawText,
    );
  }

  @override
  String toString() =>
      'ReceiptScanResult(amount: $totalAmount, merchant: $merchantName, '
      'date: $transactionDate, category: $suggestedCategory, '
      'confidence: $confidence)';
}
