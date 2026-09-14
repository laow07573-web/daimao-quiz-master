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
        color: bg,
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
                  padding: padding.add(
                      const EdgeInsets.only(left: MaoSpace.sm)),
                  child: child,
                ),
              ],
            )
          : Padding(padding: padding, child: child),
    );

    if (onTap != null) {
      panel = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(r),
          splashColor: ac.accent.withOpacity(0.06),
          highlightColor: ac.accent.withOpacity(0.04),
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
              Text(title,
                  style: MaoType.h2Style.copyWith(color: ac.textPrimary)),
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
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: text, style: MaoType.number(size, weight: weight)),
        if (suffix != null)
          TextSpan(
            text: suffix,
            style: MaoType.number(size * 0.5,
                weight: FontWeight.w500)
                .copyWith(letterSpacing: 0),
          ),
      ]),
      style: TextStyle(color: c),
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
        fg = Colors.white;
    }

    final disabled = onPressed == null;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: dense ? 15 : 17, color: disabled ? ac.textTertiary : fg),
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
          splashColor: Colors.white.withOpacity(0.06),
          highlightColor: Colors.white.withOpacity(0.04),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: MaoRadius.controlBorder,
              border: side == BorderSide.none ? null : Border.fromBorderSide(side),
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
  const MJTag(this.text, {super.key, this.tone = MJTagTone.neutral, this.filled = true});

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
        bg = ac.warning.withOpacity(0.12);
    }
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MaoSpace.xs, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? bg : Colors.transparent,
        borderRadius: MaoRadius.chipBorder,
        border: filled
            ? null
            : Border.all(color: ac.border, width: MaoLine.width),
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
                    style: MaoType.captionStyle
                        .copyWith(color: ac.textSecondary)),
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
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 0.9).animate(
          CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: ac.surfaceAlt,
          borderRadius:
              BorderRadius.circular(widget.radius ?? MaoRadius.chip),
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
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(maxWidth: maxWidth),
      builder: (_) => MJSheet(title: title, trailing: trailing, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ac.surface,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(MaoRadius.large)),
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
                          style: MaoType.h2Style
                              .copyWith(color: ac.textPrimary)),
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
    return showDialog<T>(
      context: context,
      builder: (_) =>
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
  const MJResumeCard({super.key, required this.session, required this.answered, this.onTap});

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
      padding: const EdgeInsets.all(MaoSpace.sm + 2),
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
                        fontWeight: FontWeight.w600,
                        color: ac.textPrimary)),
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
