import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/migration_service.dart';
import '../../utils/app_theme.dart';

/// Dialog/screen untuk migrate data Firestore dari struktur lama ke baru.
/// Dibuka dari Settings apabila ada data lama yang perlu dipindahkan.
class MigrationScreen extends StatefulWidget {
  const MigrationScreen({super.key});

  @override
  State<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends State<MigrationScreen> {
  _MigrationState _state = _MigrationState.idle;
  final List<String> _logs = [];
  MigrationResult? _result;
  bool _deleteOldData = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.surfaceLight;
    final card = isDark ? AppTheme.darkCard : Colors.white;
    final textPrimary = isDark ? Colors.white : AppTheme.textPrimary;
    final textSecondary = isDark ? Colors.white60 : AppTheme.textSecondary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Migrate Database',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(card, textPrimary, textSecondary),
            const SizedBox(height: 16),
            if (_state == _MigrationState.idle) ...[
              _buildOptionsCard(card, textPrimary, textSecondary, isDark),
              const SizedBox(height: 20),
              _buildMigrateButton(isDark),
            ],
            if (_state == _MigrationState.running) ...[
              _buildProgressCard(card, textPrimary, textSecondary),
            ],
            if (_state == _MigrationState.done && _result != null) ...[
              _buildResultCard(card, textPrimary, textSecondary),
              const SizedBox(height: 16),
              _buildLogCard(card, textPrimary, textSecondary),
              const SizedBox(height: 20),
              _buildDoneButton(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Info Card ────────────────────────────────────────────────────────────

  Widget _buildInfoCard(Color card, Color textPrimary, Color textSecondary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: Color(0xFF7C3AED), size: 20),
              const SizedBox(width: 8),
              Text(
                'Kenapa perlu migrate?',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF7C3AED),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow('Sebelum', 'expenses/ , savings_goals/ , recurring_expenses/',
              Icons.folder_outlined),
          const SizedBox(height: 6),
          _infoRow('Selepas', 'users/{id}/expenses/ , users/{id}/savings_goals/...',
              Icons.account_tree_outlined),
          const SizedBox(height: 10),
          Text(
            'Semua data akan dipindahkan ke struktur baru. Data lama akan '
            'dipadamkan (atau disimpan sebagai backup ikut pilihan anda).',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF7C3AED).withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF7C3AED).withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7C3AED),
                  ),
                ),
                TextSpan(
                  text: value,
                  style: GoogleFonts.sourceCodePro(
                    fontSize: 11,
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Options Card ─────────────────────────────────────────────────────────

  Widget _buildOptionsCard(
      Color card, Color textPrimary, Color textSecondary, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Padam data lama selepas migrate',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        subtitle: Text(
          _deleteOldData
              ? 'Data lama akan dipadam — Firestore lebih kemas'
              : 'Data lama disimpan sebagai backup',
          style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
        ),
        value: _deleteOldData,
        activeColor: const Color(0xFF7C3AED),
        onChanged: (val) => setState(() => _deleteOldData = val),
      ),
    );
  }

  // ── Migrate Button ────────────────────────────────────────────────────────

  Widget _buildMigrateButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _startMigration,
        icon: const Icon(Icons.sync_rounded, color: Colors.white),
        label: Text(
          'Mula Migrate Sekarang',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C3AED),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  // ── Progress Card ─────────────────────────────────────────────────────────

  Widget _buildProgressCard(
      Color card, Color textPrimary, Color textSecondary) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: Color(0xFF7C3AED),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sedang memindahkan data...',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Jangan tutup app',
                style: GoogleFonts.inter(
                    fontSize: 13, color: textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildLogCard(card, textPrimary, textSecondary),
      ],
    );
  }

  // ── Result Card ───────────────────────────────────────────────────────────

  Widget _buildResultCard(
      Color card, Color textPrimary, Color textSecondary) {
    final r = _result!;
    final isSuccess = r.success;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isSuccess
            ? const Color(0xFF10B981).withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSuccess
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
            color: isSuccess ? const Color(0xFF10B981) : Colors.red,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            isSuccess ? 'Migration Berjaya! 🎉' : 'Migration Gagal',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isSuccess ? const Color(0xFF10B981) : Colors.red,
            ),
          ),
          if (isSuccess) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statBadge('Expenses', r.migratedExpenses, const Color(0xFF7C3AED)),
                _statBadge('Goals', r.migratedGoals, const Color(0xFF10B981)),
                _statBadge('Recurring', r.migratedRecurring, const Color(0xFFF59E0B)),
              ],
            ),
            if (r.skipped > 0) ...[
              const SizedBox(height: 10),
              Text(
                '${r.skipped} dokumen dilangkau (tiada user_id)',
                style: GoogleFonts.inter(fontSize: 12, color: textSecondary),
              ),
            ],
          ],
          if (!isSuccess && r.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              r.errorMessage!,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _statBadge(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: GoogleFonts.inter(fontSize: 11, color: color)),
      ],
    );
  }

  // ── Log Card ──────────────────────────────────────────────────────────────

  Widget _buildLogCard(Color card, Color textPrimary, Color textSecondary) {
    if (_logs.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Log',
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textSecondary),
          ),
          const SizedBox(height: 8),
          ...(_logs.reversed.take(10).map((log) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  log,
                  style: GoogleFonts.sourceCodePro(
                      fontSize: 11, color: textSecondary, height: 1.4),
                ),
              ))),
        ],
      ),
    );
  }

  // ── Done Button ───────────────────────────────────────────────────────────

  Widget _buildDoneButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: () => Navigator.pop(context, true),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: Text(
          'Selesai — Kembali ke Settings',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ── Migration logic ───────────────────────────────────────────────────────

  Future<void> _startMigration() async {
    setState(() {
      _state = _MigrationState.running;
      _logs.clear();
    });

    MigrationService.instance.onProgress = (msg) {
      if (mounted) {
        setState(() => _logs.add(msg));
      }
    };

    final result = await MigrationService.instance.migrateAll(
      deleteOldData: _deleteOldData,
    );

    if (mounted) {
      setState(() {
        _result = result;
        _state = _MigrationState.done;
      });
    }
  }
}

enum _MigrationState { idle, running, done }

