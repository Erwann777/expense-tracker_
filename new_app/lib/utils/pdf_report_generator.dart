import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/currency_model.dart';
import '../models/expense_model.dart';

/// Generates a clean, professional PDF report matching the Expense Tracker app.
/// Supports both Web (browser share/download) and Mobile/Desktop (native sharing).
///
/// Notes on the PDF engine:
/// - Semi-transparent colors (alpha) are NOT rendered by the `pdf` package, so
///   every color below is a solid, pre-blended color.
/// - Only widgets that mix in `SpanningWidget` (Column, Row of rows, etc.) can
///   be split across pages. A `Container` that wraps a long Column cannot, so
///   long lists are emitted as separate widgets in the `MultiPage` body.
/// - Built-in fonts only support Latin-1, so text is sanitised in [_cleanText].
class PdfReportGenerator {
  // ───────────────────────────── Palette (all solid colors) ─────────────────
  static const PdfColor primaryPurple = PdfColor.fromInt(0xFF7C3AED);
  static const PdfColor primaryDark = PdfColor.fromInt(0xFF5B21B6);
  static const PdfColor primaryIndigo = PdfColor.fromInt(0xFF6366F1);
  static const PdfColor purpleSoft = PdfColor.fromInt(0xFFF3E8FF);

  // Hero card tones (pre-blended instead of using transparency)
  static const PdfColor heroTile = PdfColor.fromInt(0xFF6D28D9);
  static const PdfColor heroTrack = PdfColor.fromInt(0xFF8B5CF6);
  static const PdfColor heroLabel = PdfColor.fromInt(0xFFE9D5FF);

  static const PdfColor accentGreen = PdfColor.fromInt(0xFF10B981);
  static const PdfColor greenBadgeBg = PdfColor.fromInt(0xFFD1FAE5);
  static const PdfColor greenText = PdfColor.fromInt(0xFF047857);

  static const PdfColor accentRed = PdfColor.fromInt(0xFFEF4444);
  static const PdfColor redBadgeBg = PdfColor.fromInt(0xFFFEE2E2);
  static const PdfColor redText = PdfColor.fromInt(0xFFB91C1C);

  static const PdfColor accentOrange = PdfColor.fromInt(0xFFF59E0B);

  static const PdfColor cardBg = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor bgMuted = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor rowAltBg = PdfColor.fromInt(0xFFF9FAFB);
  static const PdfColor headerRowBg = PdfColor.fromInt(0xFFF1F5F9);
  static const PdfColor borderColor = PdfColor.fromInt(0xFFE2E8F0);
  static const PdfColor borderLight = PdfColor.fromInt(0xFFF1F5F9);

  static const PdfColor textPrimary = PdfColor.fromInt(0xFF0F172A);
  static const PdfColor textSecondary = PdfColor.fromInt(0xFF475569);
  static const PdfColor textMuted = PdfColor.fromInt(0xFF94A3B8);

  // ───────────────────────────── Helpers ─────────────────────────────────────

  /// Short text-style helper to keep the widget tree readable.
  static pw.TextStyle _ts(
    double size, {
    PdfColor color = textPrimary,
    bool bold = false,
    double? letterSpacing,
  }) {
    return pw.TextStyle(
      fontSize: size,
      color: color,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      letterSpacing: letterSpacing,
    );
  }

