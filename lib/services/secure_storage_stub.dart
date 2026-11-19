// Stub for non-mobile platforms (Windows, Linux, macOS, Web)
// Uses shared_preferences instead of flutter_secure_storage to avoid ATL dependency

import 'package:shared_preferences/shared_preferences.dart';

class SecureStorageHelper {
  static Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  static Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
