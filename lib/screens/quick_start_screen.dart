import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/quiz_session.dart';
import '../services/app_state.dart';
import '../services/theme_service.dart';
import '../utils/app_constants.dart';
import '../utils/design_tokens.dart';
import '../utils/responsive.dart';
import '../widgets/command_palette.dart';
import '../widgets/kit/mj_kit.dart';
import 'bank_manage_screen.dart';
import 'error_book_screen.dart';
import 'import_preview_screen.dart';
import 'import_screen.dart';
import 'practice_screen.dart';
import 'quiz_screen.dart';

/// 快速开始（独立导航项 · Mao Des 2.0）
///
/// 从首页拆出来的「动作区」：首页只负责「看」（战绩与数据），
/// 这里只负责「做」（开始刷题 / 题库 / 错题 / 导入）。
/// 同时承接后台导入的任务状态（进行中进度、待确认预览）。
class QuickStartScreen extends StatefulWidget {
  const QuickStartScreen({super.key});

  @override
  State<QuickStartScreen> createState() => _QuickStartScreenState();
}

class _QuickStartScreenState extends State<QuickStartScreen> {
  /// 断点续刷：最新未完成会话 + 已答题数（续刷是「做」的动作，故在开始页）
  (QuizSession, int)? _unfinished;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final info =
          await context.read<AppState>().getUnfinishedSessionInfo();
      if (mounted) setState(() => _unfinished = info);
    });
  }

  bool _vacationBlocked(AppState appState) {
    if (!appState.vacationModeEnabled) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('寒暑假模式中，答题功能已暂停')),
    );
    return true;
  }

  /// 一键导入内置示例题库（免 Key、免文件，转后台执行）
  void _importSampleBank(AppState appState) {
    // 后台导入互斥在应用层是静默 return——UI 层提前明示，别让用户干等
    if (appState.importTaskActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已有导入任务进行中')),
      );
      return;
    }
    MJImportTask.discarded = false;
    unawaited(appState.startBackgroundSampleImport());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已开始导入示例题库，进度见开始页顶部卡片')),
    );
  }

  /// 取消导入：后台任务不可中止（边界见 [MJImportTask]），
  /// 「取消」= 不再展示进度、结果与解析结果直接丢弃。
  void _cancelImport(AppState appState) {
    MJImportTask.discarded = true;
    // 丢弃解析结果，并借 clearPreview 的通知让各页立即隐藏任务卡
    appState.clearPreview();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已取消导入，解析结果将丢弃')),
    );
  }

  Future<void> _navigateAndRefresh(
      BuildContext context, AppState appState, Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Scaffold(
      backgroundColor: ac.background,
      appBar: AppBar(
        title: const Text('快速开始'),
        actions: [
          // 触屏入口：窄屏没有物理键盘，这里打开同一个命令面板
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: '搜索命令',
            onPressed: () => CommandPalette.open(context),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(MaoSpace.md),
            child: ResponsivePage(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 后台导入：进行中进度卡
                  if (appState.importTaskActive &&
                      !MJImportTask.discarded) ...[
                    MJTaskCard(
                      progress: appState.importProgress,
                      status: appState.importStatus,
                      onCancel: () => _cancelImport(appState),
                    ),
                    const SizedBox(height: MaoSpace.sm),
                  ],
                  // 后台导入：AI 解析完成、待预览确认
                  if (!appState.importTaskActive &&
                      appState.previewQuestions.isNotEmpty) ...[
                    _PreviewConfirmCard(
                      appState: appState,
                      onOpen: () => _navigateAndRefresh(
                          context, appState, const ImportPreviewScreen()),
                    ),
                    const SizedBox(height: MaoSpace.sm),
                  ],

                  // 新生引导卡：零题库时置顶
                  if (appState.banks.isEmpty) ...[
                    MJSurface(
                      accentEdge: true,
                      padding: const EdgeInsets.all(MaoSpace.sm),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: ac.accentSoft,
                              borderRadius: MaoRadius.smallBorder,
                              border: Border.all(
                                  color: ac.border, width: MaoLine.width),
                            ),
                            child: Icon(Icons.school_rounded,
                                color: ac.accent, size: 18),
                          ),
                          const SizedBox(width: MaoSpace.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('新生第一步',
                                    style: MaoType.h3Style.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: ac.textPrimary)),
                                const SizedBox(height: 2),
                                Text('导入示例题库（10 道医学题），无需任何配置立即体验',
                                    style: MaoType.captionStyle.copyWith(
                                        color: ac.textSecondary,
                                        height: 1.35)),
                              ],
                            ),
                          ),
                          const SizedBox(width: MaoSpace.xs),
                          FilledButton(
                            onPressed: () => _importSampleBank(appState),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14),
                              minimumSize: const Size(0, 36),
                            ),
                            child: Text('导入',
                                style: MaoType.captionStyle.copyWith(
                                    color: ac.onAccent,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: MaoSpace.md),
                  ],

                  // 断点续刷：有未完成会话时置顶
                  if (_unfinished != null) ...[
                    MJResumeCard(
                      session: _unfinished!.$1,
                      answered: _unfinished!.$2,
                      onTap: () async {
                        // 先取 navigator 再跨异步：context 不能再用
                        final nav = Navigator.of(context);
                        final ok = await appState.resumeUnfinishedSession();
                        if (!ok || !mounted) return;
                        await nav.push(
                          MaterialPageRoute(
                              builder: (_) => const QuizScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: MaoSpace.md),
                  ],
                  const MJSectionHeader(title: '开始刷题'),
                  const SizedBox(height: MaoSpace.sm),
                  _QuickActionTile(
                    icon: Icons.rocket_launch_rounded,
                    label: '定向爆破',
                    subtitle: appState.selectedBankIds.isEmpty
                        ? '请先选择题库'
                        : '已选${appState.selectedBankIds.length}个题库，${appState.selectedQuestionCount >= kQuestionCountAll ? '全部' : '${appState.selectedQuestionCount}题'}',
                    iconColor: ac.accent,
                    onTap: appState.selectedBankIds.isEmpty
                        ? () {
                            final hasBanks = appState.banks.isNotEmpty;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(hasBanks ? '先勾选要刷的题库' : '还没有题库，先导入一份吧'),
                                action: SnackBarAction(
                                  label: hasBanks ? '去选择' : '去导入',
                                  onPressed: () => _navigateAndRefresh(
                                    context,
                                    appState,
                                    hasBanks
                                        ? const BankManageScreen()
                                        : const ImportScreen(),
                                  ),
                                ),
                              ),
                            );
                          }
                        : () {
                            if (_vacationBlocked(appState)) return;
                            _showStartQuizSheet(context, appState);
                          },
                  ),
                  _QuickActionTile(
                    icon: Icons.library_books_rounded,
                    label: '管理题库',
                    subtitle: appState.banks.isEmpty
                        ? '还没有题库，先去导入'
                        : '${appState.banks.length} 个题库',
                    iconColor: ac.accent,
                    onTap: () => _navigateAndRefresh(
                        context, appState, const BankManageScreen()),
                  ),
                  _QuickActionTile(
                    icon: Icons.replay_rounded,
                    label: '错题本',
                    subtitle: '智能排期，只显示应复习的错题',
                    iconColor: ac.danger,
                    onTap: () => _navigateAndRefresh(
                        context, appState, const ErrorBookScreen()),
                  ),
                  _QuickActionTile(
                    icon: Icons.upload_file_rounded,
                    label: '导入题库',
                    subtitle: 'AI 解析 DOCX/PDF（需 Key），JSON 直接入库',
                    iconColor: ac.accent,
                    onTap: () => _navigateAndRefresh(
                        context, appState, const ImportScreen()),
                  ),
                  const SizedBox(height: MaoSpace.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '本软件由b站：笨蛋鱼坏蛋猫 开发 | $kAppVersion',
                      style: MaoType.microStyle.copyWith(color: ac.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ══════════ 发起刷题（数量 + 模式一张面板一次确认） ══════════

  /// 原「数量 sheet → 自动关 → 模式 sheet」两连弹合一：连环弹层既打断节奏，
  /// 又在两步之间丢失「我要干什么」的上下文；这里数量 chips + 模式单选 +
  /// 底部「开始」主按钮，一次确认发起。
  void _showStartQuizSheet(BuildContext context, AppState appState) {
    MJSheet.show<void>(
      context,
      title: '发起刷题',
      maxWidth: kSheetMaxWidth,
      child: _StartQuizSheet(
        appState: appState,
        onStart: (mode, count) {
          appState.setQuestionCount(count);
          switch (mode) {
            case _StartMode.quiz:
              _startQuiz(appState);
            case _StartMode.practice:
              _startPractice(appState);
            case _StartMode.memorize:
              _startMemorize(appState);
          }
        },
      ),
    );
  }

  Future<void> _startQuiz(AppState appState) async {
    if (_vacationBlocked(appState)) return;
    await appState.startQuiz();
    if (!mounted) return;
    if (appState.quizQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选题库中没有题目，请先导入题目')),
      );
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const QuizScreen()));
  }

  Future<void> _startPractice(AppState appState) async {
    if (_vacationBlocked(appState)) return;
    if (appState.selectedBankIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先选择要练习的题库'),
          action: SnackBarAction(
            label: '去选择',
            onPressed: () => _navigateAndRefresh(
                context, appState, const BankManageScreen()),
          ),
        ),
      );
      return;
    }
    await appState.startQuiz(persistSession: false);
    if (!mounted) return;
    if (appState.quizQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选题库中没有题目，请先导入题目')),
      );
      return;
    }
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PracticeEntryScreen()));
  }

  Future<void> _startMemorize(AppState appState) async {
    if (_vacationBlocked(appState)) return;
    if (appState.selectedBankIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先选择要背的题库'),
          action: SnackBarAction(
            label: '去选择',
            onPressed: () => _navigateAndRefresh(
                context, appState, const BankManageScreen()),
          ),
        ),
      );
      return;
    }
    appState.noShuffle = true;
    try {
      await appState.startQuiz(persistSession: false);
    } finally {
      appState.noShuffle = false;
    }
    if (!mounted) return;
    if (appState.quizQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选题库中没有题目，请先导入题目')),
      );
      return;
    }
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => const QuizScreen(quizMode: QuizMode.memorize)));
  }
}

