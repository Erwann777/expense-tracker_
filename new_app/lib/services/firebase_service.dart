import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/expense_model.dart';
import '../models/savings_goal_model.dart';
import '../models/recurring_expense_model.dart';

/// Firebase service that handles all Firestore operations with real-time synchronization
class FirebaseService {
  static final FirebaseService instance = FirebaseService._init();

  FirebaseService._init();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  CollectionReference get _usersCollection => _firestore.collection('users');
  CollectionReference get _expensesCollection => _firestore.collection('expenses');
  CollectionReference get _goalsCollection => _firestore.collection('savings_goals');
  CollectionReference get _recurringCollection => _firestore.collection('recurring_expenses');

  // ─────────────────────────────────────────────────────
  // ── User Operations ──
  // ─────────────────────────────────────────────────────

  Future<String> createUser(UserModel user) async {
    final docRef = await _usersCollection.add(user.toMap());
    return docRef.id;
  }

  Future<UserModel?> getUser(String username) async {
    final snapshot = await _usersCollection
        .where('username', isEqualTo: username)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final data = snapshot.docs.first.data() as Map<String, dynamic>;
    return UserModel.fromMap({...data, 'id': snapshot.docs.first.id});
  }

  Future<UserModel?> getUserById(String id) async {
    try {
      final doc = await _usersCollection
          .doc(id)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>;
      return UserModel.fromMap({...data, 'id': doc.id});
    } catch (_) {
      return null;
    }
  }

  Future<UserModel?> authenticateUser(String username, String password) async {
    final snapshot = await _usersCollection
        .where('username', isEqualTo: username)
        .where('password', isEqualTo: password)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final data = snapshot.docs.first.data() as Map<String, dynamic>;
    return UserModel.fromMap({...data, 'id': snapshot.docs.first.id});
  }

  Future<void> updateUser(UserModel user) async {
    if (user.id == null) return;
    await _usersCollection.doc(user.id).update(user.toMap());
  }

