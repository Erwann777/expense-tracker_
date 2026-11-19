import '../utils/model_parsers.dart';

class UserModel {
  final String? id;
  final String username;
  final String password;
  final String displayName;

  /// Currency yang ditampilkan ke user saat ini (bisa diubah kapan saja)
  final String currency;

  /// Currency dasar tempat amount disimpan di Firestore.
  /// Defaultnya sama dengan [currency] saat pertama kali daftar.
  /// Tidak boleh berubah kecuali user reset data.
  final String baseCurrency;

  final double monthlyBudget;
  final String? avatarEmoji;
  final String? profilePhotoPath;
  final String? pin;
  final DateTime createdAt;

  UserModel({
    this.id,
    required this.username,
    required this.password,
    required this.displayName,
    this.currency = 'USD',
    String? baseCurrency,
    this.monthlyBudget = 1000.0,
    this.avatarEmoji,
    this.profilePhotoPath,
    this.pin,
    DateTime? createdAt,
  })  : baseCurrency = baseCurrency ?? currency,
        createdAt = createdAt ?? DateTime.now();

  /// toMap() does NOT include 'id' — Firestore uses document ID for that.
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'password': password,
      'display_name': displayName,
      'currency': currency,
      'base_currency': baseCurrency,
      'monthly_budget': monthlyBudget,
      'avatar_emoji': avatarEmoji,
      'profile_photo_path': profilePhotoPath,
      'pin': pin,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final currency = ModelParsers.parseString(map['currency'], 'USD');
    return UserModel(
      id: map['id']?.toString(),
      username: ModelParsers.parseString(map['username']),
      password: ModelParsers.parseString(map['password']),
      displayName: ModelParsers.parseString(map['display_name'] ?? map['displayName'], 'User'),
      currency: currency,
      baseCurrency: ModelParsers.parseString(map['base_currency'], currency),
      monthlyBudget: ModelParsers.parseDouble(map['monthly_budget'] ?? map['monthlyBudget'], 1000.0),
      avatarEmoji: map['avatar_emoji'] as String?,
      profilePhotoPath: map['profile_photo_path'] as String?,
      pin: map['pin']?.toString(),
      createdAt: ModelParsers.parseDateTime(map['created_at'] ?? map['createdAt']),
    );
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? password,
    String? displayName,
    String? currency,
    String? baseCurrency,
    double? monthlyBudget,
    String? avatarEmoji,
    String? profilePhotoPath,
    String? pin,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      displayName: displayName ?? this.displayName,
      currency: currency ?? this.currency,
      baseCurrency: baseCurrency ?? this.baseCurrency,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      profilePhotoPath: profilePhotoPath ?? this.profilePhotoPath,
      pin: pin ?? this.pin,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
