import '../utils/model_parsers.dart';

class RecurringExpenseModel {
  final String? id;
  final String userId;
  final String title;
  final double amount;
  final String category;
  final String frequency; // 'daily', 'weekly', 'monthly', 'yearly'
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? lastTriggered;
  final bool isActive;
  final DateTime createdAt;

  RecurringExpenseModel({
    this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.category,
    required this.frequency,
    required this.startDate,
    this.endDate,
    this.lastTriggered,
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// toMap() does NOT include 'id' — Firestore uses document ID for that.
  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'title': title,
      'amount': amount,
      'category': category,
      'frequency': frequency,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'last_triggered': lastTriggered?.toIso8601String(),
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory RecurringExpenseModel.fromMap(Map<String, dynamic> map) {
    return RecurringExpenseModel(
      id: map['id']?.toString(),
      userId: ModelParsers.parseString(map['user_id'] ?? map['userId']),
      title: ModelParsers.parseString(map['title'] ?? map['name'], 'Recurring'),
      amount: ModelParsers.parseDouble(map['amount'] ?? map['balance']),
      category: ModelParsers.parseString(map['category'], 'Other'),
      frequency: ModelParsers.parseString(map['frequency'], 'monthly'),
      startDate: ModelParsers.parseDateTime(map['start_date'] ?? map['startDate']),
      endDate: ModelParsers.parseOptionalDateTime(map['end_date'] ?? map['endDate']),
      lastTriggered: ModelParsers.parseOptionalDateTime(map['last_triggered'] ?? map['lastTriggered']),
      isActive: ModelParsers.parseBool(map['is_active'] ?? map['isActive'], true),
      createdAt: ModelParsers.parseDateTime(map['created_at'] ?? map['createdAt']),
    );
  }

  RecurringExpenseModel copyWith({
    String? id,
    String? userId,
    String? title,
    double? amount,
    String? category,
    String? frequency,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? lastTriggered,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return RecurringExpenseModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      lastTriggered: lastTriggered ?? this.lastTriggered,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  DateTime get nextDueDate {
    final base = lastTriggered ?? startDate;
    switch (frequency) {
      case 'daily':
        return base.add(const Duration(days: 1));
      case 'weekly':
        return base.add(const Duration(days: 7));
      case 'monthly':
        return DateTime(base.year, base.month + 1, base.day);
      case 'yearly':
        return DateTime(base.year + 1, base.month, base.day);
      default:
        return base.add(const Duration(days: 30));
    }
  }

  bool get isDue => DateTime.now().isAfter(nextDueDate);

  static const frequencies = [
    {'key': 'daily', 'label': 'Daily', 'icon': '📅'},
    {'key': 'weekly', 'label': 'Weekly', 'icon': '📆'},
    {'key': 'monthly', 'label': 'Monthly', 'icon': '🗓️'},
    {'key': 'yearly', 'label': 'Yearly', 'icon': '📋'},
  ];
}
