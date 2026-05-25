import 'models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class UserPreferenceManager extends ChangeNotifier {
  static final UserPreferenceManager _instance = UserPreferenceManager._internal();
  factory UserPreferenceManager() => _instance;
  UserPreferenceManager._internal();

  // 预留设置接口，默认使用 toeflIelts
  PromptStrategy currentPromptStrategy = PromptStrategy.toeflIelts;

  bool _isDarkMode = false;
  bool _enableFinalRecap = false; 
  bool _enableLectureDiscovery = false; // [New Feature] 讲座身份自动探测

  bool get isDarkMode => _isDarkMode;
  bool get enableFinalRecap => _enableFinalRecap;
  bool get enableLectureDiscovery => _enableLectureDiscovery;

  Future<void> init() async {
    await _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _enableFinalRecap = prefs.getBool('enableFinalRecap') ?? false;
    _enableLectureDiscovery = prefs.getBool('enableLectureDiscovery') ?? false;
    notifyListeners();
  }

  Future<void> toggleLectureDiscovery(bool value) async {
    _enableLectureDiscovery = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enableLectureDiscovery', value);
    notifyListeners();
  }

  Future<void> toggleFinalRecap(bool value) async {
    _enableFinalRecap = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enableFinalRecap', value);
    notifyListeners();
  }
}
