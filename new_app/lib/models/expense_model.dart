import '../utils/model_parsers.dart';

class ExpenseModel {
  final String? id;
  final String userId;
  final String title;
  final double amount;
  final String category;
  final String type; // 'expense' or 'income'
  final String? note;
  final DateTime date;
  final String? receiptPath;
  final bool isHidden;
  final String? recurringId;
  final String? splitGroupId;
  final DateTime createdAt;

  ExpenseModel({
    this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.category,
    this.type = 'expense',
    this.note,
    required this.date,
    this.receiptPath,
    this.isHidden = false,
    this.recurringId,
    this.splitGroupId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';

  /// toMap() does NOT include 'id' — Firestore uses document ID for that.
  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'title': title,
      'amount': amount,
      'category': category,
      'type': type,
      'note': note,
      'date': date.toIso8601String(),
      'receipt_path': receiptPath,
      'is_hidden': isHidden,
      'recurring_id': recurringId,
      'split_group_id': splitGroupId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    return ExpenseModel(
      id: map['id']?.toString(),
      userId: ModelParsers.parseString(map['user_id'] ?? map['userId']),
      title: ModelParsers.parseString(map['title'] ?? map['name'], 'Expense'),
      amount: ModelParsers.parseDouble(map['amount']),
      category: ModelParsers.parseString(map['category'], 'Other'),
      type: ModelParsers.parseString(map['type'], 'expense'),
      note: map['note'] as String?,
      date: ModelParsers.parseDateTime(map['date']),
      receiptPath: map['receipt_path'] as String?,
      isHidden: ModelParsers.parseBool(map['is_hidden'] ?? map['isHidden'], false),
      recurringId: map['recurring_id']?.toString() ?? map['recurringId']?.toString(),
      splitGroupId: map['split_group_id']?.toString() ?? map['splitGroupId']?.toString(),
      createdAt: ModelParsers.parseDateTime(map['created_at'] ?? map['createdAt']),
    );
  }

  ExpenseModel copyWith({
    String? id,
    String? userId,
    String? title,
    double? amount,
    String? category,
    String? type,
    String? note,
    DateTime? date,
    String? receiptPath,
    bool? isHidden,
    String? recurringId,
    String? splitGroupId,
    DateTime? createdAt,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      type: type ?? this.type,
      note: note ?? this.note,
      date: date ?? this.date,
      receiptPath: receiptPath ?? this.receiptPath,
      isHidden: isHidden ?? this.isHidden,
      recurringId: recurringId ?? this.recurringId,
      splitGroupId: splitGroupId ?? this.splitGroupId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
