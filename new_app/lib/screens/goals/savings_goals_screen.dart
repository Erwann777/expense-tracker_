import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/goals_provider.dart';
import '../../models/savings_goal_model.dart';
import '../../utils/app_theme.dart';
import '../../providers/currency_provider.dart';

class SavingsGoalsScreen extends StatefulWidget {
  const SavingsGoalsScreen({super.key});
  @override
  State<SavingsGoalsScreen> createState() => _SavingsGoalsScreenState();
}

class _SavingsGoalsScreenState extends State<SavingsGoalsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  static const List<Map<String, dynamic>> _presetEmojis = [
    {'emoji': '🏠', 'label': 'Home'}, {'emoji': '🚗', 'label': 'Car'},
    {'emoji': '✈️', 'label': 'Travel'}, {'emoji': '💍', 'label': 'Ring'},
    {'emoji': '📱', 'label': 'Phone'}, {'emoji': '💻', 'label': 'Laptop'},
    {'emoji': '🎓', 'label': 'Edu'}, {'emoji': '💰', 'label': 'Savings'},
    {'emoji': '🎯', 'label': 'Goal'}, {'emoji': '🏖️', 'label': 'Vacation'},
  ];

  static const List<int> _presetColors = [
    0xFF7C3AED, 0xFF3B82F6, 0xFF10B981, 0xFFF59E0B,
    0xFFEC4899, 0xFF06B6D4, 0xFFEF4444, 0xFF8B5CF6,
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser != null) {
        context.read<GoalsProvider>().setUserId(auth.currentUser!.id!);
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.surfaceLight,
      body: SafeArea(
        child: Consumer3<AuthProvider, GoalsProvider, CurrencyProvider>(
          builder: (context, auth, goalsProv, cp, _) {
            final user = auth.currentUser;
            if (user == null) return const SizedBox.shrink();
            if (goalsProv.userId != user.id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                goalsProv.setUserId(user.id!);
              });
            }
            final goals = goalsProv.goals;

            return Column(
              children: [
                _buildHeader(goalsProv, isDark),
                Expanded(
                  child: goalsProv.isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.accentPurple))
                      : goals.isEmpty
                          ? _buildEmpty(isDark)
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                              itemCount: goals.length,
                              itemBuilder: (ctx, i) => _buildGoalCard(
                                  ctx, goals[i], cp, isDark, i),
                            ),
                ),
              ],
            );
          },
        ),
      ),
      // ✅ FIX: tombol custom, lebar otomatis mengikuti isi (ikon + teks)
      floatingActionButton: Material(
        color: AppTheme.accentPurple,
        elevation: 6,
        shadowColor: AppTheme.accentPurple.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => _showSheet(context, null),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'New Goal',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(GoalsProvider goalsProv, bool isDark) {
    final active = goalsProv.activeGoals.length;
    final completed = goalsProv.completedGoals.length;
    return FadeTransition(
      opacity: _fade,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
          boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.savings_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Savings Goals', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                  child: Text('🏆 ${goalsProv.totalBadges}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _headerStat('Active', active.toString()),
                const SizedBox(width: 32),
                _headerStat('Completed', completed.toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1)),
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildGoalCard(BuildContext context, SavingsGoalModel goal,
      CurrencyProvider cp, bool isDark, int index) {
    final color = Color(goal.color);
    final progress = goal.progress;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 350 + index * 80),
      curve: Curves.easeOutCubic,
      builder: (ctx, val, child) => Opacity(
          opacity: val, child: Transform.translate(offset: Offset(0, 20 * (1 - val)), child: child)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 4)),
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
          border: Border.all(color: color.withValues(alpha: goal.isCompleted ? 0.4 : 0.15), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                    child: Center(child: Text(goal.emoji, style: const TextStyle(fontSize: 26))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(goal.badge, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 4),
                          Expanded(child: Text(goal.title,
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700,
                                  color: isDark ? AppTheme.darkText : AppTheme.textPrimary))),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                            goal.isCompleted
                                ? '🎉 Goal Completed!'
                                : '${goal.daysLeft} days left · ${goal.level}',
                            style: GoogleFonts.inter(fontSize: 11,
                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      _iconBtnSmall(Icons.edit_rounded, () => _showSheet(context, goal), AppTheme.accentBlue),
                      const SizedBox(height: 4),
                      _iconBtnSmall(Icons.delete_rounded, () => _confirmDelete(context, goal), AppTheme.errorRed),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: progress),
                  duration: Duration(milliseconds: 800 + index * 100),
                  curve: Curves.easeOutCubic,
                  builder: (ctx, val, _) => LinearProgressIndicator(
                    value: val,
                    minHeight: 8,
                    backgroundColor: color.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(goal.isCompleted ? AppTheme.accentGreen : color),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Saved', style: GoogleFonts.inter(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
                    Text(cp.format(goal.savedAmount),
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700,
                            color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
                  ]),
                  Text('${(progress * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800,
                          color: goal.isCompleted ? AppTheme.accentGreen : color)),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Target', style: GoogleFonts.inter(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
                    Text(cp.format(goal.targetAmount),
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700,
                            color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
                  ]),
                ],
              ),
              if (!goal.isCompleted) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _showAddSavingsDialog(context, goal, cp, isDark),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text('Add Savings', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtnSmall(IconData icon, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎯', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 20),
          Text('No savings goals yet',
              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text('Set a target and track your\nprogress toward your dreams.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => _showSheet(context, null),
            icon: const Icon(Icons.add_rounded),
            label: Text('Create Goal', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showAddSavingsDialog(BuildContext context, SavingsGoalModel goal,
      CurrencyProvider cp, bool isDark) {
    final amountCtrl = TextEditingController();
    bool isSaving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Add to "${goal.title}"', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
          content: TextField(
            controller: amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: GoogleFonts.inter(color: isDark ? AppTheme.darkText : AppTheme.textPrimary),
            decoration: InputDecoration(labelText: 'Amount', prefixText: '${cp.displaySymbol} '),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentPurple),
              onPressed: isSaving ? null : () async {
                final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0.0;
                if (amount <= 0) return;
                setS(() => isSaving = true);
                final success = await context.read<GoalsProvider>().addSavings(goal.id!, amount);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(success ? '✅ Tabungan berhasil ditambahkan!' : '❌ Gagal menambahkan tabungan'),
                    backgroundColor: success ? AppTheme.accentGreen : AppTheme.errorRed,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ));
                }
              },
              child: isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, SavingsGoalModel? existing) {
    final auth = context.read<AuthProvider>();
    final goalsProv = context.read<GoalsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final targetCtrl = TextEditingController(
        text: existing != null ? existing.targetAmount.toStringAsFixed(2) : '');
    final savedCtrl = TextEditingController(
        text: existing != null ? existing.savedAmount.toStringAsFixed(2) : '0');
    String selEmoji = existing?.emoji ?? '🎯';
    int selColor = existing?.color ?? _presetColors.first;
    DateTime deadline = existing?.deadline ?? DateTime.now().add(const Duration(days: 90));
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: isDark ? AppTheme.darkDivider : AppTheme.divider, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),
                  Text(existing == null ? 'Create Goal' : 'Edit Goal',
                      style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700,
                          color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
                  const SizedBox(height: 20),
                  // ── Emoji ──
                  Text('Emoji', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 50,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _presetEmojis.map((e) {
                        final sel = selEmoji == e['emoji'];
                        return GestureDetector(
                          onTap: () => setS(() => selEmoji = e['emoji'] as String),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: sel ? Color(selColor).withValues(alpha: 0.15) : (isDark ? AppTheme.darkSurface : AppTheme.surfaceLight),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: sel ? Color(selColor) : (isDark ? AppTheme.darkDivider : AppTheme.divider), width: sel ? 2 : 1),
                            ),
                            child: Center(child: Text(e['emoji'] as String, style: const TextStyle(fontSize: 22))),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Color ──
                  Text('Color', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _presetColors.map((c) {
                        final sel = selColor == c;
                        return GestureDetector(
                          onTap: () => setS(() => selColor = c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(color: sel ? Colors.white : Colors.transparent, width: 2.5),
                              boxShadow: sel ? [BoxShadow(color: Color(c).withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(0, 2))] : [],
                            ),
                            child: sel ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Fields ──
                  TextField(
                    controller: titleCtrl,
                    autofocus: existing == null,
                    style: GoogleFonts.inter(color: isDark ? AppTheme.darkText : AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Goal Title',
                      hintText: 'e.g. New Laptop, Vacation',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(selEmoji, style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: targetCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.inter(color: isDark ? AppTheme.darkText : AppTheme.textPrimary),
                    decoration: const InputDecoration(labelText: 'Target Amount', prefixIcon: Icon(Icons.flag_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: savedCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.inter(color: isDark ? AppTheme.darkText : AppTheme.textPrimary),
                    decoration: const InputDecoration(labelText: 'Already Saved', prefixIcon: Icon(Icons.savings_rounded)),
                  ),
                  const SizedBox(height: 12),
                  // ── Deadline Picker ──
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: deadline,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setS(() => deadline = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E36) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_rounded, color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            'Deadline: ${deadline.day}/${deadline.month}/${deadline.year}',
                            style: GoogleFonts.inter(fontSize: 14, color: isDark ? AppTheme.darkText : AppTheme.textPrimary),
                          )),
                          Icon(Icons.chevron_right_rounded, color: isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // ── Save Button ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final title = titleCtrl.text.trim();
                              if (title.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Judul goal tidak boleh kosong')),
                                );
                                return;
                              }
                              final target = double.tryParse(targetCtrl.text.replaceAll(',', '.')) ?? 0.0;
                              if (target <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Target amount harus lebih dari 0')),
                                );
                                return;
                              }
                              final saved = double.tryParse(savedCtrl.text.replaceAll(',', '.')) ?? 0.0;

                              setS(() => isSaving = true);
                              bool success;
                              try {
                                if (existing == null) {
                                  final goal = SavingsGoalModel(
                                    userId: auth.currentUser!.id!,
                                    title: title,
                                    emoji: selEmoji,
                                    targetAmount: target,
                                    savedAmount: saved,
                                    deadline: deadline,
                                    color: selColor,
                                  );
                                  success = await goalsProv.addGoal(goal);
                                } else {
                                  final goal = existing.copyWith(
                                    title: title, emoji: selEmoji,
                                    targetAmount: target, savedAmount: saved,
                                    deadline: deadline, color: selColor,
                                  );
                                  success = await goalsProv.updateGoal(goal);
                                }
                              } catch (e) {
                                success = false;
                              }
                              setS(() => isSaving = false);

                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(success
                                        ? (existing == null ? '✅ Goal berhasil dibuat!' : '✅ Goal berhasil diupdate!')
                                        : '❌ Gagal menyimpan goal. Coba lagi.'),
                                    backgroundColor: success ? AppTheme.accentGreen : AppTheme.errorRed,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                      child: isSaving
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(existing == null ? 'Create Goal' : 'Save Changes',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, SavingsGoalModel goal) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Goal', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('Delete "${goal.title}"? This cannot be undone.', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () async {
              await context.read<GoalsProvider>().deleteGoal(goal.id!);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}