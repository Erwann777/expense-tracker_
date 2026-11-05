import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/auth_provider.dart';
import '../../providers/expense_provider.dart';
import '../../models/category_model.dart';
import '../../utils/app_theme.dart';
import '../../utils/formatters.dart';

import '../../providers/currency_provider.dart';
import '../../utils/pdf_report_generator.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});
  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  int _touchedIndex = -1;
  String _reportView = 'expense';
  String _chartViewType = 'pie'; // 'pie' or 'bar'
  String _activePreset = 'This Month';
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _rangeStart = DateTime(now.year, now.month, 1);
    _rangeEnd = DateTime(now.year, now.month + 1, 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRange());
  }

  void _loadRange() {
    context.read<ExpenseProvider>().loadDateRangeExpenses(_rangeStart, _rangeEnd);
  }

  void _setPreset(String label, DateTime start, DateTime end) {
    setState(() {
      _activePreset = label;
      _rangeStart = start;
      _rangeEnd = end;
    });
    _loadRange();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _rangeStart, end: _rangeEnd),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppTheme.accentPurple),
        ),
        child: child!,
      ),
    );
    if (picked != null) _setPreset('Custom', picked.start, picked.end);
  }

  Future<void> _exportPdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final auth = context.read<AuthProvider>();
      final exp = context.read<ExpenseProvider>();
      await PdfReportGenerator.generateAndShare(
        userName: auth.currentUser?.displayName ?? 'User',
        currency: auth.currentUser?.currency ?? 'USD',
        startDate: _rangeStart,
        endDate: _rangeEnd,
        totalExpense: exp.rangeExpenseTotal,
        totalIncome: exp.rangeIncomeTotal,
        expenseCategoryTotals: exp.rangeCategoryTotals,
        incomeCategoryTotals: exp.rangeIncomeCategoryTotals,
        transactions: exp.rangeExpenses,
        budget: auth.currentUser?.monthlyBudget,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: AppTheme.errorRed),
        );
      }
    }
    if (mounted) setState(() => _isGeneratingPdf = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.surfaceLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            _buildDatePresets(isDark),
            _buildDateRangeDisplay(isDark),
            Expanded(
              child: Consumer3<ExpenseProvider, AuthProvider, CurrencyProvider>(
                builder: (context, exp, auth, cp, _) {
                  final budget = auth.currentUser?.monthlyBudget ?? 0;
                  return CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildSummaryCards(exp, cp, budget, isDark)),
                      SliverToBoxAdapter(child: _buildViewToggle(isDark)),
                      SliverToBoxAdapter(child: _buildChartSection(exp, isDark)),
                      SliverToBoxAdapter(child: _buildCategoryBreakdown(exp, cp, isDark)),
                      SliverToBoxAdapter(child: _buildTransactionList(exp, cp, isDark)),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reports',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppTheme.darkText : AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'Financial Analytics & Insights',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: _isGeneratingPdf ? null : _exportPdf,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppTheme.cardGradient,
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentPurple.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isGeneratingPdf
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    _isGeneratingPdf ? 'Generating...' : 'Export PDF',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePresets(bool isDark) {
    final now = DateTime.now();
    final presets = <String, List<DateTime>>{
      'Today': [DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day)],
      'This Week': [
        DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1)),
        DateTime(now.year, now.month, now.day)
      ],
      'This Month': [DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0)],
      'Last 3 Months': [DateTime(now.year, now.month - 2, 1), DateTime(now.year, now.month + 1, 0)],
      'This Year': [DateTime(now.year, 1, 1), DateTime(now.year, 12, 31)],
    };
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          ...presets.entries.map((e) => _presetChip(e.key, e.value[0], e.value[1], isDark)),
          _presetChip('Custom', _rangeStart, _rangeEnd, isDark, isCustom: true),
        ],
      ),
    );
  }

  Widget _presetChip(String label, DateTime start, DateTime end, bool isDark, {bool isCustom = false}) {
    final isActive = _activePreset == label;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        isCustom ? _pickCustomRange() : _setPreset(label, start, end);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accentPurple : (isDark ? AppTheme.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isActive ? Colors.transparent : (isDark ? AppTheme.darkDivider : AppTheme.divider),
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppTheme.accentPurple.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCustom) ...[
              Icon(
                Icons.date_range_rounded,
                size: 14,
                color: isActive ? Colors.white : (isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? Colors.white
                    : (isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeDisplay(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: GestureDetector(
        onTap: _pickCustomRange,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? AppTheme.darkDivider.withValues(alpha: 0.5) : AppTheme.divider.withValues(alpha: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.accentPurple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.accentPurple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${Formatters.date(_rangeStart)}  →  ${Formatters.date(_rangeEnd)}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkText : AppTheme.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.edit_calendar_rounded,
                size: 18,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(ExpenseProvider exp, CurrencyProvider cp, double budget, bool isDark) {
    final spent = exp.rangeExpenseTotal;
    final income = exp.rangeIncomeTotal;
    final net = income - spent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusXxl),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              'Net Balance',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${net >= 0 ? '+' : ''}${cp.format(net.abs())}',
                style: GoogleFonts.inter(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _summaryItem(
                      'Income',
                      cp.format(income),
                      Icons.arrow_downward_rounded,
                      AppTheme.accentGreen,
                    ),
                  ),
                  Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.2)),
                  Expanded(
                    child: _summaryItem(
                      'Expense',
                      cp.format(spent),
                      Icons.arrow_upward_rounded,
                      AppTheme.errorRed,
                    ),
                  ),
                ],
              ),
            ),
            if (budget > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.savings_rounded, color: Colors.white.withValues(alpha: 0.95), size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Budget: ${cp.format((budget - spent).clamp(0, double.infinity).toDouble())} remaining',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 12, color: Colors.white),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildViewToggle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _toggleBtn('expense', 'Expenses', Icons.arrow_upward_rounded, AppTheme.errorRed, isDark),
            _toggleBtn('income', 'Income', Icons.arrow_downward_rounded, AppTheme.accentGreen, isDark),
          ],
        ),
      ),
    );
  }

  Widget _toggleBtn(String val, String label, IconData icon, Color color, bool isDark) {
    final sel = _reportView == val;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _reportView = val),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: sel ? Colors.white : (isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : (isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartSection(ExpenseProvider exp, bool isDark) {
    final catTotals = _reportView == 'income' ? exp.rangeIncomeCategoryTotals : exp.rangeCategoryTotals;
    if (catTotals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            children: [
              const Text('📊', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(
                'No ${_reportView == 'income' ? 'income' : 'expense'} data for this period',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusXxl),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${_reportView == 'income' ? 'Income' : 'Spending'} Analysis',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.darkText : AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkBg : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _chartTypeIcon('pie', Icons.pie_chart_rounded, isDark),
                      _chartTypeIcon('bar', Icons.bar_chart_rounded, isDark),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _chartViewType == 'pie'
                ? _buildPieChartWidget(catTotals, isDark)
                : _buildBarChartWidget(catTotals, isDark),
            const SizedBox(height: 16),
            _buildChartLegend(catTotals, isDark),
          ],
        ),
      ),
    );
  }

  Widget _chartTypeIcon(String type, IconData icon, bool isDark) {
    final sel = _chartViewType == type;
    return GestureDetector(
      onTap: () => setState(() => _chartViewType = type),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: sel ? AppTheme.accentPurple : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: sel ? Colors.white : (isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted),
        ),
      ),
    );
  }

  Widget _buildPieChartWidget(Map<String, double> catTotals, bool isDark) {
    return SizedBox(
      height: 210,
      child: PieChart(
        PieChartData(
          sectionsSpace: 3.5,
          centerSpaceRadius: 45,
          pieTouchData: PieTouchData(
            touchCallback: (event, response) {
              setState(() {
                if (!event.isInterestedForInteractions ||
                    response == null ||
                    response.touchedSection == null) {
                  _touchedIndex = -1;
                  return;
                }
                _touchedIndex = response.touchedSection!.touchedSectionIndex;
              });
            },
          ),
          sections: _buildPieSections(catTotals),
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections(Map<String, double> catTotals) {
    final total = catTotals.values.fold(0.0, (a, b) => a + b);
    final entries = catTotals.entries.toList();
    return List.generate(entries.length, (i) {
      final entry = entries[i];
      final cat = AppCategories.getByName(entry.key);
      final pct = total > 0 ? (entry.value / total * 100) : 0;
      final isTouched = i == _touchedIndex;

      final showTitle = pct >= 3.5 || isTouched;

      return PieChartSectionData(
        color: cat.color,
        value: entry.value,
        title: showTitle ? '${pct.toStringAsFixed(0)}%' : '',
        radius: isTouched ? 36.0 : 30.0,
        titleStyle: GoogleFonts.inter(
          fontSize: isTouched ? 11.0 : 9.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          shadows: [
            const Shadow(color: Colors.black38, blurRadius: 2),
          ],
        ),
        badgeWidget: isTouched
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cat.color,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: cat.color.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Text(
                  '${entry.key} (${pct.toStringAsFixed(1)}%)',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              )
            : null,
        badgePositionPercentageOffset: 1.5,
      );
    });
  }

  Widget _buildBarChartWidget(Map<String, double> catTotals, bool isDark) {
    final entries = catTotals.entries.toList();
    final total = catTotals.values.fold(0.0, (a, b) => a + b);
    final maxVal = catTotals.values.fold(0.0, (max, val) => val > max ? val : max);
    final barWidth = entries.length > 8 ? 14.0 : entries.length > 5 ? 18.0 : 26.0;

    return SizedBox(
      height: 230,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal > 0 ? maxVal * 1.35 : 100,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            // Percentage labels on top of each bar
            topTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= entries.length) return const SizedBox.shrink();
                  final pct = total > 0 ? (entries[idx].value / total * 100) : 0;
                  final cat = AppCategories.getByName(entries[idx].key);
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: cat.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: cat.color,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 58,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= entries.length) return const SizedBox.shrink();
                  final cat = AppCategories.getByName(entries[idx].key);
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(cat.emoji, style: const TextStyle(fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(
                            cat.name,
                            style: GoogleFonts.inter(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            softWrap: true,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(entries.length, (i) {
            final entry = entries[i];
            final cat = AppCategories.getByName(entry.key);
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entry.value,
                  color: cat.color,
                  width: barWidth,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxVal * 1.35,
                    color: isDark ? AppTheme.darkDivider.withValues(alpha: 0.25) : const Color(0xFFF1F5F9),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildChartLegend(Map<String, double> catTotals, bool isDark) {
    final total = catTotals.values.fold(0.0, (a, b) => a + b);
    final entries = catTotals.entries.toList();

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: entries.map((entry) {
        final cat = AppCategories.getByName(entry.key);
        final pct = total > 0 ? (entry.value / total * 100) : 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: isDark ? AppTheme.darkDivider.withValues(alpha: 0.5) : AppTheme.divider.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: cat.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                entry.key,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkText : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${pct.toStringAsFixed(1)}%',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: cat.color,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryBreakdown(ExpenseProvider exp, CurrencyProvider cp, bool isDark) {
    final catTotals = _reportView == 'income' ? exp.rangeIncomeCategoryTotals : exp.rangeCategoryTotals;
    if (catTotals.isEmpty) return const SizedBox.shrink();
    final total = catTotals.values.fold(0.0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusXxl),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Category Breakdown',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkText : AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${catTotals.length} categories',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...catTotals.entries.map((entry) {
              final cat = AppCategories.getByName(entry.key);
              final pct = total > 0 ? entry.value / total : 0.0;
              final pctFormatted = (pct * 100).toStringAsFixed(1);
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    // Icon + label column
                    SizedBox(
                      width: 54,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cat.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: cat.color.withValues(alpha: 0.25),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(cat.emoji, style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cat.name.length > 8 ? '${cat.name.substring(0, 7)}.' : cat.name,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Progress + amounts
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Percentage pill
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: cat.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '$pctFormatted%',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: cat.color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Amount
                              Flexible(
                                child: Text(
                                  cp.format(entry.value),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? AppTheme.darkText : AppTheme.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Progress bar
                          Stack(
                            children: [
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppTheme.darkDivider.withValues(alpha: 0.4)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: pct,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: cat.color,
                                    borderRadius: BorderRadius.circular(100),
                                    boxShadow: [
                                      BoxShadow(
                                        color: cat.color.withValues(alpha: 0.4),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(ExpenseProvider exp, CurrencyProvider cp, bool isDark) {
    final items = _reportView == 'income' ? exp.rangeIncomeOnly : exp.rangeExpenseOnly;
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusXxl),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${_reportView == 'income' ? 'Income' : 'Expense'} Transactions',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppTheme.darkText : AppTheme.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_reportView == 'income' ? AppTheme.accentGreen : AppTheme.errorRed)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${items.length} total',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _reportView == 'income' ? AppTheme.accentGreen : AppTheme.errorRed,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...items.take(15).map((expense) {
              final cat = AppCategories.getByName(expense.category);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cat.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(cat.emoji, style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.title,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.darkText : AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            Formatters.dateRelative(expense.date),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${expense.isIncome ? '+' : '-'}${cp.format(expense.amount)}',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: expense.isIncome ? AppTheme.accentGreen : AppTheme.errorRed,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (items.length > 15)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Center(
                  child: Text(
                    '+ ${items.length - 15} more in PDF export',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.accentPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
// updated: 2026-09-23
