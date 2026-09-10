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

  /// v1.0.2 UI 审查修复：主题选择行的三色预览（导航/背景/强调）
  static List<Color> previewColorsOf(AppTheme t) {
    final c = _colorsOf(t);
    return [c.navBar, c.background, c.accent];
  }

  // ======================== 5 套主题配色（设计稿） ========================

  static AppThemeColors _colorsOf(AppTheme t) => switch (t) {
        // 主题1（品牌鲜明）：医疗/学术深蓝调
        AppTheme.brand => const AppThemeColors(
            navBar: Color(0xFF1E3A5F),
            background: Color(0xFFF0F4F8),
            accent: Color(0xFF2563EB),
            onAccent: Colors.white,
            card: Colors.white,
            cardBorder: Color(0xFFD9E2EC),
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
        // 主题4（星际穿越）：宇宙紫调浅色版
        AppTheme.starVoyage => const AppThemeColors(
            navBar: Color(0xFF1E1B4B),
            background: Color(0xFFF5F3FF),
            accent: Color(0xFF7C3AED),
            onAccent: Colors.white,
            card: Colors.white,
            cardBorder: Color(0xFFDDD6FE),
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
  ///
  /// 语义色深色适配：success/danger 提亮为 400 档保证深底可读，
  /// container 用 900 档深底替代浅色马卡龙底，避免深模式下出现刺眼亮块。
  static AppThemeColors _darkColorsOf(AppTheme t) => switch (t) {
        // 品牌鲜明-dark：深海蓝底，亮蓝强调
        AppTheme.brand => const AppThemeColors(
            navBar: Color(0xFF1A2B45),
            background: Color(0xFF0F172A),
            accent: Color(0xFF60A5FA),
            onAccent: Color(0xFF0F172A),
            card: Color(0xFF1E293B),
            cardBorder: Color(0xFF334155),
            success: Color(0xFF4ADE80),
            successContainer: Color(0xFF14532D),
            danger: Color(0xFFF87171),
            dangerContainer: Color(0xFF7F1D1D),
          ),
        // 护眼柔和-dark：暗绿底，柔和绿强调
        AppTheme.eyeCare => const AppThemeColors(
            navBar: Color(0xFF2C3A31),
            background: Color(0xFF131713),
            accent: Color(0xFF7BA98A),
            onAccent: Color(0xFF131713),
            card: Color(0xFF1B201C),
            cardBorder: Color(0xFF2E362F),
            success: Color(0xFF4ADE80),
            successContainer: Color(0xFF14532D),
            danger: Color(0xFFF87171),
            dangerContainer: Color(0xFF7F1D1D),
          ),
        // 极简-dark：深青底，青色强调
        AppTheme.minimal => const AppThemeColors(
            navBar: Color(0xFF17464A),
            background: Color(0xFF0F1517),
            accent: Color(0xFF57CBC4),
            onAccent: Color(0xFF0F1517),
            card: Color(0xFF172023),
            cardBorder: Color(0xFF243034),
            success: Color(0xFF4ADE80),
            successContainer: Color(0xFF14532D),
            danger: Color(0xFFF87171),
            dangerContainer: Color(0xFF7F1D1D),
          ),
        // 星际穿越-dark：深紫宇宙
        AppTheme.starVoyage => const AppThemeColors(
            navBar: Color(0xFF0F0720),
            background: Color(0xFF020617),
            accent: Color(0xFFC084FC),
            onAccent: Color(0xFF020617),
            card: Color(0xFF1E1B4B),
            cardBorder: Color(0xFF312E81),
            success: Color(0xFF4ADE80),
            successContainer: Color(0xFF14532D),
            danger: Color(0xFFF87171),
            dangerContainer: Color(0xFF7F1D1D),
          ),
        // 碧海银河-dark：深蓝底，亮蓝强调
        AppTheme.oceanGalaxy => const AppThemeColors(
            navBar: Color(0xFF1D2A4A),
            background: Color(0xFF101624),
            accent: Color(0xFF7CA3E8),
            onAccent: Color(0xFF101624),
            card: Color(0xFF182136),
            cardBorder: Color(0xFF26334F),
            success: Color(0xFF4ADE80),
            successContainer: Color(0xFF14532D),
            danger: Color(0xFFF87171),
            dangerContainer: Color(0xFF7F1D1D),
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
      // v1.27 视觉柔和化：统一 MiSans 字体（全端一致，现代字形），
      // Material 排版整体放大一档（基础 14→15），降低长时间阅读疲劳。
      textTheme: _comfortTextTheme(base.textTheme),
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.navBar,
        foregroundColor: navForeground,
        elevation: 0,
        titleTextStyle: TextStyle(
            fontFamily: 'MiSans',
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: navForeground),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          // v1.27 呼吸感：全局卡片描边弱化，依靠底色与间距区分层次。
          side: BorderSide(color: colors.cardBorder.withOpacity(0.7)),
        ),
      ),
      extensions: [colors],
    );
  }

  // ========== 各主题基础配置（间距/圆角/卡片样式，色值统一走配色） ==========

  /// v1.27 舒适排版：统一注入 MiSans + 有字号的样式放大一档。
  /// 逐样式安全处理（基础主题存在 fontSize 为 null 的样式，
  /// 直接 TextTheme.apply(fontSizeDelta) 会触发断言）。
  static TextStyle? _comfort(TextStyle? s) => s == null
      ? null
      : s.apply(
          fontFamily: 'MiSans',
          fontSizeDelta: s.fontSize == null ? 0.0 : 1.0,
        );

  static TextTheme _comfortTextTheme(TextTheme t) => TextTheme(
        displayLarge: _comfort(t.displayLarge),
        displayMedium: _comfort(t.displayMedium),
        displaySmall: _comfort(t.displaySmall),
        headlineLarge: _comfort(t.headlineLarge),
        headlineMedium: _comfort(t.headlineMedium),
        headlineSmall: _comfort(t.headlineSmall),
        titleLarge: _comfort(t.titleLarge),
        titleMedium: _comfort(t.titleMedium),
        titleSmall: _comfort(t.titleSmall),
        bodyLarge: _comfort(t.bodyLarge),
        bodyMedium: _comfort(t.bodyMedium),
        bodySmall: _comfort(t.bodySmall),
        labelLarge: _comfort(t.labelLarge),
        labelMedium: _comfort(t.labelMedium),
        labelSmall: _comfort(t.labelSmall),
      );

  static final _brand = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF2563EB),
    cardTheme: CardTheme(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD9E2EC))),
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
          borderRadius: BorderRadius.circular(16),
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
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5EBF0))),
    ),
  );

  static final _starVoyage = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF7C3AED),
    cardTheme: CardTheme(
      elevation: 1,
      color: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFDDD6FE))),
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
          borderRadius: BorderRadius.circular(16),
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
  // 视觉审查修复（对比度）：浅色档默认值改用 700 档深绿/深红，
  // 白底文字对比度达标（≥4.5:1）；深色模式由 _darkColorsOf 覆盖为 400 档亮色。

  /// 成功/正确语义色（判题对、背题高亮等）
  final Color success;

  /// 成功语义浅底色（深色模式下为深绿底）
  final Color successContainer;

  /// 危险/错误语义色（判题错等）
  final Color danger;

  /// 危险语义浅底色（深色模式下为深红底）
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
    this.success = const Color(0xFF15803D),
    this.successContainer = const Color(0xFFDCFCE7),
    this.danger = const Color(0xFFB91C1C),
    this.dangerContainer = const Color(0xFFFEE2E2),
    this.warning = const Color(0xFFF59E0B),
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
