import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Satu-kali migration dari struktur lama (flat top-level collections)
/// ke struktur baru (subcollections di bawah users/{userId}/).
///
/// Struktur LAMA:
///   expenses/           → where('user_id', == userId)
///   savings_goals/      → where('user_id', == userId)
///   recurring_expenses/ → where('user_id', == userId)
///
/// Struktur BARU:
///   users/{userId}/expenses/
///   users/{userId}/savings_goals/
///   users/{userId}/recurring_expenses/
class MigrationService {
  static final MigrationService instance = MigrationService._init();
  MigrationService._init();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Progress callback ──────────────────────────────────────────────────────
  /// Callback untuk update UI semasa migration berjalan.
  /// Dipanggil dengan mesej status terkini.
  void Function(String message)? onProgress;

  // ── Migration result ───────────────────────────────────────────────────────
  int _migratedExpenses = 0;
  int _migratedGoals = 0;
  int _migratedRecurring = 0;
  int _skipped = 0;
  int _errors = 0;

  int get migratedExpenses => _migratedExpenses;
  int get migratedGoals => _migratedGoals;
  int get migratedRecurring => _migratedRecurring;
  int get skipped => _skipped;
  int get errors => _errors;
  int get totalMigrated => _migratedExpenses + _migratedGoals + _migratedRecurring;

  void _log(String msg) {
    debugPrint('[Migration] $msg');
    onProgress?.call(msg);
  }

  // ── Check sama ada perlu migrate ───────────────────────────────────────────

  /// Returns true kalau masih ada dokumen dalam collection lama.
  Future<bool> needsMigration() async {
    try {
      final snap = await _db.collection('expenses').limit(1).get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Main migration method ──────────────────────────────────────────────────

  /// Migrate semua data dari collection lama ke subcollection baru.
  ///
  /// [deleteOldData] – set true untuk padam dokumen lama selepas migrate.
  ///                   Default false (selamat — data lama kekal sebagai backup).
  ///
  /// Returns ringkasan migration.
  Future<MigrationResult> migrateAll({bool deleteOldData = false}) async {
    _reset();
    _log('Memulakan migration data...');

    try {
      await _migrateCollection(
        oldCollectionName: 'expenses',
        subCollectionName: 'expenses',
        deleteOld: deleteOldData,
      );

      await _migrateCollection(
        oldCollectionName: 'savings_goals',
        subCollectionName: 'savings_goals',
        deleteOld: deleteOldData,
      );

      await _migrateCollection(
        oldCollectionName: 'recurring_expenses',
        subCollectionName: 'recurring_expenses',
        deleteOld: deleteOldData,
      );

      _log('Migration selesai! '
          'Expenses: $_migratedExpenses, '
          'Goals: $_migratedGoals, '
          'Recurring: $_migratedRecurring, '
          'Skip: $_skipped, '
          'Error: $_errors');

      return MigrationResult(
        success: true,
        migratedExpenses: _migratedExpenses,
        migratedGoals: _migratedGoals,
        migratedRecurring: _migratedRecurring,
        skipped: _skipped,
        errors: _errors,
      );
    } catch (e) {
      _log('Migration gagal: $e');
      return MigrationResult(
        success: false,
        errorMessage: e.toString(),
        migratedExpenses: _migratedExpenses,
        migratedGoals: _migratedGoals,
        migratedRecurring: _migratedRecurring,
        skipped: _skipped,
        errors: _errors,
      );
    }
  }

  // ── Migrate satu collection ────────────────────────────────────────────────

  Future<void> _migrateCollection({
    required String oldCollectionName,
    required String subCollectionName,
    required bool deleteOld,
  }) async {
    _log('Memproses collection: $oldCollectionName...');

    final snapshot = await _db.collection(oldCollectionName).get();
    _log('  Jumpa ${snapshot.docs.length} dokumen dalam "$oldCollectionName"');

    if (snapshot.docs.isEmpty) {
      _log('  Tiada data untuk dipindahkan.');
      return;
    }

    // Group dokumen mengikut user_id
    final grouped = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final userId = data['user_id']?.toString() ?? data['userId']?.toString();
      if (userId == null || userId.isEmpty) {
        _log('  ⚠️  Dokumen ${doc.id} tiada user_id — dilangkau.');
        _skipped++;
        continue;
      }
      grouped.putIfAbsent(userId, () => []).add(doc);
    }

    _log('  Dijumpai ${grouped.length} user(s) dalam "$oldCollectionName".');

    // Proses tiap user dalam batch (max 500 ops/batch, kita guna 200 untuk selamat)
    for (final entry in grouped.entries) {
      final userId = entry.key;
      final docs = entry.value;

      _log('  Migrate ${docs.length} dokumen untuk user: $userId...');

      const int chunkSize = 200;
      for (int start = 0; start < docs.length; start += chunkSize) {
        final chunk = docs.sublist(
          start,
          (start + chunkSize).clamp(0, docs.length),
        );

        final batch = _db.batch();
        final toDelete = <DocumentReference>[];

        for (final oldDoc in chunk) {
          final data = oldDoc.data() as Map<String, dynamic>;

          // Destination: users/{userId}/{subCollectionName}/{oldDocId}
          // Guna ID lama supaya data tidak duplikat kalau migrate dua kali
          final newRef = _db
              .collection('users')
              .doc(userId)
              .collection(subCollectionName)
              .doc(oldDoc.id);

          batch.set(newRef, data, SetOptions(merge: true));

          if (deleteOld) {
            toDelete.add(oldDoc.reference);
          }
        }

        await batch.commit();

        // Padam data lama dalam batch berasingan (selepas confirm write berjaya)
        if (deleteOld && toDelete.isNotEmpty) {
          final deleteBatch = _db.batch();
          for (final ref in toDelete) {
            deleteBatch.delete(ref);
          }
          await deleteBatch.commit();
        }

        // Kira jumlah mengikut collection
        final count = chunk.length;
        if (oldCollectionName == 'expenses') _migratedExpenses += count;
        if (oldCollectionName == 'savings_goals') _migratedGoals += count;
        if (oldCollectionName == 'recurring_expenses') _migratedRecurring += count;
      }
    }
  }

  void _reset() {
    _migratedExpenses = 0;
    _migratedGoals = 0;
    _migratedRecurring = 0;
    _skipped = 0;
    _errors = 0;
  }
}

// ── Result model ───────────────────────────────────────────────────────────

class MigrationResult {
  final bool success;
  final String? errorMessage;
  final int migratedExpenses;
  final int migratedGoals;
  final int migratedRecurring;
  final int skipped;
  final int errors;

  const MigrationResult({
    required this.success,
    this.errorMessage,
    required this.migratedExpenses,
    required this.migratedGoals,
    required this.migratedRecurring,
    required this.skipped,
    required this.errors,
  });

  int get total => migratedExpenses + migratedGoals + migratedRecurring;
}

