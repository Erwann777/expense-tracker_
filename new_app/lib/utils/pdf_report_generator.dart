import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/currency_model.dart';
import '../models/expense_model.dart';

/// Generates a professional PDF report matching the app's visual style.
/// Supports both Web (browser download) and Mobile/Desktop (native file sharing).
class PdfReportGenerator {
  // App-matched color palette
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF6366F1); // Indigo
  static const PdfColor primaryDark = PdfColor.fromInt(0xFF4F46E5);
  static const PdfColor accentPurple = PdfColor.fromInt(0xFF7C3AED);
  static const PdfColor greenColor = PdfColor.fromInt(0xFF10B981);
  static const PdfColor greenLight = PdfColor.fromInt(0xFFE6F4EA);
  static const PdfColor redColor = PdfColor.fromInt(0xFFEF4444);
  static const PdfColor redLight = PdfColor.fromInt(0xFFFEE2E2);
  static const PdfColor cardBg = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor bgMuted = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor borderColor = PdfColor.fromInt(0xFFE2E8F0);
  static const PdfColor textPrimary = PdfColor.fromInt(0xFF1E293B);
  static const PdfColor textSecondary = PdfColor.fromInt(0xFF64748B);
  static const PdfColor textMuted = PdfColor.fromInt(0xFF94A3B8);

  /// Strips emojis and unsupported non-Latin characters to prevent PDF glyph errors
  static String _cleanText(String text) {
    if (text.isEmpty) return text;
    final cleaned = text
        .replaceAll(
          RegExp(
            r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE00}-\u{FE0F}]',
            unicode: true,
          ),
          '',
        )
        .trim();
    return cleaned.isEmpty ? 'Item' : cleaned;
  }

  static String _fmt(double amount, String symbol) {
    final cleanSym = _cleanText(symbol);
    final prefix = cleanSym.isEmpty ? '' : '$cleanSym ';
    return '$prefix${NumberFormat('#,##0.00').format(amount)}';
  }

  static Future<void> generateAndShare({
    required String userName,
    required String currency,
    required DateTime startDate,
    required DateTime endDate,
    required double totalExpense,
    required double totalIncome,
    required Map<String, double> expenseCategoryTotals,
    required Map<String, double> incomeCategoryTotals,
    required List<ExpenseModel> transactions,
    double? budget,
  }) async {
    final pdf = pw.Document();
    final currencyInfo = AppCurrencies.getByCode(currency);
    final symbol = currencyInfo.symbol;
    final dateFormat = DateFormat('MMM dd, yyyy');
    final periodLabel =
        '${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}';
    final netBalance = totalIncome - totalExpense;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader(
          userName: _cleanText(userName),
          period: periodLabel,
          genDate: dateFormat.format(DateTime.now()),
        ),
        footer: (context) => _buildFooter(context),
        build: (context) {
          final widgets = <pw.Widget>[];

          // 1. Hero Summary Card (matches App's Net Balance card)
          widgets.add(_buildHeroSummaryCard(
            totalIncome: totalIncome,
            totalExpense: totalExpense,
            netBalance: netBalance,
            symbol: symbol,
            budget: budget,
          ));

          widgets.add(pw.SizedBox(height: 18));

          // 2. Expense Category Breakdown (matches App's category breakdown)
          if (expenseCategoryTotals.isNotEmpty) {
            widgets.add(_buildCategorySection(
              title: 'EXPENSE BREAKDOWN',
              totals: expenseCategoryTotals,
              grandTotal: totalExpense,
              symbol: symbol,
              barColor: redColor,
            ));
            widgets.add(pw.SizedBox(height: 18));
          }

          // 3. Income Category Breakdown
          if (incomeCategoryTotals.isNotEmpty) {
            widgets.add(_buildCategorySection(
              title: 'INCOME BREAKDOWN',
              totals: incomeCategoryTotals,
              grandTotal: totalIncome,
              symbol: symbol,
              barColor: greenColor,
            ));
            widgets.add(pw.SizedBox(height: 18));
          }

          // 4. Transactions List (matches App's recent transactions)
          if (transactions.isNotEmpty) {
            widgets.add(_buildTransactionsSection(
              transactions: transactions,
              symbol: symbol,
            ));
          }

          return widgets;
        },
      ),
    );

    final pdfBytes = await pdf.save();
    final fileName =
        'FinFlow_Report_${DateFormat('yyyyMMdd').format(startDate)}_to_${DateFormat('yyyyMMdd').format(endDate)}.pdf';

    if (kIsWeb) {
      // Web: Download directly via XFile.fromData
      final xFile = XFile.fromData(
        pdfBytes,
        mimeType: 'application/pdf',
        name: fileName,
      );
      await Share.shareXFiles([xFile], subject: 'FinFlow Financial Report');
    } else {
      // Mobile / Desktop: Save to temp directory and share
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
        subject: 'FinFlow Financial Report',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // HEADER & FOOTER
  // ─────────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildHeader({
    required String userName,
    required String period,
    required String genDate,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: borderColor, width: 1.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'FinFlow',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'FINANCIAL ANALYTICS & INSIGHTS',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                userName,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: pw.BoxDecoration(
                  color: bgMuted,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: borderColor),
                ),
                child: pw.Text(
                  period,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryDark,
                  ),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Generated: $genDate',
                style: const pw.TextStyle(fontSize: 7.5, color: textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: borderColor, width: 0.8),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'FinFlow Expense Tracker  •  Confidential Financial Report',
            style: const pw.TextStyle(fontSize: 8, color: textMuted),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 1. HERO SUMMARY CARD (Matches App's Net Balance Gradient Card)
  // ─────────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildHeroSummaryCard({
    required double totalIncome,
    required double totalExpense,
    required double netBalance,
    required String symbol,
    double? budget,
  }) {
    final isPositive = netBalance >= 0;

    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: primaryDark,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'NET BALANCE',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFFE0E7FF),
              letterSpacing: 1.5,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '${isPositive ? '+' : ''}${_fmt(netBalance, symbol)}',
            style: pw.TextStyle(
              fontSize: 26,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 14),

          // Inner split card for Income & Expense
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0x28FFFFFF),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Total Income',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFFD1FAE5),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        _fmt(totalIncome, symbol),
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  width: 1,
                  height: 30,
                  color: const PdfColor.fromInt(0x40FFFFFF),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Total Expense',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFFFEE2E2),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        _fmt(totalExpense, symbol),
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Budget status bar if set
          if (budget != null && budget > 0) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0x25FFFFFF),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Monthly Budget: ${_fmt(budget, symbol)}',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.Text(
                    'Remaining: ${_fmt((budget - totalExpense).clamp(0, double.infinity), symbol)}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF86EFAC),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. CATEGORY BREAKDOWN (Matches App's Category card layout)
  // ─────────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildCategorySection({
    required String title,
    required Map<String, double> totals,
    required double grandTotal,
    required String symbol,
    required PdfColor barColor,
  }) {
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
        border: pw.Border.all(color: borderColor, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: textPrimary,
                  letterSpacing: 0.8,
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: bgMuted,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: borderColor),
                ),
                child: pw.Text(
                  '${entries.length} categories',
                  style: const pw.TextStyle(fontSize: 8.5, color: textSecondary),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),

          ...entries.map((entry) {
            final pct = grandTotal > 0 ? entry.value / grandTotal : 0.0;
            final pctStr = '${(pct * 100).toStringAsFixed(1)}%';

            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        _cleanText(entry.key),
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      pw.Row(
                        children: [
                          pw.Text(
                            pctStr,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: textSecondary,
                            ),
                          ),
                          pw.SizedBox(width: 10),
                          pw.Text(
                            _fmt(entry.value, symbol),
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.ClipRRect(
                    horizontalRadius: 3,
                    verticalRadius: 3,
                    child: pw.LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: borderColor,
                      valueColor: barColor,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // 3. TRANSACTIONS SECTION (Matches App's clean transaction list)
  // ─────────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildTransactionsSection({
    required List<ExpenseModel> transactions,
    required String symbol,
  }) {
    final sorted = List<ExpenseModel>.from(transactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
        border: pw.Border.all(color: borderColor, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TRANSACTIONS',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: textPrimary,
                  letterSpacing: 0.8,
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: bgMuted,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: borderColor),
                ),
                child: pw.Text(
                  '${transactions.length} total',
                  style: const pw.TextStyle(fontSize: 8.5, color: textSecondary),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),

          ...sorted.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final isInc = e.isIncome;
            final amountColor = isInc ? greenColor : redColor;
            final amountPrefix = isInc ? '+' : '-';

            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 7),
              decoration: pw.BoxDecoration(
                border: i < sorted.length - 1
                    ? const pw.Border(
                        bottom: pw.BorderSide(color: borderColor, width: 0.6),
                      )
                    : null,
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Type badge pill
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: isInc ? greenLight : redLight,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                    ),
                    child: pw.Text(
                      e.isGoalSaving ? 'GOAL' : (isInc ? 'IN' : 'EXP'),
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: e.isGoalSaving ? accentPurple : amountColor,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),

                  // Title and Category + Date
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          _cleanText(e.title),
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: textPrimary,
                          ),
                          maxLines: 1,
                        ),
                        pw.SizedBox(height: 1.5),
                        pw.Text(
                          '${_cleanText(e.category)}  •  ${DateFormat('MMM dd, yyyy').format(e.date)}',
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Amount
                  pw.Text(
                    '$amountPrefix${_fmt(e.amount, symbol)}',
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: amountColor,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
