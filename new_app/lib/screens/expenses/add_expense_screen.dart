import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/expense_provider.dart';
import '../../models/expense_model.dart';
import '../../models/category_model.dart';
import '../../models/currency_model.dart';
import '../../models/receipt_scan_result.dart';
import '../../services/gemini_receipt_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/formatters.dart';

class AddExpenseScreen extends StatefulWidget {
  final ExpenseModel? expense;
  final bool isIncome;
  const AddExpenseScreen({super.key, this.expense, this.isIncome = false});
  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  late String _selectedCategory;
  late bool _isIncome;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _isScanningReceipt = false;

  /// Menyimpan hasil scan terakhir — ditampilkan di preview card
  ReceiptScanResult? _lastScanResult;

  bool get isEditing => widget.expense != null;
  bool get _canScanReceipt =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _isIncome = widget.isIncome;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
    if (isEditing) {
      final e = widget.expense!;
      _titleController.text = e.title;
      _amountController.text = e.amount.toStringAsFixed(2);
      _noteController.text = e.note ?? '';
      _selectedCategory = e.category;
      _selectedDate = e.date;
      _selectedTime = TimeOfDay.fromDateTime(e.date);
      _isIncome = e.isIncome;
    } else {
      _selectedCategory = _isIncome
          ? AppCategories.incomeCategories.first.name
          : AppCategories.categories.first.name;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<ExpenseCategory> get _currentCategories =>
      _isIncome ? AppCategories.incomeCategories : AppCategories.categories;

  void _switchType(bool income) {
    setState(() {
      _isIncome = income;
      _selectedCategory = _currentCategories.first.name;
      _lastScanResult = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.mediumImpact();

    final auth = context.read<AuthProvider>();
    final expProvider = context.read<ExpenseProvider>();
    final userId = auth.currentUser!.id!;
    final date = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final expense = ExpenseModel(
      id: widget.expense?.id,
      userId: userId,
      title: _titleController.text.trim(),
      amount: double.parse(_amountController.text),
      category: _selectedCategory,
      type: _isIncome ? 'income' : 'expense',
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      date: date,
      receiptPath: widget.expense?.receiptPath,
      isHidden: widget.expense?.isHidden ?? false,
    );

    bool success;
    if (isEditing) {
      success = await expProvider.updateExpense(expense);
    } else {
      success = await expProvider.addExpense(expense);
    }

    if (success && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? '${_isIncome ? 'Income' : 'Expense'} updated! ✅'
                : '${_isIncome ? 'Income' : 'Expense'} added! ✅',
          ),
          backgroundColor: AppTheme.accentGreen,
        ),
      );
    }
  }

  Future<void> _deleteExpense() async {
    if (!isEditing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        ),
        title: Text(
          'Delete ${_isIncome ? 'Income' : 'Expense'}',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.expense!.title}"?',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final success = await context.read<ExpenseProvider>().deleteExpense(
        widget.expense!.id!,
      );
      if (success && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.expense!.title} deleted'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // AI RECEIPT SCANNER (Gemini Vision)
  // ---------------------------------------------------------------------------

