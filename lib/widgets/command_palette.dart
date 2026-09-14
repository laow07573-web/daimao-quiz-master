import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/theme_service.dart';
import '../utils/app_constants.dart';
import '../utils/design_tokens.dart';
import '../screens/bank_manage_screen.dart';
import '../screens/error_book_screen.dart';
import '../screens/import_screen.dart';
import '../screens/quiz_screen.dart';
import '../screens/settings_hub_screen.dart';

/// 全局命令面板（Mao Des 2.0 · Linear 式 ⌘K）
///
/// 键盘优先的入口聚合：不必先在四个 Tab 之间找，直接搜「想做的那件事」。
/// 触发方式：宽屏按 Ctrl/Cmd+K；窄屏点「开始」页顶部的搜索框。
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  /// 打开命令面板（统一入口，便于各页面复用）
  static Future<void> open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CommandPalette(),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

/// 一条命令
class _Cmd {
  const _Cmd(this.title, this.hint, this.icon, this.run);

  final String title;
  final String hint;
  final IconData icon;
  final void Function(BuildContext) run;
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<_Cmd> _commands(BuildContext context) {
    final appState = context.read<AppState>();
    return [
      _Cmd('开始刷题', '按当前选择题库与题量开一轮', Icons.bolt, (ctx) {
        Navigator.pop(ctx);
        appState.startQuiz().then((_) {
          if (!ctx.mounted) return;
          if (appState.quizQuestions.isEmpty) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('所选题库中没有题目，请先导入题目')),
            );
            return;
          }
          Navigator.push(ctx,
              MaterialPageRoute(builder: (_) => const QuizScreen()));
        });
      }),
      _Cmd('管理题库', '查看、勾选、导出或删除题库', Icons.library_books_outlined,
          (ctx) {
        Navigator.pop(ctx);
        Navigator.push(ctx,
            MaterialPageRoute(builder: (_) => const BankManageScreen()));
      }),
      _Cmd('错题本', '智能排期，只显示应复习的错题', Icons.replay_rounded,
          (ctx) {
        Navigator.pop(ctx);
        Navigator.push(ctx,
            MaterialPageRoute(builder: (_) => const ErrorBookScreen()));
      }),
      _Cmd('导入题库', 'DOCX 走 AI 解析（需 Key），JSON 直接入库',
          Icons.upload_file_outlined, (ctx) {
        Navigator.pop(ctx);
        Navigator.push(ctx,
            MaterialPageRoute(builder: (_) => const ImportScreen()));
      }),
      _Cmd('设置', '接口、外观、同步与提醒、高级', Icons.settings_outlined,
          (ctx) {
        Navigator.pop(ctx);
        Navigator.push(ctx,
            MaterialPageRoute(builder: (_) => const SettingsHubScreen()));
      }),
      _Cmd('切换主题', '清蓝 / 松绿 / 墨黑 循环切换', Icons.palette_outlined,
          (ctx) {
        final ts = ctx.read<ThemeService>();
        final all = AppTheme.values;
        final next = all[(all.indexOf(ts.current) + 1) % all.length];
        ts.switchTo(next);
        Navigator.pop(ctx);
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text('已切换到 ${ThemeService.labelOf(next)}')));
      }),
      _Cmd('深色 / 浅色', '在跟随系统 / 浅色 / 深色间切换', Icons.dark_mode_outlined,
          (ctx) {
        final ts = ctx.read<ThemeService>();
        final next = switch (ts.themeMode) {
          ThemeMode.system => ThemeMode.light,
          ThemeMode.light => ThemeMode.dark,
          ThemeMode.dark => ThemeMode.system,
        };
        ts.switchThemeMode(next);
        Navigator.pop(ctx);
        final label = switch (next) {
          ThemeMode.system => '跟随系统',
          ThemeMode.light => '浅色',
          ThemeMode.dark => '深色',
        };
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text('外观：$label')));
      }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final all = _commands(context);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? all
        : all
            .where((c) =>
                c.title.toLowerCase().contains(q) ||
                c.hint.toLowerCase().contains(q))
            .toList();

    return Padding(
      // 键盘弹出时上移，避免遮住列表
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.only(top: 88, left: 16, right: 16),
            decoration: BoxDecoration(
              color: ac.surface,
              borderRadius: MaoRadius.largeBorder,
              border: Border.all(color: ac.border, width: MaoLine.width),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 搜索框
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: MaoSpace.sm, vertical: MaoSpace.xs),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 16, color: ac.textTertiary),
                      const SizedBox(width: MaoSpace.xs),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          autofocus: true,
                          textInputAction: TextInputAction.go,
                          style: MaoType.bodyStyle
                              .copyWith(color: ac.textPrimary),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            hintText: '输入命令…',
                            hintStyle: MaoType.bodyStyle
                                .copyWith(color: ac.textTertiary),
                          ),
                          onChanged: (v) => setState(() => _query = v),
                          onSubmitted: (_) {
                            if (shown.isNotEmpty) shown.first.run(context);
                          },
                        ),
                      ),
                      // Esc 提示（实际由 RawKeyboard 处理）
                      Text('Esc',
                          style: MaoType.microStyle
                              .copyWith(color: ac.textTertiary)),
                    ],
                  ),
                ),
                Container(height: MaoLine.width, color: ac.border),
                // 命令列表
                Flexible(
                  child: shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(MaoSpace.lg),
                          child: Text('没有匹配的命令',
                              style: MaoType.captionStyle
                                  .copyWith(color: ac.textTertiary)),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: shown.length,
                          separatorBuilder: (_, __) =>
                              Container(height: MaoLine.width, color: ac.border),
                          itemBuilder: (_, i) {
                            final c = shown[i];
                            return InkWell(
                              onTap: () => c.run(context),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: MaoSpace.sm,
                                    vertical: MaoSpace.sm),
                                child: Row(
                                  children: [
                                    Icon(c.icon,
                                        size: 16, color: ac.textSecondary),
                                    const SizedBox(width: MaoSpace.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(c.title,
                                              style: MaoType.h3Style.copyWith(
                                                  color: ac.textPrimary)),
                                          const SizedBox(height: 1),
                                          Text(c.hint,
                                              style: MaoType.microStyle
                                                  .copyWith(
                                                      color: ac.textTertiary)),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward_rounded,
                                        size: 13, color: ac.textTertiary),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(height: MaoLine.width, color: ac.border),
                // 页脚：版本 + 提示
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: MaoSpace.sm, vertical: MaoSpace.xs),
                  child: Row(
                    children: [
                      Text('猫卷 $kAppVersion',
                          style: MaoType.microStyle
                              .copyWith(color: ac.textTertiary)),
                      const Spacer(),
                      Text('回车执行首项',
                          style: MaoType.microStyle
                              .copyWith(color: ac.textTertiary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 在壳层挂载：监听 Ctrl/Cmd+K 打开命令面板。
///
/// 用 Focus + CallbackShortcuts 实现，不需要额外依赖；
/// 窄屏没有物理键盘时，用户可从「开始」页顶部入口打开同一面板。
class CommandPaletteShortcuts extends StatelessWidget {
  const CommandPaletteShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            CommandPalette.open(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            CommandPalette.open(context),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