  /// Keeps only characters the built-in PDF fonts can draw (Latin-1) and maps
  /// common typographic characters to ASCII. Returns [fallback] if nothing is
  /// left (e.g. the text was only emojis).
  static String _cleanText(String text, {String fallback = ''}) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      switch (rune) {
        case 0x09:
        case 0x0A:
        case 0x0D:
          buffer.write(' ');
          break;
        case 0x2018:
        case 0x2019:
          buffer.write("'");
          break;
        case 0x201C:
        case 0x201D:
          buffer.write('"');
          break;
        case 0x2013:
        case 0x2014:
          buffer.write('-');
          break;
        case 0x2026:
          buffer.write('...');
          break;
        default:
          if (rune >= 0x20 && rune <= 0xFF) buffer.writeCharCode(rune);
      }
    }
    final cleaned = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  /// Currency symbols such as the euro sign are outside Latin-1, so fall back
  /// to the ISO currency code (e.g. "EUR") whenever the symbol can't be drawn.
  static String _pdfSafeSymbol(String symbol, String code) {
    final trimmed = symbol.trim();
    final cleaned = _cleanText(trimmed);
    if (cleaned.isEmpty || cleaned.length != trimmed.length) {
      return code.toUpperCase();
    }
    return cleaned;
  }

  static String _fmt(double amount, String symbol) {
    final prefix = symbol.isEmpty ? '' : '$symbol ';
    return '$prefix${NumberFormat('#,##0.00').format(amount)}';
  }

  /// App-matched category color mapping.
  static PdfColor _getCategoryColor(String category) {
    final cat = category.toLowerCase().trim();
    if (cat.contains('food') ||
        cat.contains('dining') ||
        cat.contains('restaurant')) {
      return const PdfColor.fromInt(0xFFFF6B6B);
    } else if (cat.contains('transport') ||
        cat.contains('car') ||
        cat.contains('fuel')) {
      return const PdfColor.fromInt(0xFF4ECDC4);
    } else if (cat.contains('shopping') || cat.contains('mall')) {
      return const PdfColor.fromInt(0xFFFFBE0B);
    } else if (cat.contains('entertain') || cat.contains('movie')) {
      return const PdfColor.fromInt(0xFFA855F7);
    } else if (cat.contains('health') ||
        cat.contains('medical') ||
        cat.contains('doctor')) {
      return const PdfColor.fromInt(0xFFEC4899);
    } else if (cat.contains('educat') ||
        cat.contains('school') ||
        cat.contains('course')) {
      return const PdfColor.fromInt(0xFF3B82F6);
    } else if (cat.contains('bill') ||
        cat.contains('utilit') ||
        cat.contains('electric')) {
      return const PdfColor.fromInt(0xFF06B6D4);
    } else if (cat.contains('grocer') || cat.contains('market')) {
      return accentGreen;
    } else if (cat.contains('travel') ||
        cat.contains('vacation') ||
        cat.contains('flight')) {
      return accentOrange;
    } else if (cat.contains('goal') || cat.contains('saving')) {
      return primaryPurple;
    } else if (cat.contains('salary') ||
        cat.contains('bonus') ||
        cat.contains('income')) {
      return accentGreen;
    }
    return primaryIndigo;
  }

  /// Rounded progress bar built from plain containers (works on every version
  /// of the `pdf` package and doesn't depend on clipping).
  static pw.Widget _progressBar({
    required double value,
    required PdfColor color,
    required PdfColor track,
    double height = 6,
  }) {
    final double v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    final radius = pw.BorderRadius.all(pw.Radius.circular(height / 2));
    final int fill = (v * 1000).round().clamp(1, 1000).toInt();
    final fillColor = v <= 0 ? track : color;

    return pw.Container(
      height: height,
      decoration: pw.BoxDecoration(color: track, borderRadius: radius),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: fill,
            child: pw.Container(
              height: height,
              decoration:
                  pw.BoxDecoration(color: fillColor, borderRadius: radius),
            ),
          ),
          if (fill < 1000)
            pw.Expanded(flex: 1000 - fill, child: pw.SizedBox(height: height)),
        ],
      ),
    );
  }

  /// The `pdf` package has no `KeepTogether` widget. MultiPage only splits
  /// widgets that mix in `SpanningWidget` (a bare Column/Wrap); any other
  /// widget, such as a Container, is moved to the next page as one block.
  /// Wrapping a Column in a Container therefore keeps its children together.
  static pw.Widget _keepTogether(List<pw.Widget> children) {
    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  static pw.Widget _pill(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: bgMuted,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: borderColor, width: 0.8),
      ),
      child: pw.Text(text, style: _ts(8, color: textSecondary)),
    );
  }

  static pw.Widget _sectionHeader({
    required String title,
    required String pillText,
    required PdfColor accent,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Row(
          children: [
            pw.Container(
              width: 3.5,
              height: 14,
              decoration: pw.BoxDecoration(
                color: accent,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              title,
              style: _ts(10.5, bold: true, letterSpacing: 0.6),
            ),
          ],
        ),
        _pill(pillText),
      ],
    );
  }

  // ───────────────────────────── Public API ──────────────────────────────────

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
    final symbol = _pdfSafeSymbol(currencyInfo.symbol, currency);
    final dateFormat = DateFormat('MMM dd, yyyy');
    final periodLabel =
        '${dateFormat.format(startDate)}  -  ${dateFormat.format(endDate)}';
    final netBalance = totalIncome - totalExpense;
    final expenseCount = transactions.where((t) => t.isExpense).length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        header: (context) => _buildHeader(
          userName: _cleanText(userName, fallback: 'User'),
          period: periodLabel,
          genDate: dateFormat.format(DateTime.now()),
        ),
        footer: (context) => _buildFooter(context),
        build: (context) {
          final widgets = <pw.Widget>[];

          // 1. Hero summary card
          widgets.add(
            _buildHeroSummaryCard(
              totalIncome: totalIncome,
              totalExpense: totalExpense,
              netBalance: netBalance,
              symbol: symbol,
              budget: budget,
            ),
          );
          widgets.add(pw.SizedBox(height: 14));

          // 2. KPI row
          widgets.add(
            _buildKpiMetricsRow(
              totalIncome: totalIncome,
              totalExpense: totalExpense,
              transactionCount: transactions.length,
              expenseCount: expenseCount,
              symbol: symbol,
            ),
          );
          widgets.add(pw.SizedBox(height: 20));

          // 3. Expense breakdown
          if (expenseCategoryTotals.isNotEmpty) {
            widgets.addAll(
              _buildCategorySection(
                title: 'EXPENSE BREAKDOWN BY CATEGORY',
                totals: expenseCategoryTotals,
                grandTotal: totalExpense,
                symbol: symbol,
                isIncome: false,
              ),
            );
            widgets.add(pw.SizedBox(height: 20));
          }

          // 4. Income breakdown
          if (incomeCategoryTotals.isNotEmpty) {
            widgets.addAll(
              _buildCategorySection(
                title: 'INCOME BREAKDOWN BY CATEGORY',
                totals: incomeCategoryTotals,
                grandTotal: totalIncome,
                symbol: symbol,
                isIncome: true,
              ),
            );
            widgets.add(pw.SizedBox(height: 20));
          }

          // 5. Transactions table
          if (transactions.isNotEmpty) {
            widgets.addAll(
              _buildTransactionsSection(
                transactions: transactions,
                symbol: symbol,
              ),
            );
          }

          return widgets;
        },
      ),
    );

    final pdfBytes = await pdf.save();
    final fileName =
        'ExpenseTracker_Report_${DateFormat('yyyyMMdd').format(startDate)}_to_${DateFormat('yyyyMMdd').format(endDate)}.pdf';

    if (kIsWeb) {
      // Web: share / download directly from memory
      final xFile = XFile.fromData(
        pdfBytes,
        mimeType: 'application/pdf',
        name: fileName,
      );
      await Share.shareXFiles(
        [xFile],
        subject: 'Expense Tracker - Financial Report',
      );
    } else {
      // Mobile / Desktop: save to temp directory and share
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: fileName)],
        subject: 'Expense Tracker - Financial Report',
      );
    }
  }

  // ───────────────────────────── Header & Footer ─────────────────────────────

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
          bottom: pw.BorderSide(color: primaryPurple, width: 1.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Logo + name
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 38,
                height: 38,
                decoration: const pw.BoxDecoration(
                  color: primaryPurple,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Center(
                  child: pw.Text(
                    'ET',
                    style: _ts(16, color: PdfColors.white, bold: true),
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Expense Tracker', style: _ts(19, bold: true)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'FINANCIAL ANALYTICS & INSIGHTS',
                    style: _ts(
                      7.5,
                      color: primaryPurple,
                      bold: true,
                      letterSpacing: 1.3,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // User + period
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    'Prepared for: ',
                    style: _ts(8.5, color: textMuted),
                  ),
                  pw.Text(userName, style: _ts(9.5, bold: true)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: purpleSoft,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Text(
                  period,
                  style: _ts(8, color: primaryDark, bold: true),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text('Exported: $genDate', style: _ts(7, color: textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
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
            'Expense Tracker  |  Confidential Financial Report',
            style: _ts(7.5, color: textMuted),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: _ts(8, color: textSecondary, bold: true),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── 1. Hero summary card ────────────────────────

  static pw.Widget _buildHeroSummaryCard({
    required double totalIncome,
    required double totalExpense,
    required double netBalance,
    required String symbol,
    double? budget,
  }) {
    final sign = netBalance > 0 ? '+' : (netBalance < 0 ? '-' : '');

    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: const pw.BoxDecoration(
        color: primaryPurple,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(16)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'NET BALANCE',
            style: _ts(9.5, color: heroLabel, bold: true, letterSpacing: 1.5),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '$sign${_fmt(netBalance.abs(), symbol)}',
            style: _ts(28, color: PdfColors.white, bold: true),
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _buildHeroTile(
                  label: 'Total Income',
                  amount: _fmt(totalIncome, symbol),
                  iconText: '+',
                  iconBg: accentGreen,
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _buildHeroTile(
                  label: 'Total Expense',
                  amount: _fmt(totalExpense, symbol),
                  iconText: '-',
                  iconBg: accentRed,
                ),
              ),
            ],
          ),
          if (budget != null && budget > 0) ...[
            pw.SizedBox(height: 10),
            _buildBudgetProgressBar(
              budget: budget,
              spent: totalExpense,
              symbol: symbol,
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildHeroTile({
    required String label,
    required String amount,
    required String iconText,
    required PdfColor iconBg,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const pw.BoxDecoration(
        color: heroTile,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 26,
            height: 26,
            decoration: pw.BoxDecoration(
              color: iconBg,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Center(
              child: pw.Text(
                iconText,
                style: _ts(15, color: PdfColors.white, bold: true),
              ),
            ),
          ),
          pw.SizedBox(width: 9),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label, style: _ts(8, color: heroLabel)),
                pw.SizedBox(height: 2),
                pw.Text(
                  amount,
                  style: _ts(13, color: PdfColors.white, bold: true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildBudgetProgressBar({
    required double budget,
    required double spent,
    required String symbol,
  }) {
    final double remaining =
        (budget - spent).clamp(0.0, double.infinity).toDouble();
    final ratio = spent / budget;
    final isOverBudget = spent > budget;
    final pctString = '${(ratio * 100).toStringAsFixed(1)}%';
    final barColor = isOverBudget
        ? accentRed
        : (ratio > 0.8 ? accentOrange : accentGreen);

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const pw.BoxDecoration(
        color: heroTile,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'Budget: ${_fmt(budget, symbol)}',
                style: _ts(8.5, color: PdfColors.white),
              ),
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    isOverBudget
                        ? 'Over budget by ${_fmt(spent - budget, symbol)}'
                        : 'Remaining: ${_fmt(remaining, symbol)}',
                    style: _ts(
                      8.5,
                      bold: true,
                      color: isOverBudget
                          ? const PdfColor.fromInt(0xFFFCA5A5)
                          : const PdfColor.fromInt(0xFF86EFAC),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: isOverBudget ? accentRed : primaryDark,
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      pctString,
                      style: _ts(7.5, color: PdfColors.white, bold: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 7),
          _progressBar(
            value: ratio,
            color: barColor,
            track: heroTrack,
            height: 6,
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── 2. KPI row ──────────────────────────────────

  static pw.Widget _buildKpiMetricsRow({
    required double totalIncome,
    required double totalExpense,
    required int transactionCount,
    required int expenseCount,
    required String symbol,
  }) {
    final double savingsRate = totalIncome > 0
        ? (((totalIncome - totalExpense) / totalIncome) * 100)
            .clamp(-100.0, 100.0)
            .toDouble()
        : 0.0;
    // Average over expense transactions only (income shouldn't dilute it).
    final avgSpend = expenseCount > 0 ? (totalExpense / expenseCount) : 0.0;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _buildKpiBox(
            title: 'TRANSACTIONS',
            value: '$transactionCount',
            accentColor: primaryPurple,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _buildKpiBox(
            title: 'SAVINGS RATE',
            value: '${savingsRate.toStringAsFixed(1)}%',
            accentColor: savingsRate >= 0 ? accentGreen : accentRed,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _buildKpiBox(
            title: 'AVG / EXPENSE',
            value: _fmt(avgSpend, symbol),
            accentColor: accentOrange,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildKpiBox({
    required String title,
    required String value,
    required PdfColor accentColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: pw.BoxDecoration(
        color: cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: borderColor, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 6,
                height: 6,
                decoration: pw.BoxDecoration(
                  color: accentColor,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Text(
                title,
                style: _ts(7, color: textMuted, bold: true, letterSpacing: 0.5),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(value, style: _ts(11, bold: true), maxLines: 1),
        ],
      ),
    );
  }

  // ───────────────────────────── 3 & 4. Category breakdown ───────────────────

  /// Returns a list of widgets (header + one widget per category) so that
  /// `MultiPage` can break the section across pages if there are many
  /// categories.
  static List<pw.Widget> _buildCategorySection({
    required String title,
    required Map<String, double> totals,
    required double grandTotal,
    required String symbol,
    required bool isIncome,
  }) {
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final header = pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: _sectionHeader(
        title: title,
        pillText:
            '${entries.length} ${entries.length == 1 ? 'category' : 'categories'}',
        accent: isIncome ? accentGreen : primaryPurple,
      ),
    );

    final rows = <pw.Widget>[
      for (final entry in entries)
        _buildCategoryRow(
          name: _cleanText(entry.key, fallback: 'Other'),
          amount: entry.value,
          pct: grandTotal > 0 ? entry.value / grandTotal : 0.0,
          symbol: symbol,
        ),
    ];

    // Keep the header together with the first row (no orphan headers).
    return [
      _keepTogether([header, rows.first]),
      ...rows.skip(1),
    ];
  }

  static pw.Widget _buildCategoryRow({
    required String name,
    required double amount,
    required double pct,
    required String symbol,
  }) {
    final catColor = _getCategoryColor(name);

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 9, top: 1),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Row(
                children: [
                  pw.Container(
                    width: 8,
                    height: 8,
                    decoration: pw.BoxDecoration(
                      color: catColor,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(name, style: _ts(9, bold: true)),
                ],
              ),
              pw.Row(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: headerRowBg,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      '${(pct * 100).toStringAsFixed(1)}%',
                      style: _ts(8, color: textSecondary),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    _fmt(amount, symbol),
                    style: _ts(9.5, bold: true),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          _progressBar(
            value: pct,
            color: catColor,
            track: headerRowBg,
            height: 6,
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── 5. Transactions table ───────────────────────

  /// Returns header + one widget per row so the table can flow over as many
  /// pages as needed (a Container wrapping all rows would crash on long
  /// reports with "widget too big and cannot be separated").
  static List<pw.Widget> _buildTransactionsSection({
    required List<ExpenseModel> transactions,
    required String symbol,
  }) {
    final sorted = List<ExpenseModel>.from(transactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    final sectionHeader = pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: _sectionHeader(
        title: 'TRANSACTION HISTORY',
        pillText: '${transactions.length} items',
        accent: primaryPurple,
      ),
    );

    final tableHeader = pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: const pw.BoxDecoration(
        color: headerRowBg,
        borderRadius: pw.BorderRadius.only(
          topLeft: pw.Radius.circular(8),
          topRight: pw.Radius.circular(8),
        ),
      ),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 44, child: pw.Text('TYPE', style: _headStyle())),
          pw.Expanded(
            flex: 3,
            child: pw.Text('DESCRIPTION', style: _headStyle()),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text('CATEGORY', style: _headStyle()),
          ),
          pw.SizedBox(width: 72, child: pw.Text('DATE', style: _headStyle())),
          pw.SizedBox(
            width: 78,
            child: pw.Text(
              'AMOUNT',
              textAlign: pw.TextAlign.right,
              style: _headStyle(),
            ),
          ),
        ],
      ),
    );

    final rows = <pw.Widget>[
      for (var i = 0; i < sorted.length; i++)
        _buildTransactionRow(sorted[i], i, symbol),
    ];

    return [
      // Keep section title + table header + first row together.
      _keepTogether([sectionHeader, tableHeader, rows.first]),
      ...rows.skip(1),
    ];
  }

  static pw.TextStyle _headStyle() =>
      _ts(7.5, color: textMuted, bold: true, letterSpacing: 0.4);

  static pw.Widget _buildTransactionRow(
    ExpenseModel e,
    int index,
    String symbol,
  ) {
    final isInc = e.isIncome;
    final isGoal = e.isGoalSaving;

    final amountColor =
        isGoal ? primaryPurple : (isInc ? greenText : redText);
    final amountPrefix = isInc ? '+' : '-';

    final badgeBg =
        isGoal ? purpleSoft : (isInc ? greenBadgeBg : redBadgeBg);
    final badgeText = isGoal ? 'GOAL' : (isInc ? 'INC' : 'EXP');
    final badgeTextColor =
        isGoal ? primaryDark : (isInc ? greenText : redText);

    final title = _cleanText(e.title, fallback: 'Untitled');
    final category = _cleanText(e.category, fallback: 'Other');
    final note = e.note == null ? '' : _cleanText(e.note!);

    // NOTE: color goes inside the decoration - Container asserts if both
    // `color` and `decoration` are passed.
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: pw.BoxDecoration(
        color: index.isOdd ? rowAltBg : cardBg,
        border: const pw.Border(
          bottom: pw.BorderSide(color: borderLight, width: 0.6),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Type badge
          pw.SizedBox(
            width: 44,
            child: pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: badgeBg,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  badgeText,
                  style: _ts(7, color: badgeTextColor, bold: true),
                ),
              ),
            ),
          ),

          // Title & note
          pw.Expanded(
            flex: 3,
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(right: 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(title, style: _ts(8.5, bold: true), maxLines: 1),
                  if (note.isNotEmpty) ...[
                    pw.SizedBox(height: 1),
                    pw.Text(
                      note,
                      style: _ts(7, color: textMuted),
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Category with dot
          pw.Expanded(
            flex: 2,
            child: pw.Row(
              children: [
                pw.Container(
                  width: 5,
                  height: 5,
                  decoration: pw.BoxDecoration(
                    color: _getCategoryColor(category),
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Text(
                    category,
                    style: _ts(8, color: textSecondary),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),

          // Date
          pw.SizedBox(
            width: 72,
            child: pw.Text(
              DateFormat('MMM dd, yyyy').format(e.date),
              style: _ts(7.5, color: textMuted),
            ),
          ),

          // Amount
          pw.SizedBox(
            width: 78,
            child: pw.Text(
              '$amountPrefix${_fmt(e.amount, symbol)}',
              textAlign: pw.TextAlign.right,
              style: _ts(9, color: amountColor, bold: true),
            ),
          ),
        ],
      ),
    );
  }
}