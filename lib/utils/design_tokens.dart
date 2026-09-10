import 'package:flutter/material.dart';

// 猫卷设计令牌「Mao Des」
//
// 全新设计语言的唯一取值来源：字阶 / 间距 / 圆角 / 阴影 / 动效时长。
// 页面禁止再写零散字面量（如 `fontSize: 12.5`、`EdgeInsets.all(13)`、
// 各不相同的 `BorderRadius.circular(N)`），一律引用此处的 `MaoType` /
// `MaoSpace` / `MaoRadius` / `MaoShadow` / `MaoMotion`。

// ============================================================
// 1. 字阶（7 级，基准 14，不含半像素）
// ============================================================
/// 字阶：字号从大到小，正文基准 14。
class MaoType {
  const MaoType._();

  /// 超大数字（正确率、题量等仪表盘数值）
  static const double display = 30;

  /// 页面级标题
  static const double h1 = 22;

  /// 区块标题
  static const double h2 = 17;

  /// 卡片标题 / 列表主文字
  static const double h3 = 15;

  /// 正文（主力字号）
  static const double body = 14;

  /// 次要说明
  static const double caption = 12;

  /// 标签 / 极小文字
  static const double micro = 11;

  /// 正文行高（1.6 倍，长时间阅读舒适）
  static const double bodyHeight = 1.6;

  /// 标题行高
  static const double titleHeight = 1.35;

  /// 大数字行高（紧凑）
  static const double displayHeight = 1.15;

  // ---- 常用组合（省去页面反复拼 TextStyle） ----

  /// 大数字
  static const TextStyle displayStyle = TextStyle(
      fontSize: display, fontWeight: FontWeight.w700, height: displayHeight);

  /// 页面标题
  static const TextStyle h1Style = TextStyle(
      fontSize: h1, fontWeight: FontWeight.w600, height: titleHeight);

  /// 区块标题
  static const TextStyle h2Style = TextStyle(
      fontSize: h2, fontWeight: FontWeight.w600, height: titleHeight);

  /// 卡片标题
  static const TextStyle h3Style = TextStyle(
      fontSize: h3, fontWeight: FontWeight.w600, height: titleHeight);

  /// 正文
  static const TextStyle bodyStyle =
      TextStyle(fontSize: body, fontWeight: FontWeight.w400, height: bodyHeight);

  /// 次要说明
  static const TextStyle captionStyle =
      TextStyle(fontSize: caption, fontWeight: FontWeight.w400, height: 1.5);

  /// 标签
  static const TextStyle microStyle = TextStyle(
      fontSize: micro, fontWeight: FontWeight.w500, height: 1.4);
}

// ============================================================
// 2. 间距（4pt 栅格）
// ============================================================

/// 间距栅格：一切外边距/内边距/间隔只允许取这 7 档。
class MaoSpace {
  const MaoSpace._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  /// 页面左右边距
  static const double page = md;

  /// 卡片内边距
  static const double card = md;

  /// 区块之间的纵向间距
  static const double section = md;

  /// 列表条目之间的间距
  static const double item = sm;

  // 常用 EdgeInsets 预设
  static const EdgeInsets pagePadding = EdgeInsets.all(page);
  static const EdgeInsets cardPadding = EdgeInsets.all(card);
  static const EdgeInsets cardPaddingLoose =
      EdgeInsets.symmetric(horizontal: md, vertical: lg);
}

// ============================================================
// 3. 圆角
// ============================================================

/// 圆角体系：标签 6 / 小控件 10 / 按钮与输入框 14 / 卡片 18 / 大容器 24。
class MaoRadius {
  const MaoRadius._();

  /// 标签、小徽标
  static const double chip = 6;

  /// 小控件（缩略图、进度条槽、色板）
  static const double small = 10;

  /// 按钮、输入框
  static const double control = 14;

  /// 卡片
  static const double card = 18;

  /// 大容器、弹窗、底部弹层
  static const double large = 24;

  /// 胶囊（999 视为全圆）
  static const double pill = 999;

  static const BorderRadius chipBorder = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius smallBorder = BorderRadius.all(Radius.circular(small));
  static const BorderRadius controlBorder =
      BorderRadius.all(Radius.circular(control));
  static const BorderRadius cardBorder = BorderRadius.all(Radius.circular(card));
  static const BorderRadius largeBorder =
      BorderRadius.all(Radius.circular(large));
}

// ============================================================
// 4. 层次（阴影三级 + 描边）
// ============================================================

/// 层次模型：解决"发平、发闷、发糊"——卡片补回极轻阴影，描边改实色。
class MaoShadow {
  const MaoShadow._();

  /// L1 卡片：几乎不可见的柔和投影
  static const List<BoxShadow> level1 = [
    BoxShadow(
        color: Color(0x0A000000), offset: Offset(0, 1), blurRadius: 3),
  ];

  /// L2 悬浮元素 / 底部栏
  static const List<BoxShadow> level2 = [
    BoxShadow(
        color: Color(0x12000000), offset: Offset(0, 4), blurRadius: 14),
  ];

  /// L3 弹窗 / 浮层
  static const List<BoxShadow> level3 = [
    BoxShadow(
        color: Color(0x24000000), offset: Offset(0, 16), blurRadius: 40),
  ];

  /// 描边宽度（hairline）
  static const double hairline = 1;
}

// ============================================================
// 5. 动效
// ============================================================

/// 动效时长与曲线：统一交互节奏。
class MaoMotion {
  const MaoMotion._();

  /// 状态过渡（颜色/尺寸微变）
  static const Duration fast = Duration(milliseconds: 160);

  /// 常规过渡（展开、切换）
  static const Duration normal = Duration(milliseconds: 240);

  /// 强调过渡（弹层、页面转场）
  static const Duration slow = Duration(milliseconds: 320);

  /// 标准曲线
  static const Curve standard = Curves.easeOutCubic;

  /// 弹性曲线（用于按压缩放回弹）
  static const Curve emphasized = Curves.easeOutBack;
}