  Future<void> _scanReceipt() async {
    if (_isScanningReceipt) return;
    if (!_canScanReceipt) {
      _showSnack('Receipt scanning hanya tersedia di Android dan iOS.');
      return;
    }

    // Pilih sumber gambar: kamera atau galeri
    final source = await _showImageSourceDialog();
    if (source == null) return;

    setState(() {
      _isScanningReceipt = true;
      _lastScanResult = null;
    });

    try {
      final pickedFile = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2500,
        imageQuality: 90,
      );
      if (pickedFile == null) return;

      final imageFile = File(pickedFile.path);

      // Kirim ke Gemini API
      final result = await GeminiReceiptService.scanReceipt(imageFile);

      if (!mounted) return;

      if (result.hasError) {
        _showSnack('❌ ${result.errorMessage}');
        return;
      }

      // Terapkan hasil scan ke form
      _applyReceiptResult(result);

      setState(() => _lastScanResult = result);
    } on PlatformException {
      _showSnack('Tidak bisa mengakses kamera. Coba lagi.');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isScanningReceipt = false);
    }
  }

  /// Tampilkan dialog pilih sumber gambar (kamera / galeri)
  Future<ImageSource?> _showImageSourceDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkDivider : AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: AppTheme.accentPurple, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI Receipt Scanner',
                          style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
                      Text('Powered by Gemini AI',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.textSecondary)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Camera option
              _imageSourceTile(
                ctx: ctx,
                icon: Icons.camera_alt_rounded,
                label: 'Ambil Foto',
                subtitle: 'Foto receipt langsung dengan kamera',
                source: ImageSource.camera,
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              // Gallery option
              _imageSourceTile(
                ctx: ctx,
                icon: Icons.photo_library_rounded,
                label: 'Pilih dari Galeri',
                subtitle: 'Gunakan foto receipt yang sudah ada',
                source: ImageSource.gallery,
                isDark: isDark,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageSourceTile({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required String subtitle,
    required ImageSource source,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, source),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppTheme.darkDivider : AppTheme.divider,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accentPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.accentPurple, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppTheme.darkText : AppTheme.textPrimary)),
                  Text(subtitle,
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  /// Terapkan hasil scan Gemini ke form fields
  void _applyReceiptResult(ReceiptScanResult result) {
    setState(() {
      // Isi amount
      if (result.hasAmount) {
        _amountController.text = result.totalAmount!.toStringAsFixed(2);
      }

      // Isi merchant name sebagai title jika title masih kosong
      if (result.merchantName != null && _titleController.text.trim().isEmpty) {
        _titleController.text = result.merchantName!;
      }

      // Isi tanggal transaksi
      if (result.transactionDate != null) {
        _selectedDate = result.transactionDate!;
      }

      // Pilih kategori yang disarankan AI
      if (result.suggestedCategory != null) {
        final catExists = _currentCategories
            .any((c) => c.name == result.suggestedCategory);
        if (catExists) {
          _selectedCategory = result.suggestedCategory!;
        }
      }
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.read<AuthProvider>();
    final currencySymbol = auth.currentUser != null
        ? AppCurrencies.getByCode(auth.currentUser!.currency).symbol
        : '\$';

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.surfaceLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          isEditing
              ? 'Edit ${_isIncome ? 'Income' : 'Expense'}'
              : 'Add ${_isIncome ? 'Income' : 'Expense'}',
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
              color: isDark ? AppTheme.darkText : AppTheme.textPrimary,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isEditing)
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.delete_rounded,
                  size: 20,
                  color: AppTheme.errorRed,
                ),
              ),
              onPressed: _deleteExpense,
            ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Income/Expense toggle
                _buildTypeToggle(isDark),
                const SizedBox(height: 20),
                _buildAmountSection(currencySymbol),
                if (!_isIncome) ...[
                  const SizedBox(height: 12),
                  _buildScanButton(isDark),
                  // Preview card hasil scan AI
                  if (_lastScanResult != null) ...[
                    const SizedBox(height: 12),
                    _buildScanResultCard(_lastScanResult!, isDark),
                  ],
                ],
                const SizedBox(height: 28),
                _buildSectionLabel('Title', isDark),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _isIncome
                        ? 'e.g. Monthly salary'
                        : 'e.g. Lunch at café',
                    prefixIcon: Icon(
                      Icons.edit_rounded,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.textMuted,
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter a title'
                      : null,
                ),
                const SizedBox(height: 24),
                _buildSectionLabel('Category', isDark),
                const SizedBox(height: 12),
                _buildCategoryGrid(isDark),
                const SizedBox(height: 24),
                _buildSectionLabel('Date & Time', isDark),
                const SizedBox(height: 12),
                _buildDateTimeRow(context, isDark),
                const SizedBox(height: 24),
                _buildSectionLabel('Note (Optional)', isDark),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _noteController,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Add a note...',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 48),
                      child: Icon(
                        Icons.note_rounded,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isIncome
                          ? AppTheme.accentGreen
                          : AppTheme.accentPurple,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      elevation: 4,
                      shadowColor:
                          (_isIncome
                                  ? AppTheme.accentGreen
                                  : AppTheme.accentPurple)
                              .withValues(alpha: 0.4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isEditing ? Icons.check_rounded : Icons.add_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isEditing
                              ? 'Update ${_isIncome ? 'Income' : 'Expense'}'
                              : 'Add ${_isIncome ? 'Income' : 'Expense'}',
                          style: GoogleFonts.inter(
                            fontSize: 16,
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
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WIDGETS
  // ---------------------------------------------------------------------------

  /// Tombol scan receipt dengan animasi loading
  Widget _buildScanButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: _isScanningReceipt ? null : _scanReceipt,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.accentPurple,
          side: BorderSide(
            color: _isScanningReceipt
                ? AppTheme.accentPurple.withValues(alpha: 0.3)
                : AppTheme.accentPurple.withValues(alpha: 0.6),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          backgroundColor: _isScanningReceipt
              ? AppTheme.accentPurple.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: _isScanningReceipt
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accentPurple.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'AI sedang menganalisis receipt...',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accentPurple.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Scan Receipt dengan AI',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentPurple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Gemini',
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentPurple),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Card preview hasil scan AI — menampilkan confidence dan data yang diekstrak
  Widget _buildScanResultCard(ReceiptScanResult result, bool isDark) {
    final confidence = (result.confidence * 100).toStringAsFixed(0);
    final confColor = result.confidence >= 0.8
        ? AppTheme.accentGreen
        : result.confidence >= 0.5
            ? const Color(0xFFF59E0B)
            : AppTheme.errorRed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accentGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.accentGreen.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppTheme.accentGreen, size: 18),
              const SizedBox(width: 8),
              Text(
                'Hasil Scan AI',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentGreen),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Akurasi $confidence%',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: confColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (result.merchantName != null)
            _resultRow(
                Icons.store_rounded,
                'Merchant',
                result.merchantName!,
                isDark),
          if (result.hasAmount)
            _resultRow(
                Icons.payments_rounded,
                'Total',
                result.totalAmount!.toStringAsFixed(2),
                isDark),
          if (result.transactionDate != null)
            _resultRow(
                Icons.calendar_today_rounded,
                'Tanggal',
                '${result.transactionDate!.day}/${result.transactionDate!.month}/${result.transactionDate!.year}',
                isDark),
          if (result.suggestedCategory != null)
            _resultRow(
                Icons.category_rounded,
                'Kategori',
                result.suggestedCategory!,
                isDark),
          const SizedBox(height: 8),
          Text(
            '✨ Form telah diisi otomatis. Periksa dan sesuaikan jika perlu.',
            style: GoogleFonts.inter(
                fontSize: 11,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon,
              size: 14,
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.textMuted),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: GoogleFonts.inter(
                fontSize: 12,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkText : AppTheme.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeToggle(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _switchType(false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: !_isIncome ? AppTheme.errorRed : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: !_isIncome
                      ? [
                          BoxShadow(
                            color: AppTheme.errorRed.withValues(alpha: 0.3),
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
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: !_isIncome
                          ? Colors.white
                          : (isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.textMuted),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Expense',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: !_isIncome
                            ? Colors.white
                            : (isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _switchType(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _isIncome ? AppTheme.accentGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isIncome
                      ? [
                          BoxShadow(
                            color: AppTheme.accentGreen.withValues(alpha: 0.3),
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
                      Icons.arrow_downward_rounded,
                      size: 18,
                      color: _isIncome
                          ? Colors.white
                          : (isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.textMuted),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Income',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _isIncome
                            ? Colors.white
                            : (isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountSection(String symbol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        gradient: _isIncome ? AppTheme.greenGradient : AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusXxl),
        boxShadow: [
          BoxShadow(
            color:
                (_isIncome ? const Color(0xFF10B981) : const Color(0xFF6366F1))
                    .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'How much?',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  symbol,
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    errorStyle: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter amount';
                    final val = double.tryParse(v);
                    if (val == null || val <= 0) return 'Invalid';
                    return null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text, bool isDark) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: isDark ? AppTheme.darkText : AppTheme.textPrimary,
      ),
    );
  }

  Widget _buildCategoryGrid(bool isDark) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _currentCategories.map((cat) {
        final isSelected = _selectedCategory == cat.name;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedCategory = cat.name);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? cat.color.withValues(alpha: 0.15)
                  : (isDark ? AppTheme.darkCard : Colors.white),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: isSelected
                    ? cat.color
                    : (isDark ? AppTheme.darkDivider : AppTheme.divider),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: cat.color.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(cat.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  cat.name,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? cat.color
                        : (isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateTimeRow(BuildContext context, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) setState(() => _selectedDate = date);
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: isDark ? AppTheme.darkDivider : AppTheme.divider,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 20,
                    color: _isIncome
                        ? AppTheme.accentGreen
                        : AppTheme.accentPurple,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Formatters.dateShort(_selectedDate),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.darkText
                            : AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: _selectedTime,
              );
              if (time != null) setState(() => _selectedTime = time);
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: isDark ? AppTheme.darkDivider : AppTheme.divider,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 20,
                    color: _isIncome
                        ? AppTheme.accentGreen
                        : AppTheme.accentPurple,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedTime.format(context),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.darkText
                            : AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