// ════════════════════════════════════════════════════════════
// 局部组件
// ════════════════════════════════════════════════════════════

/// 动作条目：单色描边小图标 + 标题/副标题 + 细箭头。
class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MaoSpace.xs),
      child: MJSurface(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
            horizontal: MaoSpace.sm, vertical: MaoSpace.sm),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: ac.surfaceAlt,
                borderRadius: MaoRadius.smallBorder,
                border: Border.all(color: ac.border, width: MaoLine.width),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: MaoSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: MaoType.h3Style.copyWith(
                          color: ac.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MaoType.captionStyle
                          .copyWith(color: ac.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: ac.textTertiary, size: 16),
          ],
        ),
      ),
    );
  }
}

/// 发起刷题的三种模式
enum _StartMode { quiz, practice, memorize }

/// 「发起刷题」面板内容：数量 chips + 模式单选 + 底部「开始」一次确认。
class _StartQuizSheet extends StatefulWidget {
  const _StartQuizSheet({required this.appState, required this.onStart});

  final AppState appState;
  final void Function(_StartMode mode, int count) onStart;

  @override
  State<_StartQuizSheet> createState() => _StartQuizSheetState();
}

class _StartQuizSheetState extends State<_StartQuizSheet> {
  late int _count = widget.appState.selectedQuestionCount;
  bool _custom = false;
  _StartMode _mode = _StartMode.quiz;
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  /// 解析最终题数；自定义输入非法时返回 null（面板不关，提示后继续改）
  int? get _resolvedCount {
    if (!_custom) {
      return _count >= kQuestionCountAll ? kQuestionCountAll : _count;
    }
    final n = int.tryParse(_customCtrl.text.trim());
    return (n == null || n <= 0) ? null : n;
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('每轮题数 · 已选 ${widget.appState.selectedBankIds.length} 个题库',
            style: MaoType.captionStyle.copyWith(color: ac.textSecondary)),
        const SizedBox(height: MaoSpace.sm),
        Wrap(
          spacing: MaoSpace.xs,
          runSpacing: MaoSpace.xs,
          children: [
            for (final n in const [10, 20, 30, 50, 80, 100])
              MJChip(
                label: '$n 题',
                dense: true,
                selected: !_custom && _count == n,
                onTap: () => setState(() {
                  _custom = false;
                  _count = n;
                }),
              ),
            MJChip(
              label: '全部',
              dense: true,
              selected: !_custom && _count >= kQuestionCountAll,
              onTap: () => setState(() {
                _custom = false;
                _count = kQuestionCountAll;
              }),
            ),
            MJChip(
              label: '自定义',
              dense: true,
              selected: _custom,
              onTap: () => setState(() => _custom = true),
            ),
          ],
        ),
        if (_custom) ...[
          const SizedBox(height: MaoSpace.sm),
          TextField(
            controller: _customCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '输入题数'),
            style: const TextStyle(fontSize: MaoType.body),
          ),
        ],
        const SizedBox(height: MaoSpace.md),
        Text('刷题模式',
            style: MaoType.captionStyle.copyWith(color: ac.textSecondary)),
        _modeRow(_StartMode.quiz, Icons.flash_on_rounded, '正常刷题', '答完即判，立刻校对解析'),
        _modeRow(_StartMode.practice, Icons.edit_note_rounded, '练习',
            '答题卡模式，限时/不限时，统一批改'),
        _modeRow(_StartMode.memorize, Icons.visibility_rounded, '背题模式',
            '直接展示答案，快速浏览记忆'),
        const SizedBox(height: MaoSpace.md),
        MJButton(
          label: '开始',
          expand: true,
          onPressed: () {
            final count = _resolvedCount;
            if (count == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请输入大于 0 的有效题数')),
              );
              return;
            }
            Navigator.of(context).pop();
            widget.onStart(_mode, count);
          },
        ),
      ],
    );
  }

  /// 模式单选行：Linear 式小方块选择器（与题库选择/答题选项同一套语言）
  Widget _modeRow(_StartMode mode, IconData icon, String label, String desc) {
    final ac = AppThemeColors.of(context);
    final selected = _mode == mode;
    return InkWell(
      onTap: () => setState(() => _mode = mode),
      borderRadius: MaoRadius.smallBorder,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: MaoSpace.xs),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: selected ? ac.accent : Colors.transparent,
                border: Border.all(
                  color: selected ? ac.accent : ac.border,
                  width: 1.2,
                ),
                borderRadius: MaoRadius.chipBorder,
              ),
              child: selected
                  ? Icon(Icons.check_rounded, size: 12, color: ac.onAccent)
                  : null,
            ),
            const SizedBox(width: MaoSpace.sm),
            Icon(icon, size: 18, color: selected ? ac.accent : ac.textSecondary),
            const SizedBox(width: MaoSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: MaoType.h3Style.copyWith(
                          fontWeight: FontWeight.w600, color: ac.textPrimary)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: MaoType.captionStyle
                          .copyWith(color: ac.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 待确认预览入口
class _PreviewConfirmCard extends StatelessWidget {
  const _PreviewConfirmCard({required this.appState, required this.onOpen});

  final AppState appState;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return MJSurface(
      onTap: onOpen,
      padding: const EdgeInsets.all(MaoSpace.sm),
      child: Row(
        children: [
          Icon(Icons.fact_check_rounded, color: ac.accent, size: 18),
          const SizedBox(width: MaoSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('已解析 ${appState.previewQuestions.length} 道题，待确认',
                    style: MaoType.h3Style.copyWith(
                        fontWeight: FontWeight.w600, color: ac.accent)),
                const SizedBox(height: 2),
                Text('点击查看预览，确认后入库',
                    style: MaoType.captionStyle
                        .copyWith(color: ac.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: ac.accent, size: 16),
        ],
      ),
    );
  }
}

