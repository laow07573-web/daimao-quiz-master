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
    if (appState.importTaskActive) return;
    unawaited(appState.startBackgroundSampleImport());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已开始导入示例题库，进度见本页')),
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
            icon: const Icon(Icons.search),
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
                  if (appState.importTaskActive) ...[
                    _ImportProgressCard(appState: appState),
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
                      padding: const EdgeInsets.all(MaoSpace.sm + 2),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: ac.accentSoft,
                              borderRadius: MaoRadius.smallBorder,
                              border: Border.all(
                                  color: ac.border, width: MaoLine.width),
                            ),
                            child: Icon(Icons.school_rounded,
                                color: ac.accent, size: 17),
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
                        final ok = await appState.resumeUnfinishedSession();
                        if (!ok || !mounted) return;
                        await Navigator.push(
                          context,
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
                            _showCountPicker(context, appState);
                          },
                  ),
                  _QuickActionTile(
                    icon: Icons.library_books_outlined,
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
                    icon: Icons.upload_file_outlined,
                    label: '导入题库',
                    subtitle: 'AI 解析 DOCX（需 Key），JSON 直接入库',
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

  // ══════════ 刷题数量 / 模式选择（原首页逻辑） ══════════

  void _showCountPicker(BuildContext context, AppState appState) {
    final ac = AppThemeColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: ac.surface,
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MaoSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('选择刷题数量',
                  style: MaoType.h2Style.copyWith(color: ac.textPrimary),
                  textAlign: TextAlign.center),
              const SizedBox(height: MaoSpace.md),
              Wrap(
                spacing: MaoSpace.sm,
                runSpacing: MaoSpace.sm,
                alignment: WrapAlignment.center,
                children: [
                  ...[10, 20, 30, 50, 80, 100].map((n) => _countChip(ac, '$n 题', n == appState.selectedQuestionCount, () {
                        appState.setQuestionCount(n);
                        Navigator.pop(ctx);
                        _showQuizModePicker(context, appState);
                      })),
                  _countChip(ac, '全部', appState.selectedQuestionCount >= kQuestionCountAll, () {
                    appState.setQuestionCount(kQuestionCountAll);
                    Navigator.pop(ctx);
                    _showQuizModePicker(context, appState);
                  }),
                  _countChip(ac, '自定义', false, () {
                    Navigator.pop(ctx);
                    _showCustomCountDialog(context, appState);
                  }),
                ],
              ),
              const SizedBox(height: MaoSpace.sm),
              Text(
                '当前: ${appState.selectedQuestionCount >= kQuestionCountAll ? '全部' : '${appState.selectedQuestionCount} 题'}',
                style: MaoType.captionStyle.copyWith(color: ac.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countChip(
      AppThemeColors ac, String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? ac.accent : ac.surfaceAlt,
      borderRadius: MaoRadius.controlBorder,
      child: InkWell(
        onTap: onTap,
        borderRadius: MaoRadius.controlBorder,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: MaoSpace.md, vertical: MaoSpace.xs),
          decoration: BoxDecoration(
            borderRadius: MaoRadius.controlBorder,
            border: Border.all(
                color: selected ? ac.accent : ac.border,
                width: MaoLine.width),
          ),
          child: Text(label,
              style: MaoType.captionStyle.copyWith(
                  color: selected ? ac.onAccent : ac.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
        ),
      ),
    );
  }

  void _showCustomCountDialog(BuildContext context, AppState appState) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义题目数'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '输入题数'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text);
              if (n == null || n <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入大于 0 的有效题数')),
                );
                return;
              }
              appState.setQuestionCount(n);
              Navigator.pop(ctx);
              _showQuizModePicker(context, appState);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((_) => ctrl.dispose());
  }

  void _showQuizModePicker(BuildContext context, AppState appState) {
    final ac = AppThemeColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: ac.surface,
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MaoSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('选择刷题模式',
                  style: MaoType.h2Style.copyWith(color: ac.textPrimary),
                  textAlign: TextAlign.center),
              const SizedBox(height: MaoSpace.xs),
              Text(
                '已选 ${appState.selectedBankIds.length} 个题库，${appState.selectedQuestionCount >= kQuestionCountAll ? '全部' : '${appState.selectedQuestionCount} 题'}/轮',
                style: MaoType.captionStyle.copyWith(color: ac.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: MaoSpace.lg),
              _ModeOption(
                icon: Icons.flash_on_rounded,
                label: '正常刷题',
                desc: '答完即判，立刻校对解析',
                color: ac.accent,
                onTap: () {
                  Navigator.pop(ctx);
                  _startQuiz(appState);
                },
              ),
              const SizedBox(height: MaoSpace.xs),
              _ModeOption(
                icon: Icons.edit_square,
                label: '练习',
                desc: '答题卡模式，限时/不限时，统一批改',
                color: ac.textSecondary,
                onTap: () {
                  Navigator.pop(ctx);
                  _startPractice(appState);
                },
              ),
              const SizedBox(height: MaoSpace.xs),
              _ModeOption(
                icon: Icons.visibility_rounded,
                label: '背题模式',
                desc: '直接展示答案，快速浏览记忆',
                color: ac.accent,
                onTap: () {
                  Navigator.pop(ctx);
                  _startMemorize(appState);
                },
              ),
              const SizedBox(height: MaoSpace.sm),
            ],
          ),
        ),
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
        const SnackBar(content: Text('请先在首页选择题库')),
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
        const SnackBar(content: Text('请先在首页选择题库')),
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
            builder: (_) => QuizScreen(quizMode: QuizMode.memorize)));
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

/// 刷题模式选项
class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.icon,
    required this.label,
    required this.desc,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String desc;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return MJSurface(
      tone: MJTone.alt,
      onTap: onTap,
      padding: const EdgeInsets.all(MaoSpace.sm + 2),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
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
                    style:
                        MaoType.captionStyle.copyWith(color: ac.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: ac.textTertiary, size: 16),
        ],
      ),
    );
  }
}

/// 后台导入进度卡
class _ImportProgressCard extends StatelessWidget {
  const _ImportProgressCard({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final progress = appState.importProgress.clamp(0.0, 1.0);
    return MJSurface(
      accentEdge: true,
      padding: const EdgeInsets.all(MaoSpace.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: ac.accent),
              ),
              const SizedBox(width: MaoSpace.xs),
              Expanded(
                child: Text('正在导入题库，可先去做别的',
                    style: MaoType.h3Style.copyWith(
                        fontWeight: FontWeight.w600, color: ac.textPrimary)),
              ),
              MaoNumber('${(progress * 100).toInt()}',
                  size: MaoType.h3, weight: FontWeight.w600),
              Text('%',
                  style: MaoType.microStyle.copyWith(color: ac.textSecondary)),
            ],
          ),
          const SizedBox(height: MaoSpace.xs),
          MJProgress(value: progress),
          const SizedBox(height: MaoSpace.xs),
          Text(appState.importStatus,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MaoType.captionStyle.copyWith(color: ac.textSecondary)),
        ],
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
      padding: const EdgeInsets.all(MaoSpace.sm + 2),
      child: Row(
        children: [
          Icon(Icons.fact_check_outlined, color: ac.accent, size: 18),
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
          Icon(Icons.chevron_right, color: ac.accent, size: 16),
        ],
      ),
    );
  }
}

