import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme { eyeCare, brand, minimal, starVoyage, oceanGalaxy }

/// 全局主题配色（v1.0.2 UI 设计稿）
///
/// 5 套主题统一通过 [AppThemeColors]（ThemeExtension）管理：
/// 导航栏 / 页面背景 / 强调色 / 卡片色，严禁在页面中硬编码色值。
/// 取用方式：`Theme.of(context).extension<AppThemeColors>()!`
class ThemeService extends ChangeNotifier {
  static const _prefsKey = 'app_theme';
  static const _modePrefsKey = 'app_theme_mode';

  AppTheme _current = AppTheme.brand;
  AppTheme get current => _current;

  // v1.0.2 七项改进：深色模式（light / dark / system）
  ThemeMode _mode = ThemeMode.light;
  ThemeMode get themeMode => _mode;

  /// v1.0.2 修复：启动时恢复上次选择的主题与深色模式
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_prefsKey);
      if (name != null) {
        final saved = AppTheme.values.where((t) => t.name == name).firstOrNull;
        if (saved != null) _current = saved;
      }
      final modeName = prefs.getString(_modePrefsKey);
      if (modeName != null) {
        _mode = ThemeMode.values.firstWhere((m) => m.name == modeName,
            orElse: () => ThemeMode.light);
      }
    } catch (_) {}
  }

  /// 浅色主题数据（MaterialApp.theme）
  ThemeData get themeData => _buildFor(dark: false);

  /// 深色主题数据（MaterialApp.darkTheme）
  ThemeData get darkThemeData => _buildFor(dark: true);

  ThemeData _buildFor({required bool dark}) {
    final colors = dark ? _darkColorsOf(_current) : _colorsOf(_current);
    switch (_current) {
      case AppTheme.eyeCare:
        return _buildTheme(_eyeCare, colors, dark: dark);
      case AppTheme.brand:
        return _buildTheme(_brand, colors, dark: dark);
      case AppTheme.minimal:
        return _buildTheme(_minimal, colors, dark: dark);
      case AppTheme.starVoyage:
        return _buildTheme(_starVoyage, colors, dark: dark);
      case AppTheme.oceanGalaxy:
        return _buildTheme(_oceanGalaxy, colors, dark: dark);
    }
  }

  /// v1.0.2 修复：主题切换持久化，重启后保留
  Future<void> switchTo(AppTheme theme) async {
    _current = theme;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, theme.name);
    } catch (_) {}
  }

  /// v1.0.2 七项改进：深色模式切换持久化
  Future<void> switchThemeMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modePrefsKey, mode.name);
    } catch (_) {}
  }

  static String labelOf(AppTheme t) => switch (t) {
        AppTheme.eyeCare     => '护眼柔和',
        AppTheme.brand       => '品牌鲜明',
        AppTheme.minimal     => '极简',
        AppTheme.starVoyage  => '星际穿越',
        AppTheme.oceanGalaxy => '碧海银河',
      };

  // ======================== 5 套主题配色（设计稿） ========================

  static AppThemeColors _colorsOf(AppTheme t) => switch (t) {
        // 主题1（品牌鲜明）：导航栏 #5D5FEF，背景 #F5F6FA，强调色 #5D5FEF
        AppTheme.brand => const AppThemeColors(
            navBar: Color(0xFF5D5FEF),
            background: Color(0xFFF5F6FA),
            accent: Color(0xFF5D5FEF),
            onAccent: Colors.white,
            card: Colors.white,
            cardBorder: Color(0xFFE8EAF6),
          ),
        // 主题2（护眼柔和）：导航栏 #DAE1D4，背景 #FAFAF9，强调色 #4A7A5D
        AppTheme.eyeCare => const AppThemeColors(
            navBar: Color(0xFFDAE1D4),
            background: Color(0xFFFAFAF9),
            accent: Color(0xFF4A7A5D),
            onAccent: Colors.white,
            card: Colors.white,
            cardBorder: Color(0xFFE4E8E0),
          ),
        // 主题3（极简风格）：导航栏 #E4ECF3，背景 #F9FAFB，强调色 #2DA8A6
        AppTheme.minimal => const AppThemeColors(
            navBar: Color(0xFFE4ECF3),
            background: Color(0xFFF9FAFB),
            accent: Color(0xFF2DA8A6),
            onAccent: Colors.white,
            card: Colors.white,
            cardBorder: Color(0xFFE5EBF0),
          ),
        // 主题4（星际穿越）：导航栏 #1D1A1A，背景 #E8DDCB，强调色 #E96D39
        AppTheme.starVoyage => const AppThemeColors(
            navBar: Color(0xFF1D1A1A),
            background: Color(0xFFE8DDCB),
            accent: Color(0xFFE96D39),
            onAccent: Colors.white,
            card: Color(0xFFF4EEE2),
            cardBorder: Color(0xFFD9CDB8),
          ),
        // 主题5（碧海银河）：导航栏 #1A253E，背景 #F0F4F9，强调色 #4C7CD6
        AppTheme.oceanGalaxy => const AppThemeColors(
            navBar: Color(0xFF1A253E),
            background: Color(0xFFF0F4F9),
            accent: Color(0xFF4C7CD6),
            onAccent: Colors.white,
            card: Colors.white,
            cardBorder: Color(0xFFDDE6F2),
          ),
      };

  // ======================== 5 套深色配色（v1.0.2 七项改进：深色模式） ========================

  /// 深色变体：深底浅强调色，保证对比度（onAccent 用深色适配浅色强调）
  static AppThemeColors _darkColorsOf(AppTheme t) => switch (t) {
        // 品牌鲜明-dark：靛蓝强调，深墨蓝底
        AppTheme.brand => const AppThemeColors(
            navBar: Color(0xFF4344B8),
            background: Color(0xFF14151F),
            accent: Color(0xFF8B8CF8),
            onAccent: Color(0xFF14151F),
            card: Color(0xFF1F2030),
            cardBorder: Color(0xFF2C2D42),
          ),
        // 护眼柔和-dark：暗绿底，柔和绿强调
        AppTheme.eyeCare => const AppThemeColors(
            navBar: Color(0xFF2C3A31),
            background: Color(0xFF131713),
            accent: Color(0xFF7BA98A),
            onAccent: Color(0xFF131713),
            card: Color(0xFF1B201C),
            cardBorder: Color(0xFF2E362F),
          ),
        // 极简-dark：深青底，青色强调
        AppTheme.minimal => const AppThemeColors(
            navBar: Color(0xFF17464A),
            background: Color(0xFF0F1517),
            accent: Color(0xFF57CBC4),
            onAccent: Color(0xFF0F1517),
            card: Color(0xFF172023),
            cardBorder: Color(0xFF243034),
          ),
        // 星际穿越-dark：深棕底，暖橙强调
        AppTheme.starVoyage => const AppThemeColors(
            navBar: Color(0xFF33241B),
            background: Color(0xFF1A1410),
            accent: Color(0xFFF08A52),
            onAccent: Color(0xFF1A1410),
            card: Color(0xFF251C14),
            cardBorder: Color(0xFF3A2C1F),
          ),
        // 碧海银河-dark：深蓝底，亮蓝强调
        AppTheme.oceanGalaxy => const AppThemeColors(
            navBar: Color(0xFF1D2A4A),
            background: Color(0xFF101624),
            accent: Color(0xFF7CA3E8),
            onAccent: Color(0xFF101624),
            card: Color(0xFF182136),
            cardBorder: Color(0xFF26334F),
          ),
      };

  /// 由配色生成完整 ThemeData：ColorScheme 以强调色为种子，
  /// AppBar 用导航栏色，背景用主题背景色，并挂载 AppThemeColors 扩展
  static ThemeData _buildTheme(ThemeData base, AppThemeColors colors,
      {required bool dark}) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
    ).copyWith(
      primary: colors.accent,
      onPrimary: colors.onAccent,
      surface: colors.background,
    );
    // 导航栏文字对比色：浅色导航栏用深字，深色导航栏用白字
    final navForeground =
        ThemeData.estimateBrightnessForColor(colors.navBar) == Brightness.dark
            ? Colors.white
            : const Color(0xFF1F2933);
    return base.copyWith(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.navBar,
        foregroundColor: navForeground,
        elevation: 0,
        titleTextStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: navForeground),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.cardBorder),
        ),
      ),
      extensions: [colors],
    );
  }

  // ========== 各主题基础配置（间距/圆角/卡片样式，色值统一走配色） ==========

  static final _brand = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF5D5FEF),
    cardTheme: CardTheme(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE8EAF6))),
    ),
  );

  static final _eyeCare = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF4A7A5D),
    cardTheme: CardTheme(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE4E8E0))),
    ),
  );

  static final _minimal = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF2DA8A6),
    cardTheme: CardTheme(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFE5EBF0))),
    ),
  );

  static final _starVoyage = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFFE96D39),
    cardTheme: CardTheme(
      elevation: 1,
      color: const Color(0xFFF4EEE2),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFD9CDB8))),
    ),
  );

  static final _oceanGalaxy = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF4C7CD6),
    cardTheme: CardTheme(
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFDDE6F2))),
    ),
  );
}

