/// 猫卷组件库（Mao Des 2.0 · 精密暗色）
///
/// 全站唯一视觉零件来源。所有页面只允许用这里的组件拼装，
/// 不得再自行拼 Container + BoxDecoration 造"卡片"。
///
/// 设计约束（贯穿本文件的四条规则）：
///   1. 层级靠 1px 发丝描边 + 面板明度差，**不用大阴影**
///   2. 圆角一律取自 [MaoRadius]，控件方正
///   3. 一切统计数值用等宽数字（[MaoNumber]），保证数位对齐
///   4. 交互反馈短促（[MaoMotion.fast]），不用弹跳
library;

import 'package:flutter/material.dart';

import '../../models/quiz_session.dart';
import '../../services/theme_service.dart';
import '../../utils/design_tokens.dart';

// ════════════════════════════════════════════════════════════
// 表面 / 卡片
// ════════════════════════════════════════════════════════════

/// 发丝描边面板——取代 Card，是全站承载内容的唯一容器。
///
/// [tone] 控制面板层级：
///   · base（默认）surface 底，用于常规卡片
///   · alt   surfaceAlt 底，用于嵌套在卡片内的次级面板
///   · plain 透明底仅描边，用于轻量分组
/// [accentEdge] 为 true 时在左侧画一条强调竖条（用于「当前/推荐」项）。
class MJSurface extends StatelessWidget {
  const MJSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MaoSpace.md),
    this.tone = MJTone.base,
    this.accentEdge = false,
    this.radius,
    this.onTap,
    this.hoverable = false,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final MJTone tone;
  final bool accentEdge;
  final double? radius;
  final VoidCallback? onTap;
  final bool hoverable;

  /// 供测试与调试标识面板
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final r = radius ?? MaoRadius.card;

    final Color bg;
    switch (tone) {
      case MJTone.base:
        bg = ac.surface;
      case MJTone.alt:
        bg = ac.surfaceAlt;
      case MJTone.plain:
        bg = Colors.transparent;
    }

    Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        // Interactive surfaces paint their fill on Material so ink stays visible.
        color: onTap == null ? bg : Colors.transparent,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: ac.border, width: MaoLine.width),
      ),
      child: accentEdge
          ? Stack(
              children: [
                // 左侧强调竖条：只在左侧两角跟随圆角
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: MaoLine.accentBarWidth,
                    decoration: BoxDecoration(
                      color: ac.accent,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(r),
                        bottomLeft: Radius.circular(r),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      padding.add(const EdgeInsets.only(left: MaoSpace.sm)),
                  child: child,
                ),
              ],
            )
          : Padding(padding: padding, child: child),
    );

    if (onTap != null) {
      panel = Material(
        color: bg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(r),
          splashColor: ac.accent.withOpacity(0.06),
          highlightColor: ac.accent.withOpacity(0.04),
          hoverColor: ac.accent.withOpacity(hoverable ? 0.08 : 0.04),
          focusColor: ac.accent.withOpacity(0.12),
          child: panel,
        ),
      );
    }

    if (semanticLabel != null) {
      panel = Semantics(label: semanticLabel, container: true, child: panel);
    }
    return panel;
  }
}

/// 面板层级
enum MJTone { base, alt, plain }

// ════════════════════════════════════════════════════════════
// 区块标题
// ════════════════════════════════════════════════════════════

