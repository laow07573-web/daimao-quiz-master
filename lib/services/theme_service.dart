import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/design_tokens.dart';

/// 主题枚举（v1.28 全新设计语言：5 套精简为 3 套）
enum AppTheme {
  /// 清蓝（默认）：清爽专业
  clear,

  /// 松绿：护眼低疲劳
  sage,

  /// 墨黑：深色优先
  ink,
}

/// 全局主题「Mao Des」
///
/// 设计语言：显式定义 12 个语义色位，不再依赖 Material 3 的
/// `fromSeed` 自动生成 secondary/tertiary（那是旧版"色相过载"的根源）。
/// 组件视觉（按钮/输入框/弹窗/底部导航/卡片…）全部在此统一定义，
/// 页面侧不得再裸用 Material 默认样式。
class ThemeService extends ChangeNotifier {
  static const _prefsKey = 'app_theme';
  static const _modePrefsKey = 'app_theme_mode';

  AppTheme _current = AppTheme.clear;
  AppTheme get current => _current;

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get themeMode => _mode;

  /// 启动时恢复上次选择。旧版本存档 5 套主题名 → 平滑映射到新 3 套，
  /// 老用户升级不会丢失主题偏好。
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_prefsKey);
      if (name != null) {
        final direct = AppTheme.values.where((t) => t.name == name).firstOrNull;
        _current = direct ?? _migrateLegacyTheme(name);
      }
      final modeName = prefs.getString(_modePrefsKey);
      if (modeName != null) {
        _mode = ThemeMode.values.firstWhere((m) => m.name == modeName,
            orElse: () => ThemeMode.system);
      }
    } catch (_) {}
  }

  /// 旧 5 套 → 新 3 套的映射（按色相接近度）
  static AppTheme _migrateLegacyTheme(String legacy) => switch (legacy) {
        'brand' || 'oceanGalaxy' => AppTheme.clear,
        'eyeCare' || 'minimal' => AppTheme.sage,
        'starVoyage' => AppTheme.ink,
        _ => AppTheme.clear,
      };

  ThemeData get themeData => _buildFor(dark: false);
  ThemeData get darkThemeData => _buildFor(dark: true);

  ThemeData _buildFor({required bool dark}) {
    final colors = dark ? _darkOf(_current) : _lightOf(_current);
    return _buildTheme(colors, dark: dark);
  }

  Future<void> switchTo(AppTheme theme) async {
    if (_current == theme) return;
    _current = theme;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, theme.name);
    } catch (_) {}
  }

  Future<void> switchThemeMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modePrefsKey, mode.name);
    } catch (_) {}
  }

  static String labelOf(AppTheme t) => switch (t) {
        AppTheme.clear => '清蓝',
        AppTheme.sage => '松绿',
        AppTheme.ink => '墨黑',
      };

  static String descOf(AppTheme t) => switch (t) {
        AppTheme.clear => '清爽专业',
        AppTheme.sage => '护眼低疲劳',
        AppTheme.ink => '深色优先',
      };

  /// 主题选择行的色板预览（背景 / 卡片 / 强调色）
  static List<Color> previewColorsOf(AppTheme t) {
    final c = _lightOf(t);
    return [c.background, c.surface, c.accent];
  }

  // ======================== 三套主题色板（Mao Des 2.0 · 精密） ========================
  //
  // 六套色板的共同规则（精密暗色的地基）：
  //   1. 背景 ↔ 面板 ↔ 次级面 之间只差 2~4 级明度，层级靠极小的明度差 + 描边
  //   2. 描边是唯一的分隔手段：暗色 #23xxxx 级、浅色 #E4xxxx 级
  //   3. 文字三级层次拉开（主 100% / 次 ~50% / 弱 ~30%），但都压在冷灰上
  //   4. 语义色（success/danger/warning）跨主题保持认知一致，只换深浅

  static AppThemeColors _lightOf(AppTheme t) => switch (t) {
        // 清蓝-浅：白底 + 精密靛蓝（Linear 亮色）
        AppTheme.clear => const AppThemeColors(
            background: Color(0xFFFAFAFA),
            surface: Color(0xFFFFFFFF),
            surfaceAlt: Color(0xFFF4F4F5),
            border: Color(0xFFE4E4E7),
            textPrimary: Color(0xFF18181B),
            textSecondary: Color(0xFF71717A),
            textTertiary: Color(0xFFA1A1AA),
            accent: Color(0xFF5E6AD2),
            accentSoft: Color(0xFFEEF0FB),
            onAccent: Color(0xFFFFFFFF),
            navBackground: Color(0xFFFFFFFF),
            navForeground: Color(0xFF18181B),
            success: Color(0xFF1A7F37),
            successSoft: Color(0xFFDAFBE1),
            danger: Color(0xFFCF222E),
            dangerSoft: Color(0xFFFFEBE9),
            warning: Color(0xFF9A6700),
          ),
        // 松绿-浅：白底 + 精密青绿
        AppTheme.sage => const AppThemeColors(
            background: Color(0xFFFAFBFB),
            surface: Color(0xFFFFFFFF),
            surfaceAlt: Color(0xFFF2F5F3),
            border: Color(0xFFE3E8E4),
            textPrimary: Color(0xFF161B18),
            textSecondary: Color(0xFF5F6B64),
            textTertiary: Color(0xFF98A29C),
            accent: Color(0xFF1F8A63),
            accentSoft: Color(0xFFE7F4EF),
            onAccent: Color(0xFFFFFFFF),
            navBackground: Color(0xFFFFFFFF),
            navForeground: Color(0xFF161B18),
            success: Color(0xFF1A7F37),
            successSoft: Color(0xFFDAFBE1),
            danger: Color(0xFFCF222E),
            dangerSoft: Color(0xFFFFEBE9),
            warning: Color(0xFF9A6700),
          ),
        // 墨黑-浅：Vercel 亮色（黑按钮 + 中性灰阶）
        AppTheme.ink => const AppThemeColors(
            background: Color(0xFFFAFAFA),
            surface: Color(0xFFFFFFFF),
            surfaceAlt: Color(0xFFF4F4F5),
            border: Color(0xFFE4E4E7),
            textPrimary: Color(0xFF18181B),
            textSecondary: Color(0xFF71717A),
            textTertiary: Color(0xFFA1A1AA),
            accent: Color(0xFF18181B),
            accentSoft: Color(0xFFF4F4F5),
            onAccent: Color(0xFFFFFFFF),
            navBackground: Color(0xFFFFFFFF),
            navForeground: Color(0xFF18181B),
            success: Color(0xFF1A7F37),
            successSoft: Color(0xFFDAFBE1),
            danger: Color(0xFFCF222E),
            dangerSoft: Color(0xFFFFEBE9),
            warning: Color(0xFF9A6700),
          ),
      };

  static AppThemeColors _darkOf(AppTheme t) => switch (t) {
        // 清蓝-深：近黑画布 + 精密靛蓝（默认主态，最 Linear）
        AppTheme.clear => const AppThemeColors(
            background: Color(0xFF08090A),
            surface: Color(0xFF101113),
            surfaceAlt: Color(0xFF16171A),
            border: Color(0xFF23252A),
            textPrimary: Color(0xFFF7F8F8),
            textSecondary: Color(0xFF8A8F98),
            textTertiary: Color(0xFF5C6069),
            accent: Color(0xFF5E6AD2),
            accentSoft: Color(0xFF1C1F3A),
            onAccent: Color(0xFFFFFFFF),
            navBackground: Color(0xFF0B0C0E),
            navForeground: Color(0xFFF7F8F8),
            success: Color(0xFF3FB950),
            successSoft: Color(0xFF0D2818),
            danger: Color(0xFFF85149),
            dangerSoft: Color(0xFF2D1214),
            warning: Color(0xFFD29922),
          ),
        // 松绿-深：近黑画布 + 精密青绿
        AppTheme.sage => const AppThemeColors(
            background: Color(0xFF080A09),
            surface: Color(0xFF101312),
            surfaceAlt: Color(0xFF161A18),
            border: Color(0xFF232825),
            textPrimary: Color(0xFFF6F8F7),
            textSecondary: Color(0xFF8A948E),
            textTertiary: Color(0xFF5C665F),
            accent: Color(0xFF2FA37A),
            accentSoft: Color(0xFF10251D),
            onAccent: Color(0xFFFFFFFF),
            navBackground: Color(0xFF0A0C0B),
            navForeground: Color(0xFFF6F8F7),
            success: Color(0xFF3FB950),
            successSoft: Color(0xFF0D2818),
            danger: Color(0xFFF85149),
            dangerSoft: Color(0xFF2D1214),
            warning: Color(0xFFD29922),
          ),
        // 墨黑-深：中性石墨 + 单色强调（最 Vercel：白按钮 + 灰阶）
        AppTheme.ink => const AppThemeColors(
            background: Color(0xFF08090A),
            surface: Color(0xFF0F1011),
            surfaceAlt: Color(0xFF16181A),
            border: Color(0xFF242628),
            textPrimary: Color(0xFFF7F8F8),
            textSecondary: Color(0xFF8A8F98),
            textTertiary: Color(0xFF5C6069),
            accent: Color(0xFFE8E8EA),
            accentSoft: Color(0xFF1F2124),
            onAccent: Color(0xFF0A0A0B),
            navBackground: Color(0xFF0B0C0D),
            navForeground: Color(0xFFF7F8F8),
            success: Color(0xFF3FB950),
            successSoft: Color(0xFF0D2818),
            danger: Color(0xFFF85149),
            dangerSoft: Color(0xFF2D1214),
            warning: Color(0xFFD29922),
          ),
      };

  // ======================== ThemeData 组装 ========================

  static ThemeData _buildTheme(AppThemeColors c, {required bool dark}) {
    final brightness = dark ? Brightness.dark : Brightness.light;

    // ColorScheme 显式构造（不用 fromSeed），避免自动生成不受控的色相
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accent,
      secondary: c.textSecondary,
      onSecondary: c.surface,
      secondaryContainer: c.surfaceAlt,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.accent,
      onTertiary: c.onAccent,
      error: c.danger,
      onError: c.onAccent,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.danger,
      surface: c.background,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerHighest: c.surfaceAlt,
      surfaceContainerHigh: c.surfaceAlt,
      surfaceContainer: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainerLowest: c.surface,
      outline: c.border,
      outlineVariant: c.border,
      shadow: const Color(0x1A000000),
      scrim: const Color(0x80000000),
      inverseSurface: c.textPrimary,
      onInverseSurface: c.background,
      inversePrimary: c.accent,
    );

    // 统一字体 + 字阶
    final textTheme = _buildTextTheme(c.textPrimary, c.textSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      textTheme: textTheme,
      extensions: [c],

      // ---- 导航栏：与页面同色 + 底部 hairline（精密暗色的分隔靠这条线） ----
      appBarTheme: AppBarTheme(
        backgroundColor: c.navBackground,
        foregroundColor: c.navForeground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: MaoSpace.lg,
        toolbarHeight: 56,
        titleTextStyle: MaoType.h2Style.copyWith(
          fontFamily: 'MiSans',
          fontSize: MaoType.h1,
          color: c.navForeground,
        ),
        iconTheme: IconThemeData(color: c.navForeground, size: 20),
        shape: Border(bottom: BorderSide(color: c.border, width: MaoLine.width)),
      ),

      // ---- 卡片：10 圆角 + 实色 hairline，无阴影（层级靠描边与明度差） ----
      cardTheme: CardTheme(
        elevation: 0,
        color: c.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: MaoRadius.cardBorder,
          side: BorderSide(color: c.border, width: MaoShadow.hairline),
        ),
      ),

      // ---- 按钮：统一 14 圆角，三级层次 ----
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.surfaceAlt,
          disabledForegroundColor: c.textTertiary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: MaoSpace.lg),
          shape: const RoundedRectangleBorder(
              borderRadius: MaoRadius.controlBorder),
          textStyle: MaoType.h3Style.copyWith(color: c.onAccent),
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: c.surfaceAlt,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: MaoSpace.lg),
          shape: const RoundedRectangleBorder(
              borderRadius: MaoRadius.controlBorder),
          textStyle: MaoType.h3Style.copyWith(color: c.onAccent),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: MaoSpace.lg),
          side: BorderSide(color: c.border, width: MaoLine.width),
          shape: const RoundedRectangleBorder(
              borderRadius: MaoRadius.controlBorder),
          textStyle: MaoType.h3Style.copyWith(color: c.accent),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          padding: const EdgeInsets.symmetric(
              horizontal: MaoSpace.sm, vertical: MaoSpace.xs),
          shape: const RoundedRectangleBorder(
              borderRadius: MaoRadius.smallBorder),
          textStyle: MaoType.h3Style.copyWith(color: c.accent),
        ),
      ),

      // ---- 输入框：8 圆角 + 细 focus 环（精密界面用细线而非粗环） ----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: MaoSpace.sm, vertical: MaoSpace.sm),
        hintStyle: MaoType.bodyStyle.copyWith(color: c.textTertiary),
        border: OutlineInputBorder(
          borderRadius: MaoRadius.controlBorder,
          borderSide: BorderSide(color: c.border, width: MaoLine.width),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MaoRadius.controlBorder,
          borderSide: BorderSide(color: c.border, width: MaoLine.width),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MaoRadius.controlBorder,
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: MaoRadius.controlBorder,
          borderSide: BorderSide(color: c.danger, width: MaoLine.width),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: MaoRadius.controlBorder,
          borderSide: BorderSide(color: c.danger, width: 1.5),
        ),
      ),

      // ---- 弹窗：12 圆角 + 发丝描边 ----
      dialogTheme: DialogTheme(
        backgroundColor: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: MaoRadius.largeBorder,
          side: BorderSide(color: c.border, width: MaoLine.width),
        ),
        titleTextStyle:
            MaoType.h2Style.copyWith(fontFamily: 'MiSans', color: c.textPrimary),
        contentTextStyle:
            MaoType.bodyStyle.copyWith(color: c.textSecondary, fontSize: 14),
      ),

      // ---- 底部弹层：顶部 12 圆角 + 发丝上边 ----
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(MaoRadius.large)),
          side: BorderSide(color: c.border, width: MaoLine.width),
        ),
        showDragHandle: true,
        dragHandleColor: c.border,
      ),

      // ---- SnackBar：浮动 + 圆角 ----
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? c.surfaceAlt : c.textPrimary,
        contentTextStyle: MaoType.bodyStyle.copyWith(
            color: dark ? c.textPrimary : c.surface, fontSize: 13),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: MaoRadius.controlBorder,
          side: BorderSide(color: c.border, width: MaoLine.width),
        ),
        insetPadding: const EdgeInsets.all(MaoSpace.md),
      ),

      // ---- 底部导航 ----
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.navBackground,
        elevation: 0,
        height: 58,
        indicatorColor: c.accentSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MaoRadius.small),
        ),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => states
                .contains(WidgetState.selected)
            ? MaoType.microStyle.copyWith(
                color: c.accent, fontWeight: FontWeight.w600)
            : MaoType.microStyle.copyWith(color: c.textTertiary)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected)
                  ? c.accent
                  : c.textTertiary,
            )),
      ),

      // ---- 侧边导航（宽屏） ----
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.navBackground,
        indicatorColor: c.accentSoft,
        selectedIconTheme: IconThemeData(color: c.accent, size: 24),
        unselectedIconTheme: IconThemeData(color: c.textTertiary, size: 24),
        selectedLabelTextStyle: MaoType.microStyle.copyWith(
            color: c.accent, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle:
            MaoType.microStyle.copyWith(color: c.textTertiary),
      ),

      // ---- Chip：小圆角，与卡片语言统一 ----
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceAlt,
        selectedColor: c.accentSoft,
        side: BorderSide(color: c.border, width: 1),
        labelStyle: MaoType.captionStyle.copyWith(color: c.textSecondary),
        secondaryLabelStyle:
            MaoType.captionStyle.copyWith(color: c.accent, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MaoRadius.chip)),
        padding: const EdgeInsets.symmetric(
            horizontal: MaoSpace.xs, vertical: MaoSpace.xxs),
        elevation: 0,
        pressElevation: 0,
      ),

      // ---- 列表 / 分隔线 / 进度条 / 图标 ----
      listTileTheme: ListTileThemeData(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: MaoSpace.md),
        iconColor: c.textSecondary,
        titleTextStyle: MaoType.h3Style.copyWith(color: c.textPrimary),
        subtitleTextStyle:
            MaoType.captionStyle.copyWith(color: c.textSecondary),
      ),
      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: MaoLine.width,
        space: MaoLine.width,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceAlt,
        circularTrackColor: Colors.transparent,
        linearMinHeight: MaoLine.barHeight,
      ),
      iconTheme: IconThemeData(color: c.textSecondary, size: 20),

      // ---- 页面转场：淡入 + 轻微上移（替代默认硬切） ----
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      }),

      // ---- 水波反馈颜色 ----
      splashColor: c.accent.withOpacity(0.10),
      highlightColor: c.accent.withOpacity(0.06),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  /// 字阶注入 TextTheme，页面即便用 `Theme.of(context).textTheme` 也一致。
  static TextTheme _buildTextTheme(Color primary, Color secondary) => TextTheme(
        displayLarge: MaoType.displayStyle.copyWith(color: primary),
        displayMedium: MaoType.displayStyle.copyWith(color: primary),
        displaySmall: MaoType.h1Style.copyWith(color: primary),
        headlineLarge: MaoType.h1Style.copyWith(color: primary),
        headlineMedium: MaoType.h1Style.copyWith(color: primary),
        headlineSmall: MaoType.h2Style.copyWith(color: primary),
        titleLarge: MaoType.h1Style.copyWith(color: primary),
        titleMedium: MaoType.h2Style.copyWith(color: primary),
        titleSmall: MaoType.h3Style.copyWith(color: primary),
        bodyLarge: MaoType.bodyStyle.copyWith(color: primary, fontSize: 15),
        bodyMedium: MaoType.bodyStyle.copyWith(color: primary),
        bodySmall: MaoType.captionStyle.copyWith(color: secondary),
        labelLarge: MaoType.h3Style.copyWith(color: primary),
        labelMedium: MaoType.captionStyle.copyWith(color: secondary),
        labelSmall: MaoType.microStyle.copyWith(color: secondary),
      ).apply(fontFamily: 'MiSans');
}

