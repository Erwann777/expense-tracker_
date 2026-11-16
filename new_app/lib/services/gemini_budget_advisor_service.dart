import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/expense_model.dart';

/// Result from the AI Budget Advisor.
class BudgetAdviceResult {
  final String? advice;
  final String? errorMessage;

  const BudgetAdviceResult({this.advice, this.errorMessage});

  factory BudgetAdviceResult.error(String message) =>
      BudgetAdviceResult(errorMessage: message);

  bool get hasError => errorMessage != null;
}

/// Sends the user's spending data to Groq AI and returns personalised
/// budget advice in plain, friendly language.
///
/// Groq uses an OpenAI-compatible Chat Completions API with extremely
/// fast LPU inference — typical response time is under 2 seconds.
class GeminiBudgetAdvisorService {
  // Groq Chat Completions endpoint (OpenAI-compatible)
  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  // Models endpoint — used to find the best available model at runtime
  static const String _modelsUrl = 'https://api.groq.com/openai/v1/models';

  // Preferred models in priority order (first available one is used).
  // Update this list if Groq deprecates models again.
  static const List<String> _preferredModels = [
    'llama-3.3-70b-versatile',
    'llama-3.1-70b-versatile',
    'llama3-70b-8192',
    'gemma2-9b-it',
    'qwen-qwq-32b',
    'mistral-saba-24b',
    'mixtral-8x7b-32768',
  ];

