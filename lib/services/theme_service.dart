import 'package:flutter/material.dart';

enum AppTheme { eyeCare, brand, minimal, starVoyage, oceanGalaxy }

class ThemeService extends ChangeNotifier {
  AppTheme _current = AppTheme.brand;
  AppTheme get current => _current;

  ThemeData get themeData {
    switch (_current) {
      case AppTheme.eyeCare:    return _eyeCare;
      case AppTheme.brand:      return _brand;
      case AppTheme.minimal:    return _minimal;
      case AppTheme.starVoyage: return _starVoyage;
      case AppTheme.oceanGalaxy: return _oceanGalaxy;
    }
  }

  void switchTo(AppTheme theme) { _current = theme; notifyListeners(); }

  static String labelOf(AppTheme t) => switch (t) {
    AppTheme.eyeCare     => '护眼柔和',
    AppTheme.brand       => '品牌鲜明',
    AppTheme.minimal     => '极简',
    AppTheme.starVoyage  => '星际穿越',
    AppTheme.oceanGalaxy => '碧海银河',
  };

  // ========== 护眼柔和 ==========
  static final _eyeCare = ThemeData(
    useMaterial3: true, brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF7BA87B),
    scaffoldBackgroundColor: const Color(0xFFF7F4EF),
    cardTheme: CardTheme(elevation: 0, color: const Color(0xFFFDFCFA), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE8E4DC)))),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7F4EF), foregroundColor: Color(0xFF4A4A4A), elevation: 0),
  );

  // ========== 品牌鲜明 ==========
  static final _brand = ThemeData(
    useMaterial3: true, brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF6C63FF),
    scaffoldBackgroundColor: const Color(0xFFF5F3FF),
    cardTheme: CardTheme(elevation: 2, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF6C63FF), foregroundColor: Colors.white, elevation: 0),
  );

  // ========== 极简 ==========
  static final _minimal = ThemeData(
    useMaterial3: true, brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF2D2D2D),
    scaffoldBackgroundColor: const Color(0xFFFCFCFC),
    cardTheme: CardTheme(elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: const BorderSide(color: Color(0xFFEEEEEE)))),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Color(0xFF2D2D2D), elevation: 0.5),
  );

  // ========== 星际穿越 (#160A0A #F05D06 #EAE3CB) ==========
  static final _starVoyage = ThemeData(
    useMaterial3: true, brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: const Color(0xFFF05D06),
      secondary: const Color(0xFFF05D06).withOpacity(0.7),
      surface: const Color(0xFFEAE3CB),
      onPrimary: const Color(0xFFEAE3CB),
      onSurface: const Color(0xFF160A0A),
    ),
    scaffoldBackgroundColor: const Color(0xFFEAE3CB),
    cardTheme: CardTheme(elevation: 1, color: const Color(0xFFF4EFE2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: const Color(0xFFF05D06).withOpacity(0.2)))),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF160A0A), foregroundColor: Color(0xFFEAE3CB), elevation: 0),
    dividerColor: const Color(0xFFD5CFBA),
  );

  // ========== 碧海银河 (#144BB0 #F0F3F8 #18243C) ==========
  static final _oceanGalaxy = ThemeData(
    useMaterial3: true, brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: const Color(0xFF144BB0),
      secondary: const Color(0xFF144BB0).withOpacity(0.7),
      surface: const Color(0xFFF0F3F8),
      onPrimary: Colors.white,
      onSurface: const Color(0xFF18243C),
    ),
    scaffoldBackgroundColor: const Color(0xFFF0F3F8),
    cardTheme: CardTheme(elevation: 1, color: const Color(0xFF144BB0).withOpacity(0.08), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: const Color(0xFF144BB0).withOpacity(0.15)))),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF18243C), foregroundColor: Colors.white, elevation: 0),
    dividerColor: const Color(0xFFD0D8E5),
  );
}
