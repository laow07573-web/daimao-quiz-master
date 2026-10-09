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
  static const TextStyle h3Style =
      TextStyle(fontSize: h3, fontWeight: FontWeight.w600, height: titleHeight);

  /// 正文
  static const TextStyle bodyStyle = TextStyle(
      fontSize: body, fontWeight: FontWeight.w400, height: bodyHeight);

  /// 次要说明
  static const TextStyle captionStyle =
      TextStyle(fontSize: caption, fontWeight: FontWeight.w400, height: 1.5);

  /// 标签
  static const TextStyle microStyle =
      TextStyle(fontSize: micro, fontWeight: FontWeight.w500, height: 1.4);

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

  static const BorderRadius chipBorder =
      BorderRadius.all(Radius.circular(chip));
  static const BorderRadius smallBorder =
      BorderRadius.all(Radius.circular(small));
  static const BorderRadius controlBorder =
      BorderRadius.all(Radius.circular(control));
  static const BorderRadius cardBorder =
      BorderRadius.all(Radius.circular(card));
  static const BorderRadius largeBorder =
      BorderRadius.all(Radius.circular(large));
}

// ============================================================
// 4. 层次（发丝描边为主，阴影极轻）
// ============================================================

/// 遮罩：引导 / 模态背后的压暗层。
///
/// 用中性黑而不是画布色——画布色在浅色主题里等于「白色蒙版」，
/// 压暗几乎看不见；而互动式引导恰恰要靠「洞内外的明暗差」把目标托出来。
class MaoScrim {
  MaoScrim._();

  /// 互动式引导遮罩（约 70% 黑，明暗主题通用：暗色下四周沉到近纯黑，
  /// 高亮洞成为屏幕上唯一亮着的地方）
  static const Color guide = Color(0xB3000000);
}

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

/// 动效时长与曲线：精密界面的动作应"快而不飘"，像仪表指针——
/// 只在状态真的变化时动，动就一次落定。三档时长各有适用面：
/// [fast] 状态色变 / [normal] 组件过渡 / [slow] 转场落位；
/// 出场一律用 [exit]（快于进场，层是"落定"不是"飘走"）。
/// 全站禁止散落时长字面量，一律引用本类。
class MaoMotion {
  const MaoMotion._();

  // ════════════════════════════════════════════════════════════
  // 时长：按「运动语义」分层，而不是按大小命名
  // ════════════════════════════════════════════════════════════
  //
  // 2026-10-09 重新设计。旧命名（fast/normal/slow）只表达"多长"，
  // 用起来全凭感觉：180ms 到底是微交互还是内容切换？没人说得清，
  // 于是同一个交互在不同页面用不同时长。
  //
  // 现在按**层级**命名：运动的"块"越大、离手指越远，时长越长。
  // 选时长时先问自己「这是哪一层」，而不是「我想要多快」。
  //
  //   L0 手指直接反馈  → tap          （几乎无延迟）
  //   L1 元素状态变化  → stateChange  （颜色/描边/开关）
  //   L2 页面内换内容  → contentSwap  （列表/排行/标签内容）
  //   L3 浮层与整块    → overlay      （弹层/对话框/大块淡入）
  //   P1 一级页面      → primaryPage  （底部导航 Tab）
  //   P2 二级及以下    → nestedPage   （从一级页面 push 进去）
  //   OUT 任何层退出    → exit         （必须快于它的进场）

  /// L0 直接反馈：按压、悬停、涟漪。手指下的回应必须几乎无延迟。
  static const Duration tap = Duration(milliseconds: 90);

  /// L1 状态变化：颜色、描边、开关、选中态。
  static const Duration stateChange = Duration(milliseconds: 120);

  /// L2 内容替换：同一页内换内容（列表换数据、排行换维度、标签页内容）。
  static const Duration contentSwap = Duration(milliseconds: 180);