  /// Fetches the list of available Groq models and returns the first one
  /// that matches our [_preferredModels] priority list.
  /// Falls back to the first available model if none match.
  static Future<String?> _pickBestModel(String apiKey) async {
    try {
      final response = await http
          .get(
            Uri.parse(_modelsUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'];
      if (data is! List) return null;

      // Build a set of available model IDs
      final available = data
          .whereType<Map>()
          .map((m) => m['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      // Pick the first preferred model that is actually available
      for (final preferred in _preferredModels) {
        if (available.contains(preferred)) return preferred;
      }

      // Last resort: return any chat model that isn't audio/image
      return available
          .where((id) =>
              !id.contains('whisper') &&
              !id.contains('tts') &&
              !id.contains('orpheus'))
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Analyses [expenses] for the given [month]/[year] and returns advice.
  ///
  /// [currency]      – 3-letter ISO code shown to the user (e.g. "MYR").
  /// [monthlyBudget] – the user's budget cap (0 means none set).
  static Future<BudgetAdviceResult> getAdvice({
    required List<ExpenseModel> expenses,
    required int year,
    required int month,
    required String currency,
    required double monthlyBudget,
  }) async {
    final apiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    if (apiKey.isEmpty || apiKey == 'your_groq_api_key_here') {
      return BudgetAdviceResult.error(
        'Groq API key is not configured. Add GROQ_API_KEY to your .env file.\n'
        'Get a free key at: console.groq.com',
      );
    }

    // ── Aggregate the data ─────────────────────────────────────────────────
    final monthExpenses =
        expenses.where((e) => e.date.year == year && e.date.month == month);
    final expenseList = monthExpenses.where((e) => e.isExpense).toList();
    final incomeList  = monthExpenses.where((e) => e.isIncome).toList();

    if (expenseList.isEmpty && incomeList.isEmpty) {
      return BudgetAdviceResult.error(
        'No transactions found for this month. Add some expenses first!',
      );
    }

    final totalExpense = expenseList.fold(0.0, (sum, e) => sum + e.amount);
    final totalIncome  = incomeList.fold(0.0,  (sum, e) => sum + e.amount);
    final netBalance   = totalIncome - totalExpense;

    // Days in selected month & days elapsed so far
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final today = DateTime.now();
    final isCurrentMonth = today.year == year && today.month == month;
    final daysElapsed = isCurrentMonth
        ? today.day
        : daysInMonth; // kalau bulan lepas, anggap full month
    final daysRemaining = isCurrentMonth
        ? (daysInMonth - today.day).clamp(0, daysInMonth)
        : 0;

    // Daily spend rate & recommended daily budget
    final dailySpendRate =
        daysElapsed > 0 ? totalExpense / daysElapsed : 0.0;
    final dailyBudget = monthlyBudget > 0
        ? monthlyBudget / daysInMonth
        : (totalIncome > 0 ? totalIncome / daysInMonth : 0.0);
    final remainingBudget = monthlyBudget > 0
        ? (monthlyBudget - totalExpense).clamp(0.0, double.infinity)
        : (totalIncome - totalExpense).clamp(0.0, double.infinity);
    final safeDaily = daysRemaining > 0
        ? remainingBudget / daysRemaining
        : 0.0;

    // Category breakdown — top 5 only to keep the prompt short
    final categoryTotals = <String, double>{};
    for (final e in expenseList) {
      categoryTotals[e.category] = (categoryTotals[e.category] ?? 0) + e.amount;
    }
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategories = sortedCategories
        .take(5)
        .map((e) => '${e.key}: ${e.value.toStringAsFixed(2)}')
        .join(', ');

    // Previous month
    final prevMonth = month == 1 ? 12 : month - 1;
    final prevYear  = month == 1 ? year - 1 : year;
    final prevTotal = expenses
        .where((e) =>
            e.isExpense &&
            e.date.year == prevYear &&
            e.date.month == prevMonth)
        .fold(0.0, (sum, e) => sum + e.amount);

    final budgetNote = monthlyBudget > 0
        ? 'Monthly Budget: $currency ${monthlyBudget.toStringAsFixed(2)} '
          '(${totalExpense <= monthlyBudget ? "on track ✅" : "over budget ❗"})'
        : 'No budget set';

    final dailyNote = dailyBudget > 0
        ? 'Daily budget: $currency ${dailyBudget.toStringAsFixed(2)} | '
          'Actual daily spend: $currency ${dailySpendRate.toStringAsFixed(2)} | '
          'Days elapsed: $daysElapsed/$daysInMonth | '
          'Days remaining: $daysRemaining | '
          'Safe to spend per day for rest of month: $currency ${safeDaily.toStringAsFixed(2)}'
        : 'Daily spend rate so far: $currency ${dailySpendRate.toStringAsFixed(2)}/day';

    final userMessage =
        'Analyse my spending for ${_monthName(month)} $year and give brief, '
        'friendly financial advice.\n\n'
        'Currency: $currency\n'
        'Income: ${totalIncome.toStringAsFixed(2)} | '
        'Expense: ${totalExpense.toStringAsFixed(2)} | '
        'Net: ${netBalance.toStringAsFixed(2)}\n'
        '$budgetNote\n'
        '$dailyNote\n'
        'Previous month expense: ${prevTotal.toStringAsFixed(2)}\n'
        'Top expense categories: $topCategories\n\n'
        'Reply with exactly 5 short sections using these emoji headers:\n'
        '📊 Overview – 1 sentence about the month overall\n'
        '📅 Daily Budget – Tell me exactly how much I can spend per day for the rest of this month in $currency, based on my remaining budget/income. Be specific with the number.\n'
        '🔍 Top Spending – 2 sentences on the biggest spending categories\n'
        '💡 Tips – 3 actionable bullet-point tips to save money\n'
        '🎯 Motivation – 1 encouraging closing sentence\n\n'
        'Keep the total response under 250 words. '
        'Write in plain, conversational English. '
        'Always use $currency as the currency symbol for all amounts.';

    // Pick the best available Groq model at runtime
    final model = await _pickBestModel(apiKey);
    if (model == null) {
      return BudgetAdviceResult.error(
        'Could not connect to Groq or find a compatible model.\n'
        'Check your API key at console.groq.com and try again.',
      );
    }

    final requestBody = {
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a friendly, practical personal finance advisor. '
              'Give concise, specific advice based only on the data provided. '
              'Never invent numbers. Never use financial jargon.',
        },
        {
          'role': 'user',
          'content': userMessage,
        },
      ],
      'temperature': 0.7,
      'max_tokens': 400,
      'top_p': 0.9,
    };

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 30)); // Groq is fast — 30s is plenty

      if (response.statusCode != 200) {
        final errMsg = _apiErrorMessage(response);
        return BudgetAdviceResult.error('Groq API error: $errMsg');
      }

      // Parse OpenAI-compatible response format
      final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = responseJson['choices'];
      if (choices is! List || choices.isEmpty) {
        return BudgetAdviceResult.error(
            'Groq did not return a result. Please try again.');
      }

      final message = (choices.first as Map?)?['message'];
      final text    = (message as Map?)?['content']?.toString() ?? '';

      if (text.trim().isEmpty) {
        return BudgetAdviceResult.error(
            'Groq returned an empty response. Please try again.');
      }

      return BudgetAdviceResult(advice: text.trim());
    } on SocketException {
      return BudgetAdviceResult.error(
        'No internet connection. Check your network and try again.',
      );
    } on TimeoutException {
      return BudgetAdviceResult.error(
        'The request timed out. Please try again.',
      );
    } on http.ClientException catch (e) {
      return BudgetAdviceResult.error('Network error: ${e.message}');
    } catch (e) {
      return BudgetAdviceResult.error('An unexpected error occurred: $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _monthName(int month) => [
        '',
        'January',   'February', 'March',    'April',
        'May',       'June',     'July',      'August',
        'September', 'October',  'November',  'December',
      ][month];

  static String _apiErrorMessage(http.Response response) {
    var msg = 'HTTP ${response.statusCode}';
    try {
      final body = jsonDecode(response.body);
      // Groq uses OpenAI error format: { "error": { "message": "..." } }
      if (body is Map<String, dynamic> &&
          body['error'] is Map<String, dynamic>) {
        msg = (body['error'] as Map<String, dynamic>)['message']
                ?.toString() ??
            msg;
      }
    } on FormatException {
      // Keep HTTP status when server doesn't return JSON.
    }
    return msg;
  }
}
