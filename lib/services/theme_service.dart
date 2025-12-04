// lib/services/theme_service.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
//
// List of available colors for the user to choose
const List<Color> themeColors = [
  Colors.amber, // Default/Keep style
  Colors.blue,
  Colors.green,
  Colors.purple,
];

class ThemeService extends ChangeNotifier {
  // --- Color State ---
  Color _themeColor = themeColors.first;
  Color get themeColor => _themeColor;
  static const _themeColorKey = 'selectedThemeColor'; // Renamed key for clarity

  // --- Dark Mode State ---
  bool _isDarkMode = true; // DEFAULT: Set dark mode as default
  bool get isDarkMode => _isDarkMode;
  static const _themeModeKey = 'isDarkMode'; // New key for dark mode

  ThemeService() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Color Preference
    final colorValue = prefs.getInt(_themeColorKey);
    if (colorValue != null) {
      _themeColor = Color(colorValue);
    }
    
    // Load Dark Mode Preference (Default to true if not found)
    _isDarkMode = prefs.getBool(_themeModeKey) ?? true;
    
    notifyListeners();
  }

  // --- Color Toggle Function (Existing) ---
  Future<void> setThemeColor(Color color) async {
    _themeColor = color;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeColorKey, color.value);
  }

  
  Future<void> toggleDarkMode(bool value) async {
    if (_isDarkMode == value) return; // Prevent unnecessary writes
    
    _isDarkMode = value;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeModeKey, _isDarkMode);
  }
}