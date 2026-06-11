import 'package:shared_preferences/shared_preferences.dart';

class UploadCache {
  static const String _key = 'uploaded_hashes';

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key);
    return raw?.toSet() ?? {};
  }

  static Future<void> mark(String hash) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.add(hash);
    await prefs.setStringList(_key, list.toSet().toList());
  }

  static Future<bool> exists(String hash) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.contains(hash);
  }
}