  // Real-time user updates
  Stream<UserModel?> getUserStream(String userId) {
    return _usersCollection.doc(userId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      final data = snapshot.data() as Map<String, dynamic>;
      return UserModel.fromMap({...data, 'id': snapshot.id});
    });
  }

  // ─────────────────────────────────────────────────────
  // ── Expense Operations ──
  // ─────────────────────────────────────────────────────

  Future<String> createExpense(ExpenseModel expense) async {
    final docRef = await _expensesCollection.add(expense.toMap());
    return docRef.id;
  }

  Future<List<ExpenseModel>> getExpenses(
    String userId, {
    bool showHidden = false,
  }) async {
    try {
      final snapshot = await _expensesCollection
          .where('user_id', isEqualTo: userId)
          .get();

      final list = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return ExpenseModel.fromMap({...data, 'id': doc.id});
          })
          .where((e) => showHidden || !e.isHidden)
          .toList();

      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    } catch (e) {
      return [];
    }
  }

  Future<List<ExpenseModel>> getExpensesByDateRange(
    String userId,
    DateTime start,
    DateTime end, {
    bool showHidden = false,
  }) async {
    final all = await getExpenses(userId, showHidden: showHidden);
    return all.where((e) {
      return (e.date.isAfter(start) || e.date.isAtSameMomentAs(start)) &&
          (e.date.isBefore(end) || e.date.isAtSameMomentAs(end));
    }).toList();
  }

  Future<List<ExpenseModel>> getExpensesByMonth(
    String userId,
    int year,
    int month,
  ) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);
    return getExpensesByDateRange(userId, start, end);
  }

  Future<List<ExpenseModel>> getTodayExpenses(String userId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return getExpensesByDateRange(userId, start, end);
  }

  Future<List<ExpenseModel>> getLast7DaysExpenses(String userId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return getExpensesByDateRange(userId, start, end);
  }

  Future<void> updateExpense(ExpenseModel expense) async {
    if (expense.id == null) return;
    await _expensesCollection.doc(expense.id).update(expense.toMap());
  }

  Future<void> deleteExpense(String id) async {
    await _expensesCollection.doc(id).delete();
  }

  Future<double> getMonthlyTotal(
    String userId,
    int year,
    int month, {
    String type = 'expense',
  }) async {
    final list = await getExpensesByMonth(userId, year, month);
    double total = 0.0;
    for (final e in list) {
      if (e.type == type) {
        total += e.amount;
      }
    }
    return total;
  }

  Future<double> getMonthlyIncome(String userId, int year, int month) async {
    return getMonthlyTotal(userId, year, month, type: 'income');
  }

  Future<double> getMonthlyExpense(String userId, int year, int month) async {
    return getMonthlyTotal(userId, year, month, type: 'expense');
  }

  Future<Map<String, double>> getCategoryTotals(
    String userId,
    int year,
    int month, {
    String? type,
  }) async {
    final list = await getExpensesByMonth(userId, year, month);
    final map = <String, double>{};
    for (final e in list) {
      if (type == null || e.type == type) {
        map[e.category] = (map[e.category] ?? 0.0) + e.amount;
      }
    }
    return map;
  }

  Future<List<Map<String, dynamic>>> getDailyTotals(
    String userId,
    int days,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final expenses = await getExpensesByDateRange(userId, start, end);
    final dailyMap = <String, double>{};
    for (int i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      final k =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      dailyMap[k] = 0.0;
    }
    for (final e in expenses.where((e) => e.isExpense)) {
      final k =
          '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}-${e.date.day.toString().padLeft(2, '0')}';
      dailyMap[k] = (dailyMap[k] ?? 0.0) + e.amount;
    }

    final result = <Map<String, dynamic>>[];
    for (final entry in dailyMap.entries) {
      result.add({'day': entry.key, 'total': entry.value});
    }
    result.sort((a, b) => (a['day'] as String).compareTo(b['day'] as String));
    return result;
  }

  Future<Map<String, double>> getCategoryTotalsByDateRange(
    String userId,
    DateTime start,
    DateTime end, {
    String? type,
  }) async {
    final list = await getExpensesByDateRange(userId, start, end);
    final map = <String, double>{};
    for (final e in list) {
      if (type == null || e.type == type) {
        map[e.category] = (map[e.category] ?? 0.0) + e.amount;
      }
    }
    return map;
  }

  Future<double> getTotalByDateRange(
    String userId,
    DateTime start,
    DateTime end, {
    String type = 'expense',
  }) async {
    final list = await getExpensesByDateRange(userId, start, end);
    double total = 0.0;
    for (final e in list) {
      if (e.type == type) {
        total += e.amount;
      }
    }
    return total;
  }

  Future<List<Map<String, dynamic>>> getAllExpensesRaw(String userId) async {
    final list = await getExpenses(userId, showHidden: true);
    return list.map((e) => e.toMap()).toList();
  }

  // Real-time expense updates
  Stream<List<ExpenseModel>> getExpensesStream(
    String userId, {
    bool showHidden = false,
  }) {
    return _expensesCollection
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return ExpenseModel.fromMap({...data, 'id': doc.id});
          })
          .where((e) => showHidden || !e.isHidden)
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  // ─────────────────────────────────────────────────────
  // ── Savings Goals Operations ──
  // ─────────────────────────────────────────────────────

  Future<String> createSavingsGoal(SavingsGoalModel goal) async {
    final docRef = await _goalsCollection.add(goal.toMap());
    return docRef.id;
  }

  Future<List<SavingsGoalModel>> getSavingsGoals(String userId) async {
    try {
      final snapshot = await _goalsCollection
          .where('user_id', isEqualTo: userId)
          .get();

      final list = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return SavingsGoalModel.fromMap({...data, 'id': doc.id});
      }).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      return [];
    }
  }

  Future<void> updateSavingsGoal(SavingsGoalModel goal) async {
    if (goal.id == null) return;
    await _goalsCollection.doc(goal.id).update(goal.toMap());
  }

  Future<void> deleteSavingsGoal(String id) async {
    await _goalsCollection.doc(id).delete();
  }

  // Real-time goals stream
  Stream<List<SavingsGoalModel>> getSavingsGoalsStream(String userId) {
    return _goalsCollection
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return SavingsGoalModel.fromMap({...data, 'id': doc.id});
      }).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  // ─────────────────────────────────────────────────────
  // ── Recurring Expenses Operations ──
  // ─────────────────────────────────────────────────────

  Future<String> createRecurringExpense(RecurringExpenseModel recurring) async {
    final docRef = await _recurringCollection.add(recurring.toMap());
    return docRef.id;
  }

  Future<List<RecurringExpenseModel>> getRecurringExpenses(String userId) async {
    try {
      final snapshot = await _recurringCollection
          .where('user_id', isEqualTo: userId)
          .get();

      final list = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return RecurringExpenseModel.fromMap({...data, 'id': doc.id});
      }).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      return [];
    }
  }

  Future<void> updateRecurringExpense(RecurringExpenseModel recurring) async {
    if (recurring.id == null) return;
    await _recurringCollection.doc(recurring.id).update(recurring.toMap());
  }

  Future<void> deleteRecurringExpense(String id) async {
    await _recurringCollection.doc(id).delete();
  }

  // Real-time recurring expenses stream
  Stream<List<RecurringExpenseModel>> getRecurringExpensesStream(String userId) {
    return _recurringCollection
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return RecurringExpenseModel.fromMap({...data, 'id': doc.id});
      }).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  // ─────────────────────────────────────────────────────
  // ── Recurring → Expense Sync (Atomic Batch) ──
  // ─────────────────────────────────────────────────────

  /// Trigger satu periode recurring secara ATOMIC menggunakan Firestore batch:
  /// 1. Buat dokumen expense baru dengan tanggal = [dueDate]
  /// 2. Update `last_triggered` di dokumen recurring
  ///
  /// Jika salah satu gagal → keduanya dibatalkan (tidak ada data setengah-setengah).
  Future<String> triggerRecurringExpense({
    required RecurringExpenseModel recurring,
    required String userId,
    required DateTime dueDate,
  }) async {
    if (recurring.id == null) throw Exception('Recurring ID tidak boleh null');

    final expenseRef = _expensesCollection.doc(); // auto-generated ID
    final recurringRef = _recurringCollection.doc(recurring.id);

    final expense = ExpenseModel(
      userId: userId,
      title: recurring.title,
      amount: recurring.amount,
      type: 'expense',
      category: recurring.category,
      date: dueDate,
      recurringId: recurring.id,
      note: 'Recurring: ${recurring.title}',
    );

    // Gunakan WriteBatch — create expense + update lastTriggered dalam 1 operasi
    final batch = _firestore.batch();
    batch.set(expenseRef, expense.toMap());
    batch.update(recurringRef, {'last_triggered': dueDate.toIso8601String()});
    await batch.commit();

    return expenseRef.id;
  }

  /// Trigger BANYAK periode recurring sekaligus menggunakan Firestore batch.
  ///
  /// [entries] adalah list of map:
  ///   - 'recurring': RecurringExpenseModel
  ///   - 'dueDate'  : DateTime (tanggal jatuh tempo periode tersebut)
  ///   - 'userId'   : String
  ///
  /// Firestore batch maksimal 500 operasi per commit.
  /// Method ini otomatis memecah jadi beberapa batch jika > 200 periode.
  ///
  /// Returns jumlah expense yang berhasil dibuat.
  Future<int> batchTriggerRecurringExpenses(
    List<Map<String, dynamic>> entries,
  ) async {
    if (entries.isEmpty) return 0;

    int created = 0;
    // Tiap periode = 2 operasi (set expense + update recurring)
    // Firestore limit 500 ops/batch → aman pakai 200 periode per batch
    const int chunkSize = 200;

    for (int start = 0; start < entries.length; start += chunkSize) {
      final chunk = entries.sublist(
        start,
        (start + chunkSize).clamp(0, entries.length),
      );

      final batch = _firestore.batch();

      for (final entry in chunk) {
        final recurring = entry['recurring'] as RecurringExpenseModel;
        final dueDate = entry['dueDate'] as DateTime;
        final userId = entry['userId'] as String;

        if (recurring.id == null) continue;

        final expenseRef = _expensesCollection.doc();
        final recurringRef = _recurringCollection.doc(recurring.id);

        final expense = ExpenseModel(
          userId: userId,
          title: recurring.title,
          amount: recurring.amount,
          type: 'expense',
          category: recurring.category,
          date: dueDate,
          recurringId: recurring.id,
          note: 'Recurring: ${recurring.title}',
        );

        batch.set(expenseRef, expense.toMap());
        batch.update(recurringRef, {
          'last_triggered': dueDate.toIso8601String(),
        });
        created++;
      }

      await batch.commit();
    }

    return created;
  }
}