/// 主题语义色扩展「Mao Des」
///
/// 12 个色位全部显式定义，页面通过 `AppThemeColors.of(context)` 取用；
/// 禁止在页面里硬编码色值。
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  /// 页面背景
  final Color background;

  /// 卡片 / 主要表面
  final Color surface;

  /// 次级表面（输入框底、标签底、分区底）
  final Color surfaceAlt;

  /// 描边（hairline）
  final Color border;

  /// 主文字
  final Color textPrimary;

  /// 次文字
  final Color textSecondary;

  /// 三级文字 / 占位
  final Color textTertiary;

  /// 强调色
  final Color accent;

  /// 强调色浅底（选中态、标签底）
  final Color accentSoft;

  /// 强调色上的文字
  final Color onAccent;

  /// 导航栏背景
  final Color navBackground;

  /// 导航栏前景（标题/图标）
  final Color navForeground;

  // ===== 语义色（判题对错等，跨主题保持一致认知） =====

  /// 成功/正确
  final Color success;

  /// 成功浅底
  final Color successSoft;

  /// 危险/错误
  final Color danger;

  /// 危险浅底
  final Color dangerSoft;

  /// 警告
  final Color warning;

  const AppThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.navBackground,
    required this.navForeground,
    // 浅色档默认值：白底对比度达标的深绿/深红
    this.success = const Color(0xFF15803D),
    this.successSoft = const Color(0xFFDCFCE7),
    this.danger = const Color(0xFFB91C1C),
    this.dangerSoft = const Color(0xFFFEE2E2),
    this.warning = const Color(0xFFD97706),
  });

  // ---- 兼容旧字段名（页面仍在用 navBar/card/cardBorder/successContainer…） ----

  /// @deprecated 用 [navBackground]
  Color get navBar => navBackground;

  /// @deprecated 用 [surface]
  Color get card => surface;

  /// @deprecated 用 [border]
  Color get cardBorder => border;

  /// @deprecated 用 [successSoft]
  Color get successContainer => successSoft;

  /// @deprecated 用 [dangerSoft]
  Color get dangerContainer => dangerSoft;

  @override
  AppThemeColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentSoft,
    Color? onAccent,
    Color? navBackground,
    Color? navForeground,
    Color? success,
    Color? successSoft,
    Color? danger,
    Color? dangerSoft,
    Color? warning,
  }) =>
      AppThemeColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        border: border ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        onAccent: onAccent ?? this.onAccent,
        navBackground: navBackground ?? this.navBackground,
        navForeground: navForeground ?? this.navForeground,
        success: success ?? this.success,
        successSoft: successSoft ?? this.successSoft,
        danger: danger ?? this.danger,
        dangerSoft: dangerSoft ?? this.dangerSoft,
        warning: warning ?? this.warning,
      );

  @override
  AppThemeColors lerp(AppThemeColors? other, double t) {
    if (other == null) return this;
    return AppThemeColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
      navForeground: Color.lerp(navForeground, other.navForeground, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }

  /// 便捷取用。若当前 ThemeData 未挂载扩展（如测试里用裸 ThemeData、
  /// 或第三方页面），回退为按当前 colorScheme 现算的一份配色，
  /// 保证取色永不返回 null（避免 Null check operator 崩溃）。
  static AppThemeColors of(BuildContext context) {
    final theme = Theme.of(context);
    final ext = theme.extension<AppThemeColors>();
    if (ext != null) return ext;
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return AppThemeColors(
      background: scheme.surface,
      surface: scheme.surfaceContainerLowest,
      surfaceAlt: scheme.surfaceContainerHighest,
      border: scheme.outlineVariant,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      textTertiary: scheme.onSurfaceVariant.withOpacity(0.7),
      accent: scheme.primary,
      accentSoft: scheme.primaryContainer,
      onAccent: scheme.onPrimary,
      navBackground: theme.appBarTheme.backgroundColor ?? scheme.surface,
      navForeground: scheme.onSurface,
      success: dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
      successSoft: dark ? const Color(0xFF14361F) : const Color(0xFFDCFCE7),
      danger: dark ? const Color(0xFFF87171) : const Color(0xFFB91C1C),
      dangerSoft: dark ? const Color(0xFF3B1D1D) : const Color(0xFFFEE2E2),
      warning: dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
    );
  }
}
