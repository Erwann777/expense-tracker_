import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/receipt_scan_result.dart';

/// Service untuk scan receipt menggunakan Google Gemini Vision API.
/// Mengirim gambar receipt ke Gemini dan mendapatkan:
/// - Total amount
/// - Nama merchant
/// - Tanggal transaksi
/// - Kategori yang sesuai dengan aplikasi
class GeminiReceiptService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  /// Daftar kategori expense yang tersedia di aplikasi.
  /// Harus sinkron dengan AppCategories.categories di category_model.dart
  static const List<String> _expenseCategories = [
    'Food & Dining',
    'Transport',
    'Shopping',
    'Entertainment',
    'Health',
    'Education',
    'Bills & Utilities',
    'Groceries',
    'Travel',
    'Personal Care',
    'Gifts',
    'Rent',
    'Insurance',
    'Subscriptions',
    'Fitness',
    'Pets',
    'Other',
  ];

  /// Prompt yang dikirim ke Gemini bersama gambar receipt.
  /// Dirancang agar output selalu JSON yang konsisten dan mudah di-parse.
  static String _buildPrompt() {
    final categoriesJson = jsonEncode(_expenseCategories);
    return '''
You are an expert receipt scanner AI. Analyze this receipt image and extract information with high accuracy.

Return ONLY a valid JSON object (no markdown, no code blocks, no extra text) with these exact fields:
{
  "total_amount": <number or null>,
  "merchant_name": <string or null>,
  "transaction_date": <"YYYY-MM-DD" or null>,
  "category": <one of the allowed categories or null>,
  "confidence": <number between 0.0 and 1.0>
}

Rules:
1. "total_amount": Extract the FINAL total amount paid (after tax, after discount). Must be a positive number. Use null if not found.
2. "merchant_name": Extract the store/restaurant/merchant name. Capitalize properly. Use null if not found.
3. "transaction_date": Extract the date in YYYY-MM-DD format. Use null if not found.
4. "category": Choose the BEST matching category from this list ONLY: $categoriesJson. Use null if none fits.
5. "confidence": Your overall confidence in the extraction (1.0 = very confident, 0.5 = uncertain).

Important: Only return the raw JSON. No explanation. No markdown. Just the JSON object.
''';
  }

  /// Scan receipt dari file gambar menggunakan Gemini Vision API.
  /// [imageFile]: File gambar receipt (JPEG/PNG)
  /// Returns [ReceiptScanResult] dengan data yang diekstrak.
  static Future<ReceiptScanResult> scanReceipt(File imageFile) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'your_gemini_api_key_here') {
      return ReceiptScanResult.error(
        'Gemini API key belum dikonfigurasi. Isi GEMINI_API_KEY di file .env',
      );
    }

    try {
      // Baca gambar sebagai bytes dan encode ke base64
      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // Deteksi MIME type berdasarkan ekstensi file
      final ext = imageFile.path.split('.').last.toLowerCase();
      final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

      // Bangun request body untuk Gemini API
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': _buildPrompt()},
              {
                'inline_data': {
                  'mime_type': mimeType,
                  'data': base64Image,
                },
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.1,        // Rendah = lebih konsisten, kurang kreatif
          'topK': 1,
          'topP': 1,
          'maxOutputTokens': 512,    // Cukup untuk JSON kecil
          'responseMimeType': 'application/json', // Paksa output JSON
        },
        'safetySettings': [
          {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
          {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
          {'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold': 'BLOCK_NONE'},
          {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'BLOCK_NONE'},
        ],
      };

      // Kirim request ke Gemini API
      final response = await http
          .post(
            Uri.parse('$_baseUrl?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        final errBody = jsonDecode(response.body);
        final errMsg = errBody['error']?['message'] ?? 'HTTP ${response.statusCode}';
        return ReceiptScanResult.error('Gemini API error: $errMsg');
      }

      // Parse response Gemini
      final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = responseJson['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        return ReceiptScanResult.error('Gemini tidak mengembalikan hasil.');
      }

      // Ambil teks dari candidate pertama
      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      final rawText = parts?.isNotEmpty == true
          ? (parts![0]['text'] as String? ?? '')
          : '';

      if (rawText.isEmpty) {
        return ReceiptScanResult.error('Gemini mengembalikan respons kosong.');
      }

      // Parse JSON dari Gemini response
      return _parseGeminiResponse(rawText);
    } on SocketException {
      return ReceiptScanResult.error(
        'Tidak ada koneksi internet. Periksa jaringan kamu.',
      );
    } on http.ClientException catch (e) {
      return ReceiptScanResult.error('Network error: ${e.message}');
    } on FormatException catch (e) {
      return ReceiptScanResult.error('Gagal parse respons AI: ${e.message}');
    } catch (e) {
      return ReceiptScanResult.error('Terjadi error: $e');
    }
  }

  /// Parse JSON response dari Gemini menjadi [ReceiptScanResult].
  static ReceiptScanResult _parseGeminiResponse(String rawText) {
    try {
      // Bersihkan respons — kadang Gemini masih menambahkan markdown meski diminta JSON
      String cleanText = rawText.trim();

      // Hapus code fences jika ada (```json ... ```)
      if (cleanText.startsWith('```')) {
        cleanText = cleanText
            .replaceAll(RegExp(r'^```(?:json)?\n?', multiLine: false), '')
            .replaceAll(RegExp(r'\n?```$', multiLine: false), '')
            .trim();
      }

      // Cari JSON object di dalam teks jika masih ada teks lain
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleanText);
      if (jsonMatch == null) {
        return ReceiptScanResult.error(
          'Tidak dapat menemukan JSON dalam respons AI.',
        );
      }

      final data = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;

      // Ekstrak total_amount
      double? totalAmount;
      final rawAmount = data['total_amount'];
      if (rawAmount != null) {
        if (rawAmount is num) {
          totalAmount = rawAmount.toDouble();
        } else if (rawAmount is String) {
          totalAmount = double.tryParse(
            rawAmount.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.'),
          );
        }
        if (totalAmount != null && totalAmount <= 0) totalAmount = null;
      }

      // Ekstrak merchant_name
      final merchantName = data['merchant_name'] as String?;

      // Ekstrak transaction_date
      DateTime? transactionDate;
      final rawDate = data['transaction_date'] as String?;
      if (rawDate != null && rawDate.isNotEmpty) {
        transactionDate = DateTime.tryParse(rawDate);
      }

      // Ekstrak category — validasi harus ada di daftar yang diizinkan
      String? category;
      final rawCategory = data['category'] as String?;
      if (rawCategory != null && _expenseCategories.contains(rawCategory)) {
        category = rawCategory;
      }

      // Ekstrak confidence
      double confidence = 1.0;
      final rawConf = data['confidence'];
      if (rawConf is num) {
        confidence = rawConf.toDouble().clamp(0.0, 1.0);
      }

      return ReceiptScanResult(
        totalAmount: totalAmount,
        merchantName: merchantName?.isNotEmpty == true ? merchantName : null,
        transactionDate: transactionDate,
        suggestedCategory: category,
        confidence: confidence,
        rawText: rawText,
      );
    } on FormatException catch (e) {
      return ReceiptScanResult.error(
        'Gagal membaca respons AI. Format tidak valid: ${e.message}',
      );
    } catch (e) {
      return ReceiptScanResult.error('Error parsing respons AI: $e');
    }
  }
}