/// 全局主题配色扩展（UI 设计稿 5 套主题的导航栏/背景/强调色等）
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  /// 导航栏颜色
  final Color navBar;

  /// 页面背景色
  final Color background;

  /// 强调色（按钮/高亮/进度条等）
  final Color accent;

  /// 强调色上的文字/图标
  final Color onAccent;

  /// 卡片背景
  final Color card;

  /// 卡片描边
  final Color cardBorder;

  // ===== v1.0.2 设计审查修复：语义色（判定对错/背题高亮等跨主题一致） =====

  /// 成功/正确语义色（判题对、背题高亮等）
  final Color success;

  /// 成功语义浅底色
  final Color successContainer;

  /// 危险/错误语义色（判题错等）
  final Color danger;

  /// 危险语义浅底色
  final Color dangerContainer;

  /// 警告语义色（余额不足、未配置提示等）
  final Color warning;

  const AppThemeColors({
    required this.navBar,
    required this.background,
    required this.accent,
    required this.onAccent,
    required this.card,
    required this.cardBorder,
    this.success = const Color(0xFF5CB85C),
    this.successContainer = const Color(0xFFE8F5E9),
    this.danger = const Color(0xFFD9534F),
    this.dangerContainer = const Color(0xFFFDECEA),
    this.warning = const Color(0xFFF0AD4E),
  });

  @override
  AppThemeColors copyWith({
    Color? navBar,
    Color? background,
    Color? accent,
    Color? onAccent,
    Color? card,
    Color? cardBorder,
    Color? success,
    Color? successContainer,
    Color? danger,
    Color? dangerContainer,
    Color? warning,
  }) {
    return AppThemeColors(
      navBar: navBar ?? this.navBar,
      background: background ?? this.background,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppThemeColors lerp(AppThemeColors? other, double t) {
    if (other == null) return this;
    return AppThemeColors(
      navBar: Color.lerp(navBar, other.navBar, t)!,
      background: Color.lerp(background, other.background, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }

  /// 便捷取用：Theme.of(context).extension<AppThemeColors>()!
  static AppThemeColors of(BuildContext context) =>
      Theme.of(context).extension<AppThemeColors>()!;
}
