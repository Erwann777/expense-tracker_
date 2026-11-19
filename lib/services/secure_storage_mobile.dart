// Mobile implementation — uses shared_preferences (flutter_secure_storage removed for cross-platform compatibility)
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
