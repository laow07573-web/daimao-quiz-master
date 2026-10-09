import 'dart:async';

import 'package:flutter/material.dart';

import '../services/mao_quotes.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';

/// 点 Logo 时浮空一闪而过的语录小窗。
///
/// 2026-10-09 用户对展示形式的原话：「语录的展示形式不是这样，而是一个类似于
/// 浮空的包含这文字的小弹窗，而且会很快消散，在触发下一条语录的时候会马上消失。」
///
/// 所以这里**不是**底部弹层（MJSheet），而是插进 Overlay 的悬浮小窗：
/// - 淡入 → 短暂停留 → 淡出，全程约 2 秒就会自己消散，不打断任何操作；
/// - [show] 每次都先 [dismiss] 掉上一条，做到「触发下一条时旧的马上消失」；
/// - 不挡交互（Overlay 只覆盖气泡自身那块区域）。
class MaoQuoteBubble {
  MaoQuoteBubble._();

  /// 气泡总存活时长：淡入 140ms + 停留 1500ms + 淡出 220ms
  static const Duration fadeIn = Duration(milliseconds: 140);
  static const Duration hold = Duration(milliseconds: 1500);
  static const Duration fadeOut = Duration(milliseconds: 220);
  static Duration get total => fadeIn + hold + fadeOut;

  static OverlayEntry? _entry;

  /// 是否有一条正在显示。
  ///
  /// 用 `mounted` 而不是 `!= null`：如果承载气泡的 Overlay 被整棵拆掉
  /// （换 MaterialApp / 测试里 `runApp` 顶替整棵树），气泡 State 随树 dispose、
  /// 它的定时器被取消，`onFinished` 就再也不会来——只判 null 会让这里一直
  /// 谎报 true。`mounted` 为 false 时顺带把失效引用清掉。
  static bool get visible {
    final entry = _entry;
    if (entry == null) return false;
    if (!entry.mounted) {
      _entry = null;
      return false;
    }
    return true;
  }

  /// 弹一条语录；[text] 为空时从 [MaoQuotes] 随机取。
  static void show(BuildContext context, {String? text}) {
    // 用户要求：触发下一条时上一条马上消失（不做淡出，直接移除）
    dismiss();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final content = text ?? MaoQuotes.pick();
    if (content.trim().isEmpty) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _QuoteBubble(
        text: content,
        onFinished: () {
          // 只有仍然是当前这一条时才移除，避免误删后插入的那条
          if (identical(_entry, entry)) {
            entry.remove();
            _entry = null;
          }
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  /// 立即移除当前气泡（没有则什么都不做）
  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _QuoteBubble extends StatefulWidget {
  const _QuoteBubble({required this.text, required this.onFinished});

  final String text;
  final VoidCallback onFinished;

  @override
  State<_QuoteBubble> createState() => _QuoteBubbleState();
}

class _QuoteBubbleState extends State<_QuoteBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MaoQuoteBubble.fadeIn,
    reverseDuration: MaoQuoteBubble.fadeOut,
  );
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _holdTimer = Timer(MaoQuoteBubble.hold, () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    // 浮在屏幕中上部：既不挡底部导航，也不压住卡片标题
    return Align(
      alignment: const Alignment(0, -0.42),
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _controller,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(CurvedAnimation(
                parent: _controller, curve: MaoMotion.standard)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: MaoSpace.lg),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: const EdgeInsets.symmetric(
                      horizontal: MaoSpace.md, vertical: MaoSpace.sm),
                  decoration: BoxDecoration(
                    color: ac.surface,
                    borderRadius: MaoRadius.controlBorder,
                    border: Border.all(color: ac.border, width: MaoLine.width),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.text,
                    textAlign: TextAlign.center,
                    style: MaoType.bodyStyle
                        .copyWith(color: ac.textPrimary, height: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
