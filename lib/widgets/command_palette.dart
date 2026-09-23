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
    // 面板锚在顶部：整屏自底滑入是语义错位（底滑入 = "从下方长出的层"），
    // 改为「淡入 + 以顶部为中心 0.97→1 微放大」落定；进 MaoMotion.normal / 出 MaoMotion.exit。
    final window = MaoMotion.effective(context, MaoMotion.normal);
    final exit = MaoMotion.effective(context, MaoMotion.exit);
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '命令面板',
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
            alignment: Alignment.topCenter,
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (_, __, ___) => const CommandPalette(),
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

  /// 键盘高亮项（↑↓ 移动、回车执行）：键盘优先的面板不该逼人碰鼠标
  int _highlight = 0;

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

  void _moveHighlight(int count, int delta) {
    if (count <= 0) return;
    setState(() => _highlight = (_highlight + delta).clamp(0, count - 1));
  }

  List<_Cmd> _commands(BuildContext context) {
    final appState = context.read<AppState>();
    return [
      _Cmd('开始刷题', '按当前选择题库与题量开一轮', Icons.bolt, (ctx) {
        // 寒暑假拦截（与「开始」页同款条件）：答题已暂停时不再往下走
        if (appState.vacationModeEnabled) {
          Navigator.pop(ctx);
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('寒暑假模式中，答题功能已暂停')),
          );
          return;
        }
        // 先取 messenger/navigator 再关面板：pop 后 builder 的 context 已卸载，
        // 异步回调里不能再用它找 ScaffoldMessenger/Navigator
        final messenger = ScaffoldMessenger.of(ctx);
        final nav = Navigator.of(ctx);
        nav.pop();
        appState.startQuiz().then((_) {
          if (appState.quizQuestions.isEmpty) {
            messenger.showSnackBar(
              SnackBar(
                content: const Text('所选题库中没有题目，请先导入题目'),
                action: SnackBarAction(
                  label: '去导入',
                  onPressed: () => nav.push(MaterialPageRoute(
                      builder: (_) => const ImportScreen())),
                ),
              ),
            );
            return;
          }
          nav.push(MaterialPageRoute(builder: (_) => const QuizScreen()));
        });
      }),
      _Cmd('管理题库', '查看、勾选、导出或删除题库', Icons.library_books_outlined,
          (ctx) {
        final nav = Navigator.of(ctx);
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => const BankManageScreen()));
      }),
      _Cmd('错题本', '智能排期，只显示应复习的错题', Icons.replay_rounded,
          (ctx) {
        final nav = Navigator.of(ctx);
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => const ErrorBookScreen()));
      }),
      _Cmd('导入题库', 'DOCX/PDF 走 AI 解析（需 Key），JSON 直接入库',
          Icons.upload_file_outlined, (ctx) {
        final nav = Navigator.of(ctx);
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => const ImportScreen()));
      }),
      _Cmd('设置', '接口、外观、同步与提醒、高级', Icons.settings_outlined,
          (ctx) {
        final nav = Navigator.of(ctx);
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => const SettingsHubScreen()));
      }),
      _Cmd('切换主题', '清蓝 / 松绿 / 墨黑 循环切换', Icons.palette_outlined,
          (ctx) {
        final ts = ctx.read<ThemeService>();
        final messenger = ScaffoldMessenger.of(ctx);
        const all = AppTheme.values;
        final next = all[(all.indexOf(ts.current) + 1) % all.length];
        ts.switchTo(next);
        Navigator.pop(ctx);
        messenger.showSnackBar(
            SnackBar(content: Text('已切换到 ${ThemeService.labelOf(next)}')));
      }),
      _Cmd('深色 / 浅色', '在跟随系统 / 浅色 / 深色间切换', Icons.dark_mode_outlined,
          (ctx) {
        final ts = ctx.read<ThemeService>();
        final messenger = ScaffoldMessenger.of(ctx);
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
        messenger.showSnackBar(SnackBar(content: Text('外观：$label')));
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
          child: CallbackShortcuts(
            bindings: {
              // ↑↓ 在命令间移动高亮；Esc 关面板（与页脚提示一致）
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _moveHighlight(shown.length, -1),
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _moveHighlight(shown.length, 1),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(context).pop(),
            },
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
                          onChanged: (v) => setState(() {
                            _query = v;
                            // 换一批候选后从头高亮，回车行为可预期
                            _highlight = 0;
                          }),
                          onSubmitted: (_) {
                            if (shown.isNotEmpty) {
                              shown[_highlight.clamp(0, shown.length - 1)]
                                  .run(context);
                            }
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
                              onHover: (_) => setState(() => _highlight = i),
                              child: DecoratedBox(
                                // 高亮项浅强调底：键盘与鼠标共用同一个"当前项"
                                decoration: BoxDecoration(
                                  color: i == _highlight
                                      ? ac.accentSoft
                                      : Colors.transparent,
                                ),
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
                      Text('↑↓ 选择 · 回车执行 · Esc 关闭',
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
