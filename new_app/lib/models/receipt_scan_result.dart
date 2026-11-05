// Model untuk hasil scan receipt dari Gemini AI
class ReceiptScanResult {
  /// Jumlah total yang dibayar (null jika tidak ditemukan)
  final double? totalAmount;

  /// Nama merchant/toko
  final String? merchantName;

  /// Tanggal transaksi (null jika tidak ditemukan)
  final DateTime? transactionDate;

  /// Kategori yang disarankan AI (sesuai dengan kategori di aplikasi)
  final String? suggestedCategory;

  /// Kepercayaan diri AI terhadap hasil (0.0 - 1.0)
  final double confidence;

  /// Pesan error jika terjadi masalah
  final String? errorMessage;

  /// Raw text yang dikenali dari receipt (untuk debugging)
  final String? rawText;

  const ReceiptScanResult({
    this.totalAmount,
    this.merchantName,
    this.transactionDate,
    this.suggestedCategory,
    this.confidence = 1.0,
    this.errorMessage,
    this.rawText,
  });

  bool get hasError => errorMessage != null;
  bool get hasAmount => totalAmount != null && totalAmount! > 0;
  bool get isSuccess => !hasError && hasAmount;

  factory ReceiptScanResult.error(String message) => ReceiptScanResult(
        errorMessage: message,
        confidence: 0.0,
      );

  @override
  String toString() =>
      'ReceiptScanResult(amount: $totalAmount, merchant: $merchantName, '
      'date: $transactionDate, category: $suggestedCategory, '
      'confidence: $confidence)';
}

