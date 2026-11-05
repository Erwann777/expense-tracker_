import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/recurring_provider.dart';
import '../../models/recurring_expense_model.dart';
import '../../models/category_model.dart';
import '../../utils/app_theme.dart';
import '../../providers/currency_provider.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser != null) {
        final uid = auth.currentUser!.id!;
        context.read<RecurringProvider>().setUserId(uid);
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
        child: Consumer3<AuthProvider, RecurringProvider, CurrencyProvider>(
          builder: (context, auth, recurProv, cp, _) {
            final user = auth.currentUser;
            if (user == null) return const SizedBox.shrink();
            if (recurProv.userId != user.id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                recurProv.setUserId(user.id!);
              });
            }
            final items = recurProv.recurring;
            final monthly = recurProv.totalMonthlyCommitment;
            final dueCount = recurProv.dueItems.length;
            return Column(
              children: [
                _buildHeader(monthly, dueCount, cp, isDark),
                Expanded(
                  child: recurProv.isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.accentPurple))
                      : items.isEmpty
                          ? _buildEmpty(isDark)
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                              itemCount: items.length,
                              itemBuilder: (ctx, i) =>
                                  _buildCard(ctx, items[i], cp, isDark, i),
                            ),
                ),
              ],
            );
          },
        ),
      ),
      // ✅ FIX: tombol custom, lebar otomatis mengikuti isi (ikon + teks)
      floatingActionButton: Material(
        color: AppTheme.accentOrange,
        elevation: 6,
        shadowColor: AppTheme.accentOrange.withValues(alpha: 0.4),
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
                  'Add Recurring',
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

  Widget _buildHeader(double monthly, int dueCount, CurrencyProvider cp, bool isDark) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
          boxShadow: [
            BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.repeat_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Recurring', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white))),
                if (dueCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(20)),
                    child: Text('$dueCount due', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Monthly Commitment', style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              cp.format(monthly),
              style: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, RecurringExpenseModel item,
      CurrencyProvider cp, bool isDark, int index) {
    final freqInfo = RecurringExpenseModel.frequencies.firstWhere(
        (f) => f['key'] == item.frequency,
        orElse: () => RecurringExpenseModel.frequencies[2]);
    final color = item.isActive ? AppTheme.accentOrange : AppTheme.textMuted;
    final dueColor = item.isActive && item.isDue ? AppTheme.errorRed : color;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 350 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (ctx, val, child) => Opacity(
          opacity: val, child: Transform.translate(offset: Offset(0, 18 * (1 - val)), child: child)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: (item.isActive && item.isDue ? AppTheme.errorRed : dueColor).withValues(alpha: 0.2),
              width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04), blurRadius: 10, offset: const Offset(0, 3))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: dueColor.withValues(alpha: item.isActive ? 0.12 : 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: Text(freqInfo['icon'] as String, style: const TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(item.category, style: GoogleFonts.inter(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
                      Text(' · ', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                      Text(freqInfo['label'] as String, style: GoogleFonts.inter(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
                    ]),
                    if (item.isActive && item.isDue)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.errorRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text('Due now', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.errorRed)),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(cp.format(item.amount),
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: dueColor)),
                  const SizedBox(height: 4),
                  Row(children: [
                    // Tombol "Pay Now" — hanya muncul jika item aktif dan sudah jatuh tempo
                    if (item.isActive && item.isDue) ...[
                      _actionBtn(
                        Icons.play_circle_filled_rounded,
                        () {
                          HapticFeedback.mediumImpact();
                          _confirmPayNow(context, item, cp, isDark);
                        },
                        AppTheme.accentGreen,
                        tooltip: 'Pay Now',
                      ),
                      const SizedBox(width: 4),
                    ],
                    _actionBtn(
                      item.isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      () async { HapticFeedback.selectionClick(); await context.read<RecurringProvider>().toggleActive(item); },
                      item.isActive ? AppTheme.accentOrange : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 4),
                    _actionBtn(Icons.edit_rounded, () { HapticFeedback.selectionClick(); _showSheet(context, item); }, AppTheme.accentBlue),
                    const SizedBox(width: 4),
                    _actionBtn(Icons.delete_rounded, () { HapticFeedback.selectionClick(); _confirmDelete(context, item); }, AppTheme.errorRed),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, VoidCallback onTap, Color color, {String? tooltip}) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 15, color: color),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }

  /// Dialog konfirmasi sebelum "Pay Now" — mencegah pembayaran tidak sengaja.
  void _confirmPayNow(BuildContext ctx, RecurringExpenseModel item, CurrencyProvider cp, bool isDark) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.play_circle_filled_rounded, color: AppTheme.accentGreen, size: 24),
            const SizedBox(width: 8),
            Text('Pay Now', style: GoogleFonts.inter(fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
          ],
        ),
        content: Text(
          'Bayar "${item.title}" sebesar ${cp.format(item.amount)}?\n\n'
                  'Ini akan membuat expense baru berdasarkan recurring ini.',
          style: GoogleFonts.inter(fontSize: 14, height: 1.5,
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Batal', style: GoogleFonts.inter(color: AppTheme.textMuted)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text('Bayar', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              // Tampilkan loading snackbar
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Row(children: [
                      const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      const SizedBox(width: 12),
                      Text('Memproses pembayaran...', style: GoogleFonts.inter()),
                    ]),
                    duration: const Duration(seconds: 10),
                    backgroundColor: AppTheme.accentGreen,
                  ),
                );
              }

              final auth = ctx.read<AuthProvider>();
              final success = await ctx.read<RecurringProvider>()
                  .triggerRecurring(item, auth.currentUser!.id!);

              if (ctx.mounted) {
                // Tutup loading snackbar
                ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Row(children: [
                      Icon(
                        success ? Icons.check_circle_rounded : Icons.error_rounded,
                        color: Colors.white, size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        success
                            ? '✅ "${item.title}" berhasil dibayar!'
                            : '❌ Gagal membayar. Coba lagi.',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                      ),
                    ]),
                    backgroundColor: success ? AppTheme.accentGreen : AppTheme.errorRed,
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔄', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 20),
          Text('No recurring expenses',
              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text('Track rent, subscriptions, and\nrepeating bills here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentOrange),
            onPressed: () => _showSheet(context, null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Recurring'),
          ),
        ],
      ),
    );
  }

  void _showSheet(BuildContext context, RecurringExpenseModel? existing) {
    final auth = context.read<AuthProvider>();
    final recurProv = context.read<RecurringProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final amountCtrl = TextEditingController(
        text: existing != null ? existing.amount.toStringAsFixed(2) : '');
    String selCategory = existing?.category ?? AppCategories.categories.first.name;
    String selFrequency = existing?.frequency ?? 'monthly';
    bool isActive = existing?.isActive ?? true;
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
                  Text(existing == null ? 'Add Recurring' : 'Edit Recurring',
                      style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700,
                          color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: titleCtrl,
                    style: GoogleFonts.inter(color: isDark ? AppTheme.darkText : AppTheme.textPrimary),
                    decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Netflix, Rent'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.inter(color: isDark ? AppTheme.darkText : AppTheme.textPrimary),
                    decoration: const InputDecoration(labelText: 'Amount', prefixIcon: Icon(Icons.attach_money_rounded)),
                  ),
                  const SizedBox(height: 12),
                  Text('Category', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: AppCategories.categories.map((c) {
                        final sel = selCategory == c.name;
                        return GestureDetector(
                          onTap: () => setS(() => selCategory = c.name),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: sel ? AppTheme.accentOrange.withValues(alpha: 0.15) : (isDark ? AppTheme.darkSurface : AppTheme.surfaceLight),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: sel ? AppTheme.accentOrange : (isDark ? AppTheme.darkDivider : AppTheme.divider), width: sel ? 2 : 1),
                            ),
                            child: Text('${c.emoji} ${c.name}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
                                color: sel ? AppTheme.accentOrange : (isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary))),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Frequency', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: RecurringExpenseModel.frequencies.map((f) {
                      final sel = selFrequency == f['key'];
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setS(() => selFrequency = f['key'] as String),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? AppTheme.accentOrange.withValues(alpha: 0.15) : (isDark ? AppTheme.darkSurface : AppTheme.surfaceLight),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: sel ? AppTheme.accentOrange : (isDark ? AppTheme.darkDivider : AppTheme.divider), width: sel ? 2 : 1),
                            ),
                            child: Column(children: [
                              Text(f['icon'] as String, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 2),
                              Text(f['label'] as String, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600,
                                  color: sel ? AppTheme.accentOrange : (isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary))),
                            ]),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Active', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600,
                          color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
                      Switch(value: isActive, onChanged: (v) => setS(() => isActive = v), activeThumbColor: AppTheme.accentOrange),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentOrange,
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
                                  const SnackBar(content: Text('Judul tidak boleh kosong')),
                                );
                                return;
                              }
                              final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0.0;
                              if (amount <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Amount harus lebih dari 0')),
                                );
                                return;
                              }

                              setS(() => isSaving = true);
                              bool success;
                              try {
                                if (existing == null) {
                                  final item = RecurringExpenseModel(
                                    userId: auth.currentUser!.id!,
                                    title: title,
                                    amount: amount,
                                    category: selCategory,
                                    frequency: selFrequency,
                                    startDate: DateTime.now(),
                                    isActive: isActive,
                                  );
                                  success = await recurProv.addRecurring(item);
                                } else {
                                  final item = existing.copyWith(
                                    title: title, amount: amount,
                                    category: selCategory, frequency: selFrequency,
                                    isActive: isActive,
                                  );
                                  success = await recurProv.updateRecurring(item);
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
                                        ? (existing == null ? '✅ Recurring berhasil ditambahkan!' : '✅ Recurring berhasil diupdate!')
                                        : '❌ Gagal menyimpan. Coba lagi.'),
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
                          : Text(existing == null ? 'Add Recurring' : 'Save Changes',
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

  void _confirmDelete(BuildContext context, RecurringExpenseModel item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Recurring', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('Delete "${item.title}"? This cannot be undone.', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () async {
              await context.read<RecurringProvider>().deleteRecurring(item.id!);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}