/// 区块标题：左侧 2px 强调竖条 + 标题 + 可选尾部动作。
///
/// 全站所有"分组标题"统一用它，取代原先各页面自己拼的
/// Container(宽 4 高 18) + Text 组合。
class MJSectionHeader extends StatelessWidget {
  const MJSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.subtitle,
    this.bar = true,
  });

  final String title;
  final Widget? trailing;
  final String? subtitle;

  /// 是否显示左侧强调竖条
  final bool bar;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (bar) ...[
          Container(
            width: MaoLine.accentBarWidth,
            height: 14,
            decoration: BoxDecoration(
              color: ac.accent,
              borderRadius: BorderRadius.circular(MaoRadius.chip),
            ),
          ),
          const SizedBox(width: MaoSpace.xs),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title,
                    style: MaoType.h2Style.copyWith(color: ac.textPrimary)),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: MaoSpace.xxs),
                Text(subtitle!,
                    style:
                        MaoType.captionStyle.copyWith(color: ac.textSecondary)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// 数字 / 指标
// ════════════════════════════════════════════════════════════

/// 等宽数字文本——一切统计数值必须用它（数位对齐是精密感的来源）。
class MaoNumber extends StatelessWidget {
  const MaoNumber(
    this.text, {
    super.key,
    this.size = MaoType.h1,
    this.weight = FontWeight.w600,
    this.color,
    this.suffix,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final Color? color;

  /// 单位后缀（如「道」「%」），用小一号字重减轻
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final c = color ?? ac.textPrimary;
    // 后缀下限 micro=11：小字号 CJK 发虚是排版毛刺的来源
    final suffixSize = size * 0.5 < MaoType.micro ? MaoType.micro : size * 0.5;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text, style: MaoType.number(size, weight: weight)),
        if (suffix != null)
          TextSpan(
            text: suffix,
            style: MaoType.number(suffixSize, weight: FontWeight.w500)
                .copyWith(letterSpacing: 0),
          ),
      ]),
      style: TextStyle(color: c),
    );
  }
}

/// 滚动落位的等宽数字——仪表读数变化时短滚一次落定（无过冲、宽度不跳）。
/// 进场从 0 数上来（仪表上电语感），数值更新从当前值落位；
/// 系统「减弱动态效果」时直接落位不演。
class MaoAnimatedNumber extends StatelessWidget {
  const MaoAnimatedNumber(
    this.value, {
    super.key,
    this.size = MaoType.h1,
    this.weight = FontWeight.w600,
    this.color,
    this.suffix,
    this.decimals = 0,
  });

  final num value;
  final double size;
  final FontWeight weight;
  final Color? color;
  final String? suffix;

  /// 小数位（百分比一类带小数的读数用）
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      // 首页/概览读数稍慢一点，避免数字刚出现就瞬间跳完。
      duration: MaoMotion.effective(context, const Duration(milliseconds: 420)),
      curve: MaoMotion.standard,
      builder: (context, v, _) => MaoNumber(
        decimals > 0 ? v.toStringAsFixed(decimals) : '${v.round()}',
        size: size,
        weight: weight,
        color: color,
        suffix: suffix,
      ),
    );
  }
}

/// 指标块：一个数值 + 一个标签，用于仪表盘。
class MJStatBlock extends StatelessWidget {
  const MJStatBlock({
    super.key,
    required this.value,
    required this.label,
    this.suffix,
    this.valueColor,
    this.compact = false,
  });

  final String value;
  final String label;
  final String? suffix;
  final Color? valueColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MaoNumber(value,
            size: compact ? MaoType.h1 : MaoType.display,
            weight: FontWeight.w700,
            color: valueColor,
            suffix: suffix),
        SizedBox(height: compact ? MaoSpace.xxs : MaoSpace.xs),
        Text(label,
            style: MaoType.captionStyle.copyWith(color: ac.textSecondary)),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// 按钮
// ════════════════════════════════════════════════════════════

/// 按钮层级：primary 实心强调 / secondary 描边 / ghost 无边框 / danger 危险
enum MJButtonKind { primary, secondary, ghost, danger }

/// 统一按钮：44 高、8 圆角、可选前置图标。
class MJButton extends StatelessWidget {
  const MJButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = MJButtonKind.primary,
    this.icon,
    this.expand = false,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final MJButtonKind kind;
  final IconData? icon;
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final h = dense ? 36.0 : 44.0;

    Color bg, fg;
    BorderSide side = BorderSide.none;
    switch (kind) {
      case MJButtonKind.primary:
        bg = ac.accent;
        fg = ac.onAccent;
      case MJButtonKind.secondary:
        bg = ac.surface;
        fg = ac.textPrimary;
        side = BorderSide(color: ac.border, width: MaoLine.width);
      case MJButtonKind.ghost:
        bg = Colors.transparent;
        fg = ac.textPrimary;
      case MJButtonKind.danger:
        bg = ac.danger;
        // 实底（强调/危险）上的前景一律取 onAccent，不写死白色
        fg = ac.onAccent;
    }