  /// L3 容器进出：底部弹层、对话框、整块淡入。
  static const Duration overlay = Duration(milliseconds: 260);

  /// 出场：任何层的退出都快于自己的进场（层是「落定」不是「飘走」）。
  static const Duration exit = Duration(milliseconds: 140);

  /// 页面层级过渡时长（2026-10-09 用户定义 + 要求）。
  ///
  /// 用户定义：
  /// - **一级页面** = 进入应用后不需要操作、或只操作一步就能切换到的页面
  ///   （即底部导航的四个 Tab）；一级与一级之间的切换要求「在较短的等待时间中
  ///   用极为流畅的动画作为过渡」。
  /// - **二级及以下** = 在一级页面上再操作一步才能看到的页面，以此类推。
  ///   二级及以下的过渡「不需要在太短的时间内完成」，时长取一级的
  ///   **1.5~2.5 倍**。
  ///
  /// 取值：[primaryPage] = 150ms（短、干脆）；[nestedPage] = 300ms
  /// （= primaryPage × 2.0，落在 1.5~2.5 倍区间内）。改这两个值前先确认
  /// 倍数关系仍成立，否则就违反了用户定的层级节奏。
  static const Duration primaryPage = Duration(milliseconds: 150);
  static const Duration nestedPage = Duration(milliseconds: 300);

  /// 轻提示（SnackBar）的停留时长。
  ///
  /// 2026-10-09 用户要求：「圈出的提示需要在 2s 内消散」——框架默认 4 秒太长，
  /// 一条「先勾选要刷的题库」挡住视线又不解决问题。
  ///
  /// 取 1.5s 而不是 2s：`duration` 只是**停留**时间，从出现到彻底移出画面还要
  /// 加入场与退场动画（各约 250ms）。实测 duration=2s 时总存活 2650ms，超出
  /// 用户要求；1.5s 时约 2.0s 正好落在「2 秒内消散」。
  /// 另外切页面时会主动清掉（见 MainShell._select 与开始页的导航辅助）。
  static const Duration toast = Duration(milliseconds: 1500);

  /// 兼容别名（迁移期保留，新代码请用上面的语义名）
  static const Duration fast = stateChange;
  static const Duration normal = contentSwap;
  static const Duration slow = overlay;

  /// 按页面层级取转场时长：1 = 一级（Tab 之间），≥2 = 二级及以下。
  ///
  /// 三级及以下刻意**不再递增**：每深一层就更慢会让人越点越拖，
  /// 用户只约束了「二级及以下 = 一级的 1.5~2.5 倍」，这里统一取 nestedPage。
  static Duration pageForDepth(int depth) =>
      depth <= 1 ? primaryPage : nestedPage;

  /// 列表/卡片进场的错落节拍（配 [staggerMax] 限量使用）
  static const Duration stagger = Duration(milliseconds: 30);

  /// 错落进场的条目上限：超过直接显示，防长列表变开幕典礼
  static const int staggerMax = 8;

  // ════════════════════════════════════════════════════════════
  // 曲线：只有三条 + 一条出场，选曲线仍然先问「这是哪一层」
  // ════════════════════════════════════════════════════════════

  /// 标准曲线：进入/落定（L0~L2 默认）
  static const Curve standard = Curves.easeOutCubic;

  /// 强调曲线：M3 同款三拐点、零过冲（L3 浮层与页面转场）
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// 按压缩放反馈曲线（仅配 ≤3% 的缩放微反馈）
  static const Curve press = Curves.easeOutCubic;

  /// 出场曲线：加速离场。
  /// 与 [standard] 的「快速起步、缓慢落定」相反——退出应该越走越快，
  /// 否则观感上像是"舍不得走"。
  static const Curve exitCurve = Curves.easeInCubic;

  /// 系统是否开启了「减弱动态效果」
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// 尊重系统「减弱动态效果」：开启时返回零时长（照常 setState，只是不演）
  static Duration effective(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}
