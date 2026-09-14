import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

// 猫卷设计令牌「Mao Des 2.0 · 精密暗色」
//
// 设计取向：Linear / Vercel 式的精密与克制。
//   · 画布分层靠「明度差 + 1px 发丝描边」表达，不用大阴影
//   · 圆角收紧，控件方正利落
//   · 字阶紧凑、大字号带负字距；数字一律等宽（tabular figures）对齐
//   · 动效短促干脆（120/180/260ms）
//
// 唯一取值来源：页面与组件禁止再写散落的字面量（如 `fontSize: 12.5`、
// `EdgeInsets.all(13)`、各不相同的 `BorderRadius.circular(N)`），一律引用
// `MaoType` / `MaoSpace` / `MaoRadius` / `MaoShadow` / `MaoMotion` / `MaoLine`。

// ============================================================
// 1. 字阶（7 级，基准 14）
// ============================================================

/// 字阶：字号从大到小，正文基准 14。
///
/// 大字号（display/h1/h2）带轻微负字距——这是"精密"观感的关键：
/// 字号越大，字距越紧，视觉上更整、更像工程界面而非网页。
class MaoType {
  const MaoType._();

  /// 超大数字（仪表盘数值、正确率）
  static const double display = 32;

  /// 页面级标题
  static const double h1 = 20;

  /// 区块标题
  static const double h2 = 16;

  /// 卡片标题 / 列表主文字
  static const double h3 = 14;

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
  static const double displayHeight = 1.1;

  // ---- 字距（负值收紧）----

  /// 超大数字字距
  static const double displaySpacing = -0.9;

  /// 页面标题字距
  static const double h1Spacing = -0.4;

  /// 区块标题字距
  static const double h2Spacing = -0.2;

  /// 标签类文字的疏字距（全大写英文/小标题用）
  static const double labelSpacing = 0.6;

  // ---- 等宽数字：所有统计数值必须用它，保证数位对齐 ----

  /// 等宽数字特性（0/1/2 宽度一致，数值列不跳动）
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // ---- 常用组合（省去页面反复拼 TextStyle）----

  /// 大数字（等宽）
  static const TextStyle displayStyle = TextStyle(
      fontSize: display,
      fontWeight: FontWeight.w700,
      height: displayHeight,
      letterSpacing: displaySpacing,
      fontFeatures: tabular);

  /// 页面标题
  static const TextStyle h1Style = TextStyle(
      fontSize: h1,
      fontWeight: FontWeight.w600,
      height: titleHeight,
      letterSpacing: h1Spacing);

  /// 区块标题
  static const TextStyle h2Style = TextStyle(
      fontSize: h2,
      fontWeight: FontWeight.w600,
      height: titleHeight,
      letterSpacing: h2Spacing);

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

  /// 小标题式标签（疏字距，用于分组眉题「本周战绩」等）
  static const TextStyle eyebrowStyle = TextStyle(
      fontSize: micro,
      fontWeight: FontWeight.w600,
      height: 1.3,
      letterSpacing: labelSpacing);

  /// 统计数值（等宽，随字号传入）
  static TextStyle number(double size, {FontWeight weight = FontWeight.w600}) =>
      TextStyle(
          fontSize: size,
          fontWeight: weight,
          height: 1.15,
          letterSpacing: -0.3,
          fontFeatures: tabular);
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

  /// 发丝间隔（分隔线两侧的最小呼吸）
  static const double hair = 2;

  // 常用 EdgeInsets 预设
  static const EdgeInsets pagePadding = EdgeInsets.all(page);
  static const EdgeInsets cardPadding = EdgeInsets.all(card);
  static const EdgeInsets cardPaddingLoose =
      EdgeInsets.symmetric(horizontal: md, vertical: lg);
}

// ============================================================
// 3. 圆角（收紧，精密感）
// ============================================================

/// 圆角体系：标签 4 / 小控件 6 / 按钮与输入框 8 / 卡片 10 / 大容器 12。
///
/// 相比上一版（6/10/14/18/24）整体收紧——圆角越小越"工程感"，
/// 与 Linear/Vercel 的方正界面一致。
class MaoRadius {
  const MaoRadius._();

  /// 标签、小徽标
  static const double chip = 4;

  /// 小控件（缩略图、进度条槽、色板）
  static const double small = 6;

  /// 按钮、输入框
  static const double control = 8;

  /// 卡片
  static const double card = 10;

  /// 大容器、弹窗、底部弹层
  static const double large = 12;

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
// 4. 层次（发丝描边为主，阴影极轻）
// ============================================================

/// 层次模型：精密暗色的签名特征是**几乎没有阴影**——层级靠
/// 面板明度差（background < surface < surfaceAlt）+ 1px 描边表达。
/// 这里的三级阴影仅供浮层（弹窗/悬浮栏）使用，且压到极轻。
class MaoShadow {
  const MaoShadow._();

  /// L1 卡片：几乎不可见（多数卡片直接用描边，不用阴影）
  static const List<BoxShadow> level1 = [
    BoxShadow(color: Color(0x05000000), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// L2 悬浮元素 / 底部栏
  static const List<BoxShadow> level2 = [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  /// L3 弹窗 / 浮层（最重的一级，仍远轻于上一版）
  static const List<BoxShadow> level3 = [
    BoxShadow(color: Color(0x2E000000), offset: Offset(0, 10), blurRadius: 28),
  ];

  /// 描边宽度（hairline）
  static const double hairline = 1;
}

// ============================================================
// 5. 发丝线与分隔
// ============================================================

/// 线：精密界面里 1px 承担了大部分分隔工作。
class MaoLine {
  const MaoLine._();

  /// 标准发丝线宽度
  static const double width = 1;

  /// 进度条 / 指示条高度
  static const double barHeight = 3;

  /// 强调侧条宽度（区块标题左侧竖条）
  static const double accentBarWidth = 2;
}

// ============================================================
// 6. 动效（短促干脆）
// ============================================================

/// 动效时长与曲线：精密界面的动作应"快而不飘"。
/// 相比上一版（160/240/320ms）整体提速，响应更跟手。
class MaoMotion {
  const MaoMotion._();

  /// 状态过渡（颜色/尺寸微变、悬停）
  static const Duration fast = Duration(milliseconds: 120);

  /// 常规过渡（展开、切换）
  static const Duration normal = Duration(milliseconds: 180);

  /// 强调过渡（弹层、页面转场）
  static const Duration slow = Duration(milliseconds: 260);

  /// 标准曲线（精密界面统一用它，不用弹跳）
  static const Curve standard = Curves.easeOutCubic;

  /// 弹性曲线（仅用于按压缩放反馈）
  static const Curve emphasized = Curves.easeOutBack;
}
