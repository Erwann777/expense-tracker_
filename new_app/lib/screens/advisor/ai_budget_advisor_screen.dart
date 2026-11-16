import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/currency_provider.dart';
import '../../providers/expense_provider.dart';
import '../../services/gemini_budget_advisor_service.dart';
import '../../utils/app_theme.dart';

class AiBudgetAdvisorScreen extends StatefulWidget {
  const AiBudgetAdvisorScreen({super.key});

  @override
  State<AiBudgetAdvisorScreen> createState() => _AiBudgetAdvisorScreenState();
}

class _AiBudgetAdvisorScreenState extends State<AiBudgetAdvisorScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  bool _isLoading = false;
  String? _advice;
  String? _error;

  // Selected month / year
  late int _selectedMonth;
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = now.month;
    _selectedYear = now.year;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _monthLabel =>
      _monthNames[_selectedMonth - 1];

  static const _monthNames = [
    'January', 'February', 'March', 'April',
    'May',     'June',     'July',  'August',
    'September','October', 'November','December',
  ];

  Future<void> _getAdvice() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isLoading = true;
      _advice = null;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final expProvider = context.read<ExpenseProvider>();
    final currencyProvider = context.read<CurrencyProvider>();
    final user = auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _error = 'You must be logged in to use this feature.';
      });
      return;
    }

    // Gunakan displayCurrency (mata wang yang user pilih di settings)
    final displayCurrency = currencyProvider.displayCurrency;
    final conversionRate = currencyProvider.conversionRate;

    // Monthly budget sudah tersimpan sesuai currency aktif user di Firestore
    final currentBudget = user.monthlyBudget;

    // Convert semua expenses ke displayCurrency untuk AI analysis
    final convertedExpenses = expProvider.expenses.map((e) {
      return e.copyWith(amount: e.amount * conversionRate);
    }).toList();

    final result = await GeminiBudgetAdvisorService.getAdvice(
      expenses: convertedExpenses,
      year: _selectedYear,
      month: _selectedMonth,
      currency: displayCurrency,
      monthlyBudget: currentBudget,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.hasError) {
        _error = result.errorMessage;
      } else {
        _advice = result.advice;
        _animController
          ..reset()
          ..forward();
      }
    });
  }

  Future<void> _pickMonth() async {
    int tempMonth = _selectedMonth;
    int tempYear = _selectedYear;
    final now = DateTime.now();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setSheet) => Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // drag handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkDivider
                        : AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Select Month',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color:
                        isDark ? AppTheme.darkText : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                // Year row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () =>
                          setSheet(() => tempYear--),
                    ),
                    Text(
                      '$tempYear',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkText
                            : AppTheme.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () {
                        if (tempYear < now.year) {
                          setSheet(() => tempYear++);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Month grid
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 4,
                  childAspectRatio: 2.2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  physics: const NeverScrollableScrollPhysics(),
                  children: List.generate(12, (i) {
                    final m = i + 1;
                    final isFuture = tempYear == now.year && m > now.month;
                    final isSelected =
                        m == tempMonth && tempYear == _selectedYear;
                    return GestureDetector(
                      onTap: isFuture
                          ? null
                          : () => setSheet(() => tempMonth = m),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.accentPurple
                              : (isDark
                                  ? AppTheme.darkSurface
                                  : AppTheme.surfaceLight),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _monthNames[i].substring(0, 3),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : isFuture
                                    ? AppTheme.textMuted
                                    : (isDark
                                        ? AppTheme.darkText
                                        : AppTheme.textPrimary),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _selectedMonth = tempMonth;
                        _selectedYear = tempYear;
                        _advice = null;
                        _error = null;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentPurple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Confirm',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    final expProvider = context.watch<ExpenseProvider>();
    final currencyProvider = context.watch<CurrencyProvider>();
    final user = auth.currentUser;

    // Guna displayCurrency & conversionRate dari CurrencyProvider
    final currencySymbol = currencyProvider.displaySymbol;
    final conversionRate = currencyProvider.conversionRate;

    // Quick stats — convert amount ke displayCurrency
    final monthExpenses = expProvider.expenses.where((e) =>
        e.date.year == _selectedYear && e.date.month == _selectedMonth);
    final totalExpense = monthExpenses
        .where((e) => e.isExpense)
        .fold(0.0, (s, e) => s + e.amount * conversionRate);
    final totalIncome = monthExpenses
        .where((e) => e.isIncome)
        .fold(0.0, (s, e) => s + e.amount * conversionRate);
    final txCount = monthExpenses.length;

    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBg : AppTheme.surfaceLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'AI Budget Advisor',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              size: 20,
              color:
                  isDark ? AppTheme.darkText : AppTheme.textPrimary,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero banner ────────────────────────────────────────
              _buildHeroBanner(isDark),
              const SizedBox(height: 20),

              // ── Month selector ─────────────────────────────────────
              _buildMonthSelector(isDark),
              const SizedBox(height: 16),

              // ── Quick stats ────────────────────────────────────────
              _buildQuickStats(
                isDark: isDark,
                currencySymbol: currencySymbol,
                totalExpense: totalExpense,
                totalIncome: totalIncome,
                txCount: txCount,
              ),
              const SizedBox(height: 24),

              // ── Ask AI button ──────────────────────────────────────
              _buildAskButton(isDark),
              const SizedBox(height: 24),

              // ── Result area ────────────────────────────────────────
              if (_isLoading) _buildLoadingCard(isDark),
              if (_error != null) _buildErrorCard(isDark),
              if (_advice != null) _buildAdviceCard(isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────────

  Widget _buildHeroBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusXxl),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentPurple.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Budget Advisor',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Powered by Groq AI — get personalised\nspending insights & money-saving tips.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(bool isDark) {
    return GestureDetector(
      onTap: _pickMonth,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color:
                isDark ? AppTheme.darkDivider : AppTheme.divider,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_month_rounded,
              color: AppTheme.accentPurple,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              '$_monthLabel $_selectedYear',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppTheme.darkText
                    : AppTheme.textPrimary,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.expand_more_rounded,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats({
    required bool isDark,
    required String currencySymbol,
    required double totalExpense,
    required double totalIncome,
    required int txCount,
  }) {
    return Row(
      children: [
        _statChip(
          isDark: isDark,
          icon: Icons.arrow_upward_rounded,
          iconColor: AppTheme.errorRed,
          label: 'Spent',
          value:
              '$currencySymbol ${totalExpense.toStringAsFixed(2)}',
        ),
        const SizedBox(width: 10),
        _statChip(
          isDark: isDark,
          icon: Icons.arrow_downward_rounded,
          iconColor: AppTheme.accentGreen,
          label: 'Income',
          value:
              '$currencySymbol ${totalIncome.toStringAsFixed(2)}',
        ),
        const SizedBox(width: 10),
        _statChip(
          isDark: isDark,
          icon: Icons.receipt_long_rounded,
          iconColor: AppTheme.accentPurple,
          label: 'Txns',
          value: '$txCount',
        ),
      ],
    );
  }

  Widget _statChip({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color:
                isDark ? AppTheme.darkDivider : AppTheme.divider,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.darkText
                    : AppTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAskButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _getAdvice,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentPurple,
          disabledBackgroundColor:
              AppTheme.accentPurple.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(AppTheme.radiusMd),
          ),
          elevation: 4,
          shadowColor:
              AppTheme.accentPurple.withValues(alpha: 0.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              _advice != null
                  ? 'Refresh AI Advice'
                  : 'Get AI Budget Advice',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color:
              AppTheme.accentPurple.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppTheme.accentPurple,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Groq AI is analysing your finances…',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppTheme.darkText
                  : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This usually takes 5–20 seconds.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ensure you have a stable internet connection.',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
            color: AppTheme.errorRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppTheme.errorRed, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _error!,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.errorRed,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _getAdvice,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Try Again',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.errorRed,
                side: BorderSide(
                    color: AppTheme.errorRed.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdviceCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: AppTheme.accentPurple.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentPurple.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentPurple
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppTheme.accentPurple,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your AI Advice',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentPurple,
                    ),
                  ),
                  Text(
                    '$_monthLabel $_selectedYear · Powered by Groq AI',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(
            color: isDark
                ? AppTheme.darkDivider
                : AppTheme.divider,
          ),
          const SizedBox(height: 14),

          // Advice text — render each line
          ..._buildAdviceLines(isDark),

          const SizedBox(height: 14),
          Divider(
            color: isDark
                ? AppTheme.darkDivider
                : AppTheme.divider,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'AI advice is for guidance only. Always verify with a financial professional.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAdviceLines(bool isDark) {
    if (_advice == null) return [];
    final lines = _advice!.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }

      // Section headers (lines that start with emoji or ##)
      final isSectionHeader = trimmed.length > 1 &&
          (trimmed.startsWith('##') ||
              _startsWithEmoji(trimmed));

      if (isSectionHeader) {
        final headerText =
            trimmed.replaceFirst(RegExp(r'^##\s*'), '');
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              headerText,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.darkText
                    : AppTheme.textPrimary,
              ),
            ),
          ),
        );
      } else if (trimmed.startsWith('- ') ||
          trimmed.startsWith('• ')) {
        // Bullet point
        final bulletText = trimmed.substring(2);
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 5, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•  ',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.accentPurple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Expanded(
                  child: Text(
                    bulletText,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: isDark
                          ? AppTheme.darkText
                          : AppTheme.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // Regular paragraph
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              trimmed,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark
                    ? AppTheme.darkText
                    : AppTheme.textPrimary,
                height: 1.6,
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  bool _startsWithEmoji(String s) {
    if (s.isEmpty) return false;
    final runes = s.runes.toList();
    return runes.first > 0x7F;
  }
}

