import 'dart:async';
import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../models/recurring_expense_model.dart';

class RecurringProvider with ChangeNotifier {
  List<RecurringExpenseModel> _recurring = [];
  bool _isLoading = false;
  String? _userId;

  StreamSubscription<List<RecurringExpenseModel>>? _subscription;

  List<RecurringExpenseModel> get recurring => _recurring;
  List<RecurringExpenseModel> get activeRecurring =>
      _recurring.where((r) => r.isActive).toList();
  List<RecurringExpenseModel> get dueItems =>
      _recurring.where((r) => r.isActive && r.isDue).toList();
  bool get isLoading => _isLoading;
  String? get userId => _userId;

  double get totalMonthlyCommitment {
    double total = 0;
    for (final r in activeRecurring) {
      switch (r.frequency) {
        case 'daily':
          total += r.amount * 30;
          break;
        case 'weekly':
          total += r.amount * 4.33;
          break;
        case 'monthly':
          total += r.amount;
          break;
        case 'yearly':
          total += r.amount / 12;
          break;
      }
    }
    return total;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void setUserId(String userId) {
    if (_userId == userId) return;
    _userId = userId;
    _isLoading = true;
    notifyListeners();
    _setupRealtimeListener();
  }

  void _setupRealtimeListener() {
    if (_userId == null) return;
    _subscription?.cancel();
    _subscription = FirebaseService.instance
        .getRecurringExpensesStream(_userId!)
        .listen(
      (items) {
        _recurring = items;
        _isLoading = false;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('Error in recurring stream: $e');
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> loadRecurring() async {
    if (_userId == null) return;
    if (_recurring.isNotEmpty) return;
    _isLoading = true;
    notifyListeners();
    try {
      _recurring =
          await FirebaseService.instance.getRecurringExpenses(_userId!);
    } catch (e) {
      debugPrint('Error loading recurring expenses: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> addRecurring(RecurringExpenseModel item) async {
    try {
      await FirebaseService.instance.createRecurringExpense(item);
      return true;
    } catch (e) {
      debugPrint('Error adding recurring expense: $e');
      return false;
    }
  }

  Future<bool> updateRecurring(RecurringExpenseModel item) async {
    try {
      await FirebaseService.instance.updateRecurringExpense(item);
      return true;
    } catch (e) {
      debugPrint('Error updating recurring expense: $e');
      return false;
    }
  }

  Future<bool> toggleActive(RecurringExpenseModel item) async {
    final updated = item.copyWith(isActive: !item.isActive);
    return updateRecurring(updated);
  }

  Future<bool> deleteRecurring(String id) async {
    try {
      await FirebaseService.instance.deleteRecurringExpense(id);
      return true;
    } catch (e) {
      debugPrint('Error deleting recurring expense: $e');
      return false;
    }
  }

  /// Hitung semua tanggal jatuh tempo yang belum di-trigger dari [item].
  /// Contoh: recurring monthly terakhir di-trigger 1 Jan, sekarang 15 Mar
  /// → returns [1 Feb, 1 Mar]
  List<DateTime> _getAllPendingDueDates(RecurringExpenseModel item) {
    final now = DateTime.now();
    final List<DateTime> dueDates = [];
    DateTime current = item.lastTriggered ?? item.startDate;

    int maxIterations = 366; // Batas aman (max 1 tahun daily)
    while (maxIterations-- > 0) {
      final DateTime nextDue;
      switch (item.frequency) {
        case 'daily':
          nextDue = current.add(const Duration(days: 1));
          break;
        case 'weekly':
          nextDue = current.add(const Duration(days: 7));
          break;
        case 'monthly':
          nextDue = DateTime(current.year, current.month + 1, current.day);
          break;
        case 'yearly':
          nextDue = DateTime(current.year + 1, current.month, current.day);
          break;
        default:
          nextDue = current.add(const Duration(days: 30));
      }

      if (nextDue.isAfter(now)) break; // Belum jatuh tempo
      dueDates.add(nextDue);
      current = nextDue;
    }

    return dueDates;
  }

  /// Trigger manual oleh user (tombol "Pay Now") — hanya untuk 1 periode berikutnya.
  /// Menggunakan atomic batch: create expense + update lastTriggered sekaligus.
  Future<bool> triggerRecurring(
    RecurringExpenseModel item,
    String userId,
  ) async {
    try {
      final dueDate = item.nextDueDate;
      await FirebaseService.instance.triggerRecurringExpense(
        recurring: item,
        userId: userId,
        dueDate: dueDate,
      );
      return true;
    } catch (e) {
      debugPrint('Error triggering recurring expense: $e');
      return false;
    }
  }

  /// Auto-trigger semua recurring yang sudah jatuh tempo saat app dibuka.
  ///
  /// Menangani SEMUA periode yang terlewat, contoh:
  ///   - Recurring daily, tidak dibuka 5 hari → buat 5 expense (tiap hari)
  ///   - Recurring monthly, tidak dibuka 2 bulan → buat 2 expense (tiap bulan)
  ///
  /// Menggunakan Firestore batch agar atomic dan efisien.
  /// Returns total jumlah expense yang berhasil dibuat.
  Future<int> autoTriggerDue(String userId) async {
    final activeItems = activeRecurring;
    if (activeItems.isEmpty) return 0;

    // Kumpulkan semua periode terlewat dari semua item aktif
    final List<Map<String, dynamic>> entries = [];

    for (final item in activeItems) {
      final pendingDates = _getAllPendingDueDates(item);
      if (pendingDates.isEmpty) continue;

      // Untuk item yang sama dengan beberapa periode terlewat,
      // kita harus trigger berurutan agar last_triggered terupdate dengan benar.
      // Oleh karena itu kita proses per-item, bukan semua sekaligus dalam 1 batch.
      // Simulasi update lastTriggered secara lokal untuk hitung dueDate berikutnya.
      RecurringExpenseModel current = item;
      for (final dueDate in pendingDates) {
        entries.add({
          'recurring': current,
          'dueDate': dueDate,
          'userId': userId,
        });
        // Update local copy untuk perhitungan nextDueDate berikutnya
        current = current.copyWith(lastTriggered: dueDate);
      }
    }

    if (entries.isEmpty) return 0;

    try {
      final created = await FirebaseService.instance
          .batchTriggerRecurringExpenses(entries);
      debugPrint('Auto-triggered $created recurring expense(s)');
      return created;
    } catch (e) {
      debugPrint('Error in autoTriggerDue: $e');
      return 0;
    }
  }

  void clear() {
    _subscription?.cancel();
    _subscription = null;
    _recurring = [];
    _userId = null;
    notifyListeners();
  }
}
