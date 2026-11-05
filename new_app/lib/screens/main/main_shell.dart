import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/recurring_provider.dart';
import '../../providers/currency_provider.dart';
import '../home/home_screen.dart';
import '../expenses/expense_list_screen.dart';
import '../goals/savings_goals_screen.dart';
import '../recurring/recurring_screen.dart';
import '../report/monthly_report_screen.dart';
import '../settings/settings_screen.dart';
import '../../utils/app_theme.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const _screens = [
    HomeScreen(),
    ExpenseListScreen(),
    SavingsGoalsScreen(),
    RecurringScreen(),
    MonthlyReportScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser != null) {
        final uid = auth.currentUser!.id!;
        context.read<ExpenseProvider>()..setUserId(uid)..loadExpenses();
        context.read<GoalsProvider>().setUserId(uid);
        context.read<RecurringProvider>().setUserId(uid);

        // Init live currency conversion
        final user = auth.currentUser!;
        context.read<CurrencyProvider>().init(
          user.baseCurrency,
          user.currency,
        );

        // Auto-trigger recurring expenses yang sudah jatuh tempo
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            context.read<RecurringProvider>().autoTriggerDue(uid);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06), blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, 'Home', isDark),
                _buildNavItem(1, Icons.receipt_long_rounded, 'Expenses', isDark),
                _buildNavItem(2, Icons.savings_rounded, 'Goals', isDark),
                _buildNavItem(3, Icons.repeat_rounded, 'Recurring', isDark),
                _buildNavItem(4, Icons.bar_chart_rounded, 'Reports', isDark),
                _buildNavItem(5, Icons.settings_rounded, 'Settings', isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, bool isDark) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); setState(() => _currentIndex = index); },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(horizontal: isSelected ? 14 : 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentPurple.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
              color: isSelected ? AppTheme.accentPurple : (isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted),
              size: isSelected ? 22 : 20),
            if (isSelected) ...[
              const SizedBox(height: 2),
              Text(label,
                style: const TextStyle(color: AppTheme.accentPurple, fontWeight: FontWeight.w700, fontSize: 9),
                maxLines: 1,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
// updated: 2026-10-29