    final disabled = onPressed == null;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon,
              size: dense ? 15 : 17, color: disabled ? ac.textTertiary : fg),
          const SizedBox(width: MaoSpace.xs),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MaoType.h3Style.copyWith(
              color: disabled ? ac.textTertiary : fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    return SizedBox(
      height: h,
      child: Material(
        color: disabled ? ac.surfaceAlt : bg,
        borderRadius: MaoRadius.controlBorder,
        child: InkWell(
          onTap: onPressed,
          borderRadius: MaoRadius.controlBorder,
          // 按压水波取前景色的透明层：实底按钮上是提亮，描边/幽灵按钮上不再隐形
          splashColor: fg.withOpacity(0.06),
          highlightColor: fg.withOpacity(0.04),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: MaoRadius.controlBorder,
              border:
                  side == BorderSide.none ? null : Border.fromBorderSide(side),
            ),
            padding: EdgeInsets.symmetric(
                horizontal: dense ? MaoSpace.sm : MaoSpace.md),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 图标按钮：32×32 方形热区 + 发丝悬停底。
class MJIconButton extends StatelessWidget {
  const MJIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 18,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final on = active;
    final color = on ? (activeColor ?? ac.accent) : ac.textSecondary;

    Widget btn = SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: on ? ac.accentSoft : Colors.transparent,
        borderRadius: MaoRadius.smallBorder,
        child: InkWell(
          onTap: onPressed,
          borderRadius: MaoRadius.smallBorder,
          splashColor: ac.accent.withOpacity(0.08),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
    if (tooltip != null) {
      btn = Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

// ════════════════════════════════════════════════════════════
// 标签 / 徽章 / 分段控件
// ════════════════════════════════════════════════════════════

/// 标签语义色
enum MJTagTone { neutral, accent, success, danger, warning }

/// 小标签：4 圆角、极小字号、描边或浅底。
class MJTag extends StatelessWidget {
  const MJTag(this.text,
      {super.key, this.tone = MJTagTone.neutral, this.filled = true});

  final String text;
  final MJTagTone tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    late Color fg, bg;
    switch (tone) {
      case MJTagTone.neutral:
        fg = ac.textSecondary;
        bg = ac.surfaceAlt;
      case MJTagTone.accent:
        fg = ac.accent;
        bg = ac.accentSoft;
      case MJTagTone.success:
        fg = ac.success;
        bg = ac.successSoft;
      case MJTagTone.danger:
        fg = ac.danger;
        bg = ac.dangerSoft;
      case MJTagTone.warning:
        fg = ac.warning;
        bg = ac.warningSoft;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MaoSpace.xs, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? bg : Colors.transparent,
        borderRadius: MaoRadius.chipBorder,
        border:
            filled ? null : Border.all(color: ac.border, width: MaoLine.width),
      ),
      child: Text(text,
          style: MaoType.microStyle.copyWith(color: fg, height: 1.1)),
    );
  }
}

/// 分段控件：取代周期切换 chips 与主题单选组。
///
/// 精密风格的分段控件是"凹槽 + 滑块"：容器画发丝描边，
/// 选中项用实色底，未选中透明。
class MJSegmentedControl<T> extends StatelessWidget {
  const MJSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  /// 段定义：(值, 显示文字)
  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ac.surfaceAlt,
        borderRadius: MaoRadius.controlBorder,
        border: Border.all(color: ac.border, width: MaoLine.width),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: segments.map((s) {
          final selected = s.$1 == value;
          return Flexible(
            child: Material(
              color: selected ? ac.accent : Colors.transparent,
              borderRadius: MaoRadius.smallBorder,
              child: InkWell(
                onTap: () => onChanged(s.$1),
                borderRadius: MaoRadius.smallBorder,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: dense ? MaoSpace.sm : MaoSpace.md,
                    vertical: dense ? MaoSpace.xs - 2 : MaoSpace.xs,
                  ),
                  child: Text(
                    s.$2,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MaoType.captionStyle.copyWith(
                      color: selected ? ac.onAccent : ac.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 列表行
// ════════════════════════════════════════════════════════════

/// 内容切换过渡：旧内容立即移除，新内容淡入并轻微上移。
///
/// 与 `AnimatedSwitcher` 的关键区别：**不做交叉淡入**——AnimatedSwitcher 会让
/// 新旧两份 child 同时存在一段时间，内容（尤其高度不同的列表）会叠在一起，
/// 真机反馈「切换存在重叠画面」就是这么来的。这里用随 [switchKey] 变化的
/// TweenAnimationBuilder：切换即整块换新，只演一次入场，不存在重叠帧。
///
/// 2026-10-09 重新设计时补强了两点：
/// - **高度变化也平滑**（[animateSize]）：此前大家宁可用会重叠的
///   AnimatedSwitcher，图的就是它的高度过渡；现在这里用 AnimatedSize
///   补上，不必再为了高度去牺牲"不重叠"。
/// - **时长走层级令牌**（[duration]，默认 [MaoMotion.contentSwap] = L2 内容替换），
///   并且尊重系统「减弱动态效果」。
class MJSwitchFade extends StatelessWidget {
  const MJSwitchFade({
    super.key,
    required this.switchKey,
    required this.child,
    this.slideDistance = 8,
    this.axis = Axis.vertical,
    this.scaleFrom,
    this.duration = MaoMotion.contentSwap,
    this.animateSize = true,
  });

  /// 变化即触发重演（例如当前维度 / 数据条数）。
  final Object switchKey;
  final Widget child;

  /// 入场位移距离（px）。语义是「从哪里落位过来」：
  /// 垂直 = 从下方落定；水平 = 从侧边推入（切题那种方向感）。
  final double slideDistance;

  /// 位移方向：内容替换默认垂直；有前后顺序的切换（切题/翻页）用水平。
  final Axis axis;

  /// 可选的缩放入场起点（如 0.98）：用于「判定结果块」这类需要一点重量感的切换。
  /// 为 null 时不缩放。
  final double? scaleFrom;

  /// 过渡时长：默认 L2 内容替换层；整块浮层级的切换传 [MaoMotion.overlay]。
  final Duration duration;

  /// 是否平滑高度变化（切换前后内容高度不同时用得上）。
  final bool animateSize;

  @override
  Widget build(BuildContext context) {
    final motion = MaoMotion.effective(context, duration);
    final scale = scaleFrom;
    Widget faded = TweenAnimationBuilder<double>(
      key: ValueKey(switchKey),
      tween: Tween<double>(begin: 0, end: 1),
      duration: motion,
      curve: MaoMotion.standard,
      builder: (context, t, child) {
        final offset = axis == Axis.vertical
            ? Offset(0, (1 - t) * slideDistance)
            : Offset((1 - t) * slideDistance, 0);
        Widget out = Transform.translate(offset: offset, child: child);
        if (scale != null) {
          out = Transform.scale(
            scale: scale + (1 - scale) * t.clamp(0.0, 1.0),
            child: out,
          );
        }
        return Opacity(opacity: t.clamp(0.0, 1.0), child: out);
      },
      child: child,
    );
    if (!animateSize) return faded;
    // ClipRect 裁住高度动画过程中的溢出（旧内容比新内容高时）
    return ClipRect(
      child: AnimatedSize(
        duration: motion,
        curve: MaoMotion.standard,
        alignment: Alignment.topCenter,
        child: faded,
      ),
    );
  }
}

/// 设置/导航类列表行：左图标 + 标题/副标题 + 右箭头或自定义尾部。
class MJListRow extends StatelessWidget {
  const MJListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final row = Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: MaoSpace.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: MaoType.h3Style.copyWith(color: ac.textPrimary)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style:
                        MaoType.captionStyle.copyWith(color: ac.textSecondary)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (chevron) ...[
          const SizedBox(width: MaoSpace.xs),
          Icon(Icons.chevron_right_rounded, size: 18, color: ac.textTertiary),
        ],
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: ac.accent.withOpacity(0.05),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MaoSpace.md,
            vertical: dense ? MaoSpace.xs : MaoSpace.sm,
          ),
          child: row,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 进度 / 空态 / 骨架 / 分隔
// ════════════════════════════════════════════════════════════

/// 细进度条（3px），带 0..1 值。
class MJProgress extends StatelessWidget {
  const MJProgress({super.key, required this.value, this.color});

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(MaoLine.barHeight),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: MaoLine.barHeight,
        backgroundColor: ac.surfaceAlt,
        valueColor: AlwaysStoppedAnimation(color ?? ac.accent),
      ),
    );
  }
}

/// 空态：图标 + 标题 + 说明 + 可选动作。
class MJEmptyState extends StatelessWidget {
  const MJEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  final String title;
  final String? description;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MaoSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ac.surfaceAlt,
                borderRadius: MaoRadius.controlBorder,
                border: Border.all(color: ac.border, width: MaoLine.width),
              ),
              child: Icon(icon, size: 20, color: ac.textTertiary),
            ),
            const SizedBox(height: MaoSpace.md),
            Text(title,
                textAlign: TextAlign.center,
                style: MaoType.h3Style.copyWith(color: ac.textPrimary)),
            if (description != null) ...[
              const SizedBox(height: MaoSpace.xs),
              Text(description!,
                  textAlign: TextAlign.center,
                  style:
                      MaoType.captionStyle.copyWith(color: ac.textSecondary)),
            ],
            if (action != null) ...[
              const SizedBox(height: MaoSpace.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 骨架条：加载占位。
class MJSkeleton extends StatefulWidget {
  const MJSkeleton({super.key, this.height = 12, this.width, this.radius});

  final double height;
  final double? width;
  final double? radius;

  @override
  State<MJSkeleton> createState() => _MJSkeletonState();
}

class _MJSkeletonState extends State<MJSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 0.9)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: ac.surfaceAlt,
          borderRadius: BorderRadius.circular(widget.radius ?? MaoRadius.chip),
        ),
      ),
    );
  }
}

/// 发丝分隔线。
class MJDivider extends StatelessWidget {
  const MJDivider({super.key, this.indent = 0, this.label});

  final double indent;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    if (label == null) {
      return Padding(
        padding: EdgeInsets.only(left: indent),
        child: Container(height: MaoLine.width, color: ac.border),
      );
    }
    return Row(
      children: [
        Expanded(child: Container(height: MaoLine.width, color: ac.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MaoSpace.sm),
          child: Text(label!,
              style: MaoType.microStyle.copyWith(color: ac.textTertiary)),
        ),
        Expanded(child: Container(height: MaoLine.width, color: ac.border)),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// 可选块 / 浮层 / 工具栏
// ════════════════════════════════════════════════════════════

/// 可点选的标签（筛选项、周期切换等）。
///
/// 与 [MJTag] 的区别：MJTag 是只读徽标，MJChip 有选中态与点击反馈。
class MJChip extends StatelessWidget {
  const MJChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Material(
      color: selected ? ac.accent : ac.surface,
      borderRadius: MaoRadius.chipBorder,
      child: InkWell(
        onTap: onTap,
        borderRadius: MaoRadius.chipBorder,
        splashColor: ac.accent.withOpacity(0.08),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? MaoSpace.xs : MaoSpace.sm,
            vertical: dense ? 3 : 5,
          ),
          decoration: BoxDecoration(
            borderRadius: MaoRadius.chipBorder,
            border: Border.all(
              color: selected ? ac.accent : ac.border,
              width: MaoLine.width,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MaoType.microStyle.copyWith(
              color: selected ? ac.onAccent : ac.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部弹层容器：顶部 12 圆角 + 发丝边 + 可选标题。
///
/// 全站统一入口，取代各处手写的 showModalBottomSheet + Container + Decoration。
class MJSheet extends StatelessWidget {
  const MJSheet({
    super.key,
    required this.child,
    this.title,
    this.trailing,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;

  /// 显示底部弹层（自动限宽居中，平板/宽屏不拉满）
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    String? title,
    Widget? trailing,
    double maxWidth = 480,
  }) {
    // 弹层进出场统一：默认 250/200ms 不走 MaoMotion——自带 controller
    // 压到「进 MaoMotion.slow / 出 MaoMotion.exit」，与全站节奏一致。
    final enter = MaoMotion.effective(context, MaoMotion.slow);
    final exit = MaoMotion.effective(context, MaoMotion.exit);
    final controller = AnimationController(
      // 静态入口没有 State 提供 vsync：借 Navigator（SDK 自建弹层 controller
      // 同款做法，见 BottomSheet.createAnimationController）
      vsync: Navigator.of(context, rootNavigator: true),
      duration: enter,
      reverseDuration: exit,
    );
    // 外部传入的 controller 路由不代管回收，且 popped Future 早于出场动画
    // 结束就返回——因此等出场落定（dismissed）后再 dispose。
    var disposed = false;
    void disposeOnce() {
      if (disposed) return;
      disposed = true;
      controller.dispose();
    }

    controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        // 状态回调正遍历监听表，dispose 挪到微任务执行
        Future<void>.microtask(disposeOnce);
      }
    });
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(maxWidth: maxWidth),
      transitionAnimationController: controller,
      // 2026-10-08 真机 BUG 修复：主题里 bottomSheetTheme.showDragHandle = true，
      // 而这里把弹层背景设成了透明（真正的底色由 MJSheet 自己的 Container 画）。
      // Flutter 的拖拽手柄是渲染在「我们的 Container 之上」的，于是手柄那一横条
      // 处在一片透明区域里 —— 真机表现为弹层顶部有一条能看见下层页面的透明带。
      // MJSheet 自带标题栏，不需要框架手柄；显式关掉，让 Container 铺满整层。
      showDragHandle: false,
      builder: (_) => MJSheet(title: title, trailing: trailing, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ac.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(MaoRadius.large)),
        border: Border.all(color: ac.border, width: MaoLine.width),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(MaoSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(title!,
                          style:
                              MaoType.h2Style.copyWith(color: ac.textPrimary)),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: MaoSpace.md),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 对话框容器：12 圆角 + 发丝边（与 [MJSheet] 同一视觉语言）。
class MJDialog extends StatelessWidget {
  const MJDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget content,
    List<Widget> actions = const [],
  }) {
    // 弹窗进出场统一：默认 200ms zoom 不走 MaoMotion——改「淡入 + 0.98→1
    // 微放大」落定，进 MaoMotion.normal / 出 MaoMotion.exit。
    final window = MaoMotion.effective(context, MaoMotion.normal);
    final exit = MaoMotion.effective(context, MaoMotion.exit);
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      transitionDuration: window,
      transitionBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: MaoMotion.standard,
          // showGeneralDialog 没有独立出场时长参数（窗口 = 进场时长），
          // 用 MaoExitCurve 把出场压缩进 MaoMotion.exit 段内落定
          reverseCurve: window == Duration.zero
              ? MaoMotion.standard
              : MaoExitCurve(window: window, motion: exit),
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogCtx, animation, secondary) =>
          MJDialog(title: title, content: content, actions: actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Dialog(
      backgroundColor: ac.surface,
      elevation: 0,
      insetPadding: const EdgeInsets.all(MaoSpace.lg),
      shape: RoundedRectangleBorder(
        borderRadius: MaoRadius.largeBorder,
        side: BorderSide(color: ac.border, width: MaoLine.width),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(MaoSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: MaoType.h2Style.copyWith(color: ac.textPrimary)),
              const SizedBox(height: MaoSpace.sm),
              content,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: MaoSpace.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: MaoSpace.xs),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 横向工具栏（批注工具条等）：发丝边容器 + 可滚动内容。
class MJToolbar extends StatelessWidget {
  const MJToolbar({
    super.key,
    required this.children,
    this.padding,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ac.surface,
        border: Border.all(color: ac.border, width: MaoLine.width),
        borderRadius: MaoRadius.controlBorder,
      ),
      padding: padding ??
          const EdgeInsets.symmetric(
              horizontal: MaoSpace.xs, vertical: MaoSpace.xs - 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 断点续刷
// ════════════════════════════════════════════════════════════

/// 断点续刷卡：有未完成会话时出现在「首页」与「开始」页顶部。
///
/// 首页是用户回来第一眼看到的屏幕，「上次刷到一半」的入口必须在这里；
/// 「开始」页则是主动去做题时才进。两处必须长得一样，所以收进组件库，
/// 而不是各页自己拼一份（此前首页漏掉这个入口就是因为只写在了开始页）。
class MJResumeCard extends StatelessWidget {
  const MJResumeCard(
      {super.key, required this.session, required this.answered, this.onTap});

  /// 未完成会话。
  final QuizSession session;

  /// 该会话已作答题数。
  final int answered;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final modeLabel = switch (session.mode) {
      'error_review' => '错题复习',
      'kp_review' => '知识点复习',
      _ => '刷题',
    };
    return MJSurface(
      accentEdge: true,
      onTap: onTap,
      padding: const EdgeInsets.all(MaoSpace.sm),
      child: Row(
        children: [
          Icon(Icons.play_circle_outline, color: ac.accent, size: 22),
          const SizedBox(width: MaoSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('继续上次刷题',
                    style: MaoType.h3Style.copyWith(
                        fontWeight: FontWeight.w600, color: ac.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '已答 $answered/${session.totalQuestions} 题 · $modeLabel',
                  style: MaoType.captionStyle.copyWith(color: ac.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 16, color: ac.textTertiary),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 后台导入任务
// ════════════════════════════════════════════════════════════

/// 后台导入任务的 UI 层控制位。
///
/// 为什么在 UI 层：导入任务运行在 AppState（不归本次改动），无法真正中止；
/// 「取消」的语义是「不再展示进度、结果直接丢弃」——任务自身会很快结束并
/// 释放导入互斥，取消后短时间内再导入仍会提示「已有导入任务进行中」，
/// 这是真话（互斥确实还在）。首页/开始页/导入页/主壳共读写这一位，
/// 新任务开始时必须复位。
class MJImportTask {
  const MJImportTask._();

  /// 用户已放弃当前导入任务：进度卡隐藏、完成提示与解析结果直接丢弃。
  static bool discarded = false;
}

/// 后台导入任务卡：首页/开始页/导入页共用同一张脸
/// （进度 + 阶段文案 + 取消），不再各画一套。
class MJTaskCard extends StatelessWidget {
  const MJTaskCard({
    super.key,
    required this.progress,
    required this.status,
    this.onCancel,
  });

  /// 任务进度 0..1
  final double progress;

  /// `AppState.importStatus` 原文（阶段文案由它映射，不依赖应用层改动）
  final String status;

  /// 取消（放弃本次导入结果）；null 表示此入口不可取消
  final VoidCallback? onCancel;

  /// 文档解析的三阶段管线：PDF 先抽图文，再 AI 解析，最后待预览确认。
  /// 阶段文案直接呈现这条管线，用户能预判「进行到哪、下一步是什么」。
  static const List<String> _stages = [
    '1/3 提取图文',
    '2/3 AI 解析',
    '3/3 待预览',
  ];

  /// 从状态原文映射当前阶段；-1 = 非文档解析流程（JSON/示例直导入），
  /// 只显状态原文。
  static int _stageOf(String status) {
    if (status.contains('解析完成') || status.contains('预览')) return 2;
    if (status.contains('解析失败')) return -1;
    if (status.contains('提取')) return 0;
    if (status.contains('解析') || status.contains('AI')) return 1;
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final pct = progress.clamp(0.0, 1.0);
    final stage = _stageOf(status);
    return MJSurface(
      accentEdge: true,
      padding: const EdgeInsets.all(MaoSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: ac.accent),
              ),
              const SizedBox(width: MaoSpace.xs),
              Expanded(
                child: Text('正在导入题库，可先去做别的',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MaoType.h3Style.copyWith(
                        fontWeight: FontWeight.w600, color: ac.textPrimary)),
              ),
              MaoNumber('${(pct * 100).toInt()}',
                  size: MaoType.h3, weight: FontWeight.w600),
              Text('%',
                  style: MaoType.microStyle.copyWith(color: ac.textSecondary)),
            ],
          ),
          const SizedBox(height: MaoSpace.xs),
          MJProgress(value: pct),
          const SizedBox(height: MaoSpace.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stage >= 0) ...[
                      _TaskStageLine(current: stage),
                      const SizedBox(height: MaoSpace.xxs),
                    ],
                    Text(status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MaoType.captionStyle
                            .copyWith(color: ac.textSecondary)),
                  ],
                ),
              ),
              if (onCancel != null) ...[
                const SizedBox(width: MaoSpace.xs),
                MJButton(
                  label: '取消',
                  kind: MJButtonKind.ghost,
                  dense: true,
                  onPressed: onCancel,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 三阶段管线指示：当前阶段用强调色，其余弱化（只报进度，不报装饰）。
class _TaskStageLine extends StatelessWidget {
  const _TaskStageLine({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final spans = <TextSpan>[];
    for (var i = 0; i < MJTaskCard._stages.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(
            text: ' → ',
            style: MaoType.microStyle.copyWith(color: ac.textTertiary)));
      }
      spans.add(TextSpan(
        text: MJTaskCard._stages[i],
        style: MaoType.microStyle.copyWith(
          color: i == current ? ac.accent : ac.textTertiary,
          fontWeight: i == current ? FontWeight.w600 : FontWeight.w500,
        ),
      ));
    }
    return Text.rich(TextSpan(children: spans),
        maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}
