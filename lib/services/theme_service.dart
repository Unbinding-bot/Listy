// lib/services/theme_service.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// List of available colors for the user to choose
const List<Color> themeColors = [
  Colors.amber, // Default/Keep style
  Colors.blue,
  Colors.green,
  Colors.purple,
];

class ThemeService extends ChangeNotifier {
  Color _themeColor = themeColors.first;
  Color get themeColor => _themeColor;
  
  // Key for local storage
  static const _themeKey = 'selectedThemeColor';

  ThemeService() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_themeKey);
    if (colorValue != null) {
      _themeColor = Color(colorValue);
    }
    notifyListeners();
  }

  Future<void> setThemeColor(Color color) async {
    _themeColor = color;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    // Save color value as an integer
    await prefs.setInt(_themeKey, color.value);
  }
}