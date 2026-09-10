import '../utils/design_tokens.dart';
import '../services/theme_service.dart';
import 'package:flutter/material.dart';

import '../models/ink_annotation.dart';
import 'annotation_controller.dart';

/// 手写批注工具栏（v1.0.3 手写批注，REQ-014）
///
/// 批注模式中显示在 AppBar 之下、进度条之上，横向一行：
/// - [persistent] = false（即时批注）：颜色 | 笔型 | 橡皮擦 | 清空草稿 | 完成
/// - [persistent] = true（持久批注）：颜色 | 笔型 | 橡皮擦 | 选择 | 删除选中(选中时) | 一键清除旧批注 | 完成
///
/// 手机横向可滚动（REQ-015 小屏适配）。
class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({
    super.key,
    required this.controller,
    required this.persistent,
    required this.onFinish,
    this.shortcuts = false,
  });

  final AnnotationController controller;
  final bool persistent;
  final VoidCallback onFinish;

  /// v1.0.3 PC 快捷键：为 true 时按钮提示追快捷键标注（仅桌面平台传入）
  final bool shortcuts;

  Future<void> _confirmClear(BuildContext context, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: const Text('清除后不可恢复，确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
        ],
      ),
    );
    if (ok == true) controller.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          width: double.infinity,
          color: ac.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 颜色（REQ-007；快捷键 1/2/3/4）
                for (var i = 0; i < kAnnoColors.length; i++)
                  _ColorDot(
                    color: Color(kAnnoColors[i]),
                    selected: controller.color == kAnnoColors[i],
                    onTap: () => controller.setColor(kAnnoColors[i]),
                    tooltip: shortcuts
                        ? '${['红', '蓝', '绿', '黑'][i]} (${i + 1})'
                        : null,
                  ),
                const _Divider(),
                // 笔型（REQ-008；快捷键 Q/W/E）
                _ToolIcon(
                  icon: Icons.edit,
                  label: '细笔',
                  shortcut: shortcuts ? 'Q' : null,
                  selected: controller.tool == AnnoTool.pen &&
                      controller.penType == PenType.fine,
                  onTap: () {
                    controller.setPenType(PenType.fine);
                    controller.setTool(AnnoTool.pen);
                  },
                ),
                _ToolIcon(
                  icon: Icons.brush,
                  label: '笔',
                  shortcut: shortcuts ? 'W' : null,
                  selected: controller.tool == AnnoTool.pen &&
                      controller.penType == PenType.normal,
                  onTap: () {
                    controller.setPenType(PenType.normal);
                    controller.setTool(AnnoTool.pen);
                  },
                ),
                _ToolIcon(
                  icon: Icons.highlight,
                  label: '荧光笔',
                  shortcut: shortcuts ? 'E' : null,
                  selected: controller.tool == AnnoTool.pen &&
                      controller.penType == PenType.highlighter,
                  onTap: () {
                    controller.setPenType(PenType.highlighter);
                    controller.setTool(AnnoTool.pen);
                  },
                ),
                // 橡皮擦（REQ-009；快捷键 R）
                _ToolIcon(
                  icon: Icons.cleaning_services_outlined,
                  label: '橡皮擦',
                  shortcut: shortcuts ? 'R' : null,
                  selected: controller.tool == AnnoTool.eraser,
                  onTap: () => controller.setTool(AnnoTool.eraser),
                ),
                // 选择/移动（REQ-010，仅持久批注；快捷键 S）
                if (persistent) ...[
                  _ToolIcon(
                    icon: Icons.ads_click_outlined,
                    label: '选择',
                    shortcut: shortcuts ? 'S' : null,
                    selected: controller.tool == AnnoTool.select,
                    onTap: () => controller.setTool(AnnoTool.select),
                  ),
                  // 删除选中（选中时才出现；快捷键 Delete）
                  if (controller.selectedIndex != null)
                    _ToolIcon(
                      icon: Icons.delete_outline,
                      label: '删选中',
                      shortcut: shortcuts ? 'Delete' : null,
                      color: ac.danger,
                      selected: false,
                      onTap: () => controller.deleteSelected(),
                    ),
                  // 一键清除旧批注（REQ-011；快捷键 Ctrl+Delete）
                  _ToolIcon(
                    icon: Icons.delete_sweep_outlined,
                    label: '清全部',
                    shortcut: shortcuts ? 'Ctrl+Del' : null,
                    color: ac.danger,
                    selected: false,
                    onTap: () => _confirmClear(context, '一键清除旧手写批注'),
                  ),
                ] else ...[
                  // 即时批注：清空草稿（不落库，直接丢弃）
                  _ToolIcon(
                    icon: Icons.delete_sweep_outlined,
                    label: '清草稿',
                    shortcut: shortcuts ? 'Ctrl+Del' : null,
                    color: ac.danger,
                    selected: false,
                    onTap: () => _confirmClear(context, '清空本次草稿'),
                  ),
                ],
                const _Divider(),
                // 完成（快捷键 Esc）
                TextButton.icon(
                  onPressed: onFinish,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(shortcuts ? '完成 (Esc)' : '完成',
                      style: const TextStyle(fontSize: MaoType.body)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: ac.accent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dot = Padding(
      padding: const EdgeInsets.all(6),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
      ),
    );
    final ink = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: dot,
    );
    if (tooltip == null) return ink;
    return Tooltip(message: tooltip!, child: ink);
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.shortcut,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final effective = color ?? ac.textSecondary;
    return Tooltip(
      message: shortcut == null ? label : '$label ($shortcut)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MaoRadius.small),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? ac.accent.withOpacity(0.12) : null,
            borderRadius: BorderRadius.circular(MaoRadius.small),
          ),
          child: Icon(icon, size: 20, color: selected ? ac.accent : effective),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
