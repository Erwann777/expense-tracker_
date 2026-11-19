import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/expense_model.dart';
import '../models/savings_goal_model.dart';
import '../models/recurring_expense_model.dart';

/// Firebase service — semua data user disimpan sebagai subcollection di bawah
/// users/{userId}/, supaya senang cari dan urus data setiap user.
///
/// Struktur Firestore:
///   users/
///     {userId}/                  ← profil user
///       expenses/                ← subcollection expenses (type=expense) sahaja
///         {expenseId}/
///       income/                  ← subcollection income (type=income) sahaja
///         {incomeId}/
///       savings_goals/           ← subcollection goals user ini
///         {goalId}/
///       recurring_expenses/      ← subcollection recurring user ini
///         {recurringId}/
class FirebaseService {
  static final FirebaseService instance = FirebaseService._init();

  FirebaseService._init();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Root collections ──────────────────────────────────────────────────────

  /// Koleksi utama users
  CollectionReference get _usersCollection => _firestore.collection('users');

  /// Subcollection expenses (type=expense) di bawah user tertentu
  CollectionReference _expensesOf(String userId) =>
      _usersCollection.doc(userId).collection('expenses');

  /// Subcollection income (type=income) di bawah user tertentu
  CollectionReference _incomeOf(String userId) =>
      _usersCollection.doc(userId).collection('income');

  /// Subcollection savings_goals di bawah user tertentu
  CollectionReference _goalsOf(String userId) =>
      _usersCollection.doc(userId).collection('savings_goals');

  /// Subcollection recurring_expenses di bawah user tertentu
  CollectionReference _recurringOf(String userId) =>
      _usersCollection.doc(userId).collection('recurring_expenses');

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

  /// Real-time stream untuk profil user
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
    // Simpan ke collection yang betul bergantung pada type
    final uid = expense.userId;
    final col = expense.isIncome ? _incomeOf(uid) : _expensesOf(uid);
    final docRef = await col.add(expense.toMap());
    return docRef.id;
  }

  Future<List<ExpenseModel>> getExpenses(
    String userId, {
    bool showHidden = false,
  }) async {
    try {
      // Ambil dari kedua-dua collection dan gabungkan
      final expSnap = await _expensesOf(userId).get();
      final incSnap = await _incomeOf(userId).get();

      final list = [
        ...expSnap.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return ExpenseModel.fromMap({...data, 'id': doc.id, 'type': 'expense'});
        }),
        ...incSnap.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return ExpenseModel.fromMap({...data, 'id': doc.id, 'type': 'income'});
        }),
      ].where((e) => showHidden || !e.isHidden).toList();

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
    // Update dalam collection yang betul
    final col = expense.isIncome ? _incomeOf(expense.userId) : _expensesOf(expense.userId);
    await col.doc(expense.id).update(expense.toMap());
  }

  Future<void> deleteExpense(String expenseId, String userId, {bool isIncome = false}) async {
    final col = isIncome ? _incomeOf(userId) : _expensesOf(userId);
    await col.doc(expenseId).delete();
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

  // ─────────────────────────────────────────────────────
  // ── Migration: expenses → split expenses / income ──
  // ─────────────────────────────────────────────────────

  /// Kira berapa banyak dokumen dengan type='income' masih ada
  /// dalam collection 'expenses/' untuk SATU user (data lama).
  Future<int> countOldIncomeInExpenses(String userId) async {
    final expSnap = await _expensesOf(userId).get();
    return expSnap.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['type'] as String?) == 'income';
    }).length;
  }

  /// Kira jumlah income lama untuk SEMUA user.
  /// Returns map {totalUsers, totalIncomeDocs}.
  Future<Map<String, int>> countAllUsersOldIncome() async {
    final usersSnap = await _usersCollection.get();
    int totalIncome = 0;
    int usersWithIncome = 0;

    for (final userDoc in usersSnap.docs) {
      final count = await countOldIncomeInExpenses(userDoc.id);
      if (count > 0) {
        usersWithIncome++;
        totalIncome += count;
      }
    }

    return {
      'totalUsers': usersSnap.docs.length,
      'usersWithIncome': usersWithIncome,
      'totalIncomeDocs': totalIncome,
    };
  }

  /// Migrate data lama untuk SATU user:
  /// semua dokumen dengan type='income' di dalam 'expenses/' → 'income/'.
  /// Selamat dijalankan berulang kali (idempotent).
  Future<MigrationResult> migrateIncomeToSeparateCollection(
    String userId, {
    void Function(int done, int total)? onProgress,
  }) async {
    final expSnap = await _expensesOf(userId).get();
    final incomeDocs = expSnap.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['type'] as String?) == 'income';
    }).toList();

    if (incomeDocs.isEmpty) {
      return MigrationResult(migrated: 0, failed: 0, skipped: 0);
    }

    int migrated = 0;
    int failed = 0;
    int done = 0;
    final total = incomeDocs.length;

    // Tiap dokumen = 2 ops (set + delete) → selamat 200 doc/batch (< 500 limit)
    const chunkSize = 200;

    for (int start = 0; start < incomeDocs.length; start += chunkSize) {
      final chunk = incomeDocs.sublist(
        start,
        (start + chunkSize).clamp(0, incomeDocs.length),
      );

      final batch = _firestore.batch();
      int chunkValid = 0;

      for (final doc in chunk) {
        final data = doc.data() as Map<String, dynamic>;
        final enriched = {...data, 'type': 'income'};
        batch.set(_incomeOf(userId).doc(doc.id), enriched);
        batch.delete(_expensesOf(userId).doc(doc.id));
        chunkValid++;
      }

      try {
        await batch.commit();
        migrated += chunkValid;
      } catch (e) {
        failed += chunkValid;
      }

      done += chunk.length;
      onProgress?.call(done, total);
    }

    return MigrationResult(migrated: migrated, failed: failed, skipped: 0);
  }

  /// Migrate data lama untuk SEMUA user sekaligus.
  ///
  /// [onUserProgress] dipanggil setiap kali seorang user selesai:
  ///   - usersDone  : berapa user yang telah diproses
  ///   - usersTotal : jumlah user keseluruhan
  ///   - userId     : ID user yang baru selesai
  ///   - userResult : result migration untuk user tersebut
  ///
  /// Returns [GlobalMigrationResult] dengan statistik keseluruhan.
  Future<GlobalMigrationResult> migrateAllUsersIncome({
    void Function(
      int usersDone,
      int usersTotal,
      String userId,
      MigrationResult userResult,
    )? onUserProgress,
  }) async {
    // Ambil semua user IDs
    final usersSnap = await _usersCollection.get();
    final allUserIds = usersSnap.docs.map((d) => d.id).toList();

    int totalMigrated = 0;
    int totalFailed = 0;
    int totalSkipped = 0;
    int usersProcessed = 0;
    int usersWithData = 0;
    final List<String> failedUsers = [];

    for (final userId in allUserIds) {
      try {
        final result = await migrateIncomeToSeparateCollection(userId);

        totalMigrated += result.migrated;
        totalFailed += result.failed;
        totalSkipped += result.skipped;

        if (result.total > 0) usersWithData++;
        if (result.failed > 0) failedUsers.add(userId);

        usersProcessed++;
        onUserProgress?.call(usersProcessed, allUserIds.length, userId, result);
      } catch (e) {
        totalFailed++;
        failedUsers.add(userId);
        usersProcessed++;
        onUserProgress?.call(
          usersProcessed,
          allUserIds.length,
          userId,
          MigrationResult(migrated: 0, failed: 1, skipped: 0),
        );
      }
    }

    return GlobalMigrationResult(
      totalUsers: allUserIds.length,
      usersWithData: usersWithData,
      totalMigrated: totalMigrated,
      totalFailed: totalFailed,
      totalSkipped: totalSkipped,
      failedUserIds: failedUsers,
    );
  }

  /// Real-time stream — expenses sahaja (type=expense)
  Stream<List<ExpenseModel>> getExpensesStream(
    String userId, {
    bool showHidden = false,
  }) {
    return _expensesOf(userId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return ExpenseModel.fromMap({...data, 'id': doc.id, 'type': 'expense'});
          })
          .where((e) => showHidden || !e.isHidden)
          .toList();
      return list;
    });
  }

  /// Real-time stream untuk income sahaja (type=income)
  Stream<List<ExpenseModel>> getIncomeStream(
    String userId, {
    bool showHidden = false,
  }) {
    return _incomeOf(userId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return ExpenseModel.fromMap({...data, 'id': doc.id, 'type': 'income'});
          })
          .where((e) => showHidden || !e.isHidden)
          .toList();
      return list;
    });
  }

  // ─────────────────────────────────────────────────────
  // ── Savings Goals Operations ──
  // ─────────────────────────────────────────────────────

  Future<String> createSavingsGoal(SavingsGoalModel goal) async {
    final docRef = await _goalsOf(goal.userId).add(goal.toMap());
    return docRef.id;
  }

  Future<List<SavingsGoalModel>> getSavingsGoals(String userId) async {
    try {
      final snapshot = await _goalsOf(userId).get();

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
    await _goalsOf(goal.userId).doc(goal.id).update(goal.toMap());
  }

  Future<void> deleteSavingsGoal(String goalId, String userId) async {
    await _goalsOf(userId).doc(goalId).delete();
  }

  /// Real-time stream savings goals untuk user ini
  Stream<List<SavingsGoalModel>> getSavingsGoalsStream(String userId) {
    return _goalsOf(userId).snapshots().map((snapshot) {
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
    final docRef = await _recurringOf(recurring.userId).add(recurring.toMap());
    return docRef.id;
  }

  Future<List<RecurringExpenseModel>> getRecurringExpenses(
      String userId) async {
    try {
      final snapshot = await _recurringOf(userId).get();

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
    await _recurringOf(recurring.userId)
        .doc(recurring.id)
        .update(recurring.toMap());
  }

  Future<void> deleteRecurringExpense(String recurringId, String userId) async {
    await _recurringOf(userId).doc(recurringId).delete();
  }

  /// Real-time stream recurring expenses untuk user ini
  Stream<List<RecurringExpenseModel>> getRecurringExpensesStream(
      String userId) {
    return _recurringOf(userId).snapshots().map((snapshot) {
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

    final expenseRef = _expensesOf(userId).doc(); // auto-generated ID
    final recurringRef = _recurringOf(userId).doc(recurring.id);

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
        final uid = entry['userId'] as String;

        if (recurring.id == null) continue;

        final expenseRef = _expensesOf(uid).doc();
        final recurringRef = _recurringOf(uid).doc(recurring.id);

        final expense = ExpenseModel(
          userId: uid,
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

/// Hasil operasi migrasi data income
class MigrationResult {
  final int migrated;
  final int failed;
  final int skipped;

  const MigrationResult({
    required this.migrated,
    required this.failed,
    required this.skipped,
  });

  bool get isSuccess => failed == 0;
  int get total => migrated + failed + skipped;

  @override
  String toString() =>
      'MigrationResult(migrated: $migrated, failed: $failed, skipped: $skipped)';
}

/// Hasil migrasi untuk SEMUA user
class GlobalMigrationResult {
  final int totalUsers;
  final int usersWithData;
  final int totalMigrated;
  final int totalFailed;
  final int totalSkipped;
  final List<String> failedUserIds;

  const GlobalMigrationResult({
    required this.totalUsers,
    required this.usersWithData,
    required this.totalMigrated,
    required this.totalFailed,
    required this.totalSkipped,
    required this.failedUserIds,
  });

  bool get isFullSuccess => totalFailed == 0;
  bool get hasFailures => totalFailed > 0;
  int get totalProcessed => totalMigrated + totalFailed + totalSkipped;

  @override
  String toString() =>
      'GlobalMigrationResult(users: $totalUsers, migrated: $totalMigrated, failed: $totalFailed)';
}
