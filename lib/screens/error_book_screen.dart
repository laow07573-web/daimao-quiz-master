import '../utils/design_tokens.dart';
import '../services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/question.dart';
import '../services/app_state.dart';
import '../services/docx_export_service.dart';
import '../services/export_storage.dart';
import 'package:flutter/services.dart';
import '../services/fsrs_service.dart';
import '../utils/format_utils.dart';
import '../utils/responsive.dart';
import '../widgets/ai_response_widget.dart';
import 'quiz_screen.dart';

/// 错题本（v1.0.2 重写）
/// 三个筛选：全部（到期∪收藏去重）/ 错题（纯到期）/ 收藏
/// 知识点分组面板：计数与复习范围同口径；空知识点并入「未打标签」
/// 切换筛选清空已选题库；无匹配清残留题；寒暑假 + API 未配置统一拦截
/// v1.0.2 对齐里程碑：生成建议（本地精炼 + AI 深度诊断）/ 导出错题 JSON
class ErrorBookScreen extends StatefulWidget {
  /// [initialFilter]：'all' 全部（到期∪收藏）/ 'wrong' 错题 / 'bookmark' 收藏
  const ErrorBookScreen({super.key, this.initialFilter = 'all'});

  final String initialFilter;

  @override
  State<ErrorBookScreen> createState() => _ErrorBookScreenState();
}

class _ErrorBookScreenState extends State<ErrorBookScreen> {
  List<Map<String, dynamic>>? _stats;
  bool _loading = true;
  final Set<int> _selectedBanks = {};
  late String _filter = widget.initialFilter;
  List<Map<String, dynamic>> _kpStats = [];
  bool _adviceLoading = false;

  static const _filters = [
    ('all', '全部'),
    ('wrong', '错题'),
    ('bookmark', '收藏'),
  ];

  String get _emptyText => switch (_filter) {
        'wrong' => '当前没有到期的错题',
        'bookmark' => '当前没有收藏的题目',
        _ => '当前没有错题或收藏',
      };

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  String get _countKey => switch (_filter) {
        'wrong' => 'due_count',
        'bookmark' => 'bookmark_count',
        _ => 'all_count',
      };

  Future<void> _loadStats() async {
    // v1.0.2 修复：加载异常不卡在转圈态，提示错误并回到空态
    try {
      final appState = context.read<AppState>();
      final stats = await appState.getErrorBookStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
      await _loadKpStats(appState);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stats = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载错题本失败：$e')),
      );
    }
  }

  /// 知识点分组：范围必须与「复习 / 导出」一致（当前筛选 + 已选题库）。
  /// 面板计数、点击下钻、导出「最薄弱知识点」三处都按同一个 [bankIds] 收窄，
  /// 否则勾选题库后，面板列出的知识点在导出时会命中 0 行。
  Future<void> _loadKpStats(AppState appState) async {
    final bankIds = _selectedBanks.isEmpty ? null : Set<int>.from(_selectedBanks);
    try {
      final filter = _filter;
      final kps =
          await appState.getKnowledgePointStats(filter, bankIds: bankIds);
      // 防竞态：筛选或题库选择已变，这轮结果作废
      if (!mounted || _filter != filter || !_sameSelection(bankIds)) return;
      setState(() => _kpStats = kps);
    } catch (_) {
      // 知识点分组失败不影响主列表
    }
  }

  /// 与上一轮查询时的题库选择是否一致（用于丢弃过期结果）
  bool _sameSelection(Set<int>? bankIds) {
    if (bankIds == null) return _selectedBanks.isEmpty;
    return bankIds.length == _selectedBanks.length &&
        bankIds.every(_selectedBanks.contains);
  }

  Future<void> _switchFilter(String filter) async {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      // 切换筛选时清空已选题库（防泄漏）
      _selectedBanks.clear();
      _kpStats = [];
    });
    await _loadKpStats(context.read<AppState>());
  }

  int get _totalCount {
    final key = _countKey;
    return _stats?.fold<int>(
            0, (sum, s) => sum + ((s[key] as int?) ?? 0)) ??
        0;
  }

  int get _totalSelected {
    final key = _countKey;
    return _stats
            ?.where((s) => _selectedBanks.contains(s['bank_id'] as int))
            .fold<int>(0, (sum, s) => sum + ((s[key] as int?) ?? 0)) ??
        0;
  }

  bool get _allSelected {
    final ids = _stats?.map((s) => s['bank_id'] as int).toSet() ?? {};
    return ids.isNotEmpty && ids.every(_selectedBanks.contains);
  }

  void _toggleSelectAll() {
    final ids = _stats?.map((s) => s['bank_id'] as int).toSet() ?? {};
    setState(() {
      if (_allSelected) {
        _selectedBanks.clear();
      } else {
        _selectedBanks.addAll(ids);
      }
    });
    // 与单题库勾选一致：知识点面板要跟着新范围重算，否则「最薄弱知识点」导出
    // 用的还是上一轮范围（全选后范围变最大，导出的知识点可能一题都命中不了）。
    _loadKpStats(context.read<AppState>());
  }

  bool _guard(AppState appState) {
    if (appState.vacationModeEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('寒暑假模式中，复习功能已暂停')),
      );
      return true;
    }
    // v1.0.2 修复：错题复习不依赖 AI，不再要求 API Key
    return false;
  }

  /// v1.0.2 对齐原版：知识点标签点击 → 底部弹窗列出该知识点题目，可复习
  Future<void> _showKpQuestions(String kp) async {
    final ac = AppThemeColors.of(context);
    final appState = context.read<AppState>();
    final bankIds = _selectedBanks.isEmpty ? null : _selectedBanks;
    final questions =
        await appState.getFullQuestionsByKnowledgePoint(kp, _filter,
            bankIds: bankIds);
    // v1.0.2 FSRS 可见化：逐题复习卡（下次复习时间）
    final ids = questions.map((q) => q.id).whereType<int>().toList();
    final cards = await appState.getFsrsCardsByIds(ids);
    // 逐题作答统计（做过几次 / 正确率）：一次 GROUP BY 聚合，不逐题查库
    final stats = await appState.getQuestionStatsByIds(ids);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: ac.background,
      // 平板适配：弹窗限宽居中
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(MaoRadius.card))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: ac.textSecondary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(MaoRadius.chip)),
                ),
              ),
              const SizedBox(height: 16),
              Text('$kp · ${questions.length} 题',
                  style: TextStyle(
                      fontSize: MaoType.h3,
                      fontWeight: FontWeight.bold,
                      color: ac.textPrimary)),
              const SizedBox(height: 10),
              if (questions.isEmpty)
                Text('该知识点暂无符合条件的题目',
                    style: TextStyle(
                        fontSize: MaoType.body, color: ac.textSecondary))
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: questions.length > 8 ? 8 : questions.length,
                    itemBuilder: (context, i) {
                      final q = questions[i];
                      final card = q.id != null ? cards[q.id] : null;
                      final st = q.id != null ? stats[q.id] : null;
                      final due = card != null &&
                          FSRSService.isDue(card, DateTime.now());
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${i + 1}. ${q.title}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: MaoType.body,
                                        color: ac.textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  // 逐题统计：做过几次 · 正确率 · FSRS 复习轮数 · 下次复习
                                  Text(
                                    questionStatLine((
                                      question: q,
                                      answered: st?.$1 ?? 0,
                                      correct: st?.$2 ?? 0,
                                      card: card,
                                    )),
                                    // 允许两行：窄屏单行放不下「下次复习」——而它正是
                                    // FSRS 可见化要展示的内容，截掉就白做了
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: MaoType.caption,
                                      color: due ? ac.danger : ac.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 14),
              if (questions.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _startKpReview(kp);
                    },
                    child: const Text('复习该知识点'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// v1.0.2 对齐里程碑：AI 生成建议（薄弱知识点精炼 + 复习优先级）
  Future<void> _generateAdvice() async {
    final appState = context.read<AppState>();
    if (_guard(appState)) return;
    if (_kpStats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无错题数据，无法精炼。')),
      );
      return;
    }
    final ai = appState.aiService;
    if (ai == null) return;

    setState(() => _adviceLoading = true);
    // v1.0.2 修复：生成建议异常时复位 loading 并提示，不再永久禁用按钮
    try {
      // 统计文本：知识点 + 错题数 + 正确率（本地精炼已按错题统计排序）
      // 正确率必须与错题数同范围：收窄到已选题库后，正确率若还是全库口径，
      // 两个数字互相矛盾，AI 会据此给出错误结论
      final accByKp = await appState.getAccuracyByKnowledgePoint(
          bankIds: _selectedBanks.isEmpty ? null : _selectedBanks);
      // v1.0.2 对齐里程碑：各知识点数据：
      final statsText = '各知识点数据：\n' +
          _kpStats
              .map((s) {
                final kp = s['kp'] as String;
                final row = accByKp
                    .where((a) => (a['kp'] as String?) == kp)
                    .firstOrNull;
                final total = (row?['total'] as int?) ?? 0;
                final correct = (row?['correct'] as int?) ?? 0;
                final acc = total > 0
                    ? '${(correct / total * 100).toStringAsFixed(1)}%'
                    : '无记录';
                return '**$kp**：错题 ${s['cnt']} 道，正确率 $acc';
              })
              .join('\n');

      final result = await ai.generateKpAdvice(statsText);
      if (!mounted) return;
      setState(() => _adviceLoading = false);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('薄弱知识点建议'),
          content: SingleChildScrollView(
            // 必须走富文本渲染器：generateKpAdvice 的提示词就是让 AI
            // 「用 ## 分标题、**粗体** 突出知识点名和关键数据」，
            // 之前这里用 SelectableText 原样显示，用户看到的是
            // 「## 最优先复习知识点」「**病理学**」这种源码。
            // SelectionArea 保留可选中复制的能力。
            child: SelectionArea(
              child: AiResponseWidget(text: result, fontSize: MaoType.body),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('好的')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _adviceLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成建议失败：$e')),
      );
    }
  }

  /// 导出错题：先让用户选范围，再导出为 .json（可再导入）。
  ///
  /// 选项对应产品要求：最薄弱知识点 / 最近 / 近一周 / 近一个月 / 自定义选题；
  /// 「错得最多的」是默认排序（`wrong DESC`），在 SQL 里完成，不拉全量到 Dart 排。
  Future<void> _showExportOptions() async {
    final appState = context.read<AppState>();
    final ac = AppThemeColors.of(context);
    final bankIds = _selectedBanks.isEmpty ? null : _selectedBanks;
    // 先把知识点分组刷到当前范围：勾选题库触发的重算是异步的，这里直接读
    // _kpStats 可能仍是上一轮快照，那样「最薄弱知识点」导出的范围跟弹窗上写的
    // 名字就对不上了。
    await _loadKpStats(appState);
    if (!mounted) return;
    // 当前筛选下的题数（用于在选项上标注规模）。取不到就写「题数未知」，
    // 不让一次统计失败把整个导出入口卡死。
    int? total;
    try {
      total = await appState.getFullErrorCount(_filter, bankIds: bankIds);
    } catch (_) {
      total = null;
    }
    if (!mounted) return;

    final kps = _kpStats;
    final weakestKp = kps.isEmpty ? null : (kps.first['kp'] as String?);

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ac.background,
      // isScrollControlled：不让 sheet 高度被限制在屏高 9/16。选项按内容定高，
      // 放得下时不出现滚动视图（Android 没有滚动条，半截选项会像渲染故障），
      // 同时把「可拖拽关闭」的手势还给 sheet。SingleChildScrollView 只兜底大字号。
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(MaoRadius.card))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(MaoSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('导出错题',
                    style: MaoType.h2Style.copyWith(color: ac.textPrimary)),
                const SizedBox(height: MaoSpace.xxs),
                Text('导出为 .json，可再导入回猫卷；默认按「错得最多」排序，各选项另有说明',
                    style:
                        MaoType.captionStyle.copyWith(color: ac.textSecondary)),
                const SizedBox(height: MaoSpace.md),
                _ExportOption(
                  icon: Icons.filter_alt_outlined,
                  title: '当前筛选',
                  subtitle: total == null ? '题数未知' : '共 $total 题',
                  onTap: () => Navigator.pop(ctx, 'current'),
                ),
                if (weakestKp != null)
                  _ExportOption(
                    icon: Icons.local_fire_department_outlined,
                    title: '最薄弱知识点',
                    subtitle: '$weakestKp（错题最多）',
                    onTap: () => Navigator.pop(ctx, 'kp:$weakestKp'),
                  ),
                _ExportOption(
                  icon: Icons.history_outlined,
                  title: '最近做过的',
                  subtitle: '当前范围内全部错题，最近作答的在前',
                  onTap: () => Navigator.pop(ctx, 'recent'),
                ),
                _ExportOption(
                  icon: Icons.schedule_outlined,
                  title: '近 7 天做过的',
                  subtitle: '错得最多的在前',
                  onTap: () => Navigator.pop(ctx, 'w7d'),
                ),
                _ExportOption(
                  icon: Icons.date_range_outlined,
                  title: '近 30 天做过的',
                  subtitle: '错得最多的在前',
                  onTap: () => Navigator.pop(ctx, 'w30d'),
                ),
                _ExportOption(
                  icon: Icons.checklist_outlined,
                  title: '选择题目导出…',
                  subtitle: '自己挑要导出的题',
                  onTap: () => Navigator.pop(ctx, 'pick'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;

    // 先定「导哪些题」，再问「答案怎么排」：一次只让用户做一个决定，
    // 也避免把范围参数在两层弹窗之间反复传递出错。
    _ExportScope? scope;
    switch (action) {
      case 'current':
        scope = _ExportScope(bankIds: bankIds, label: '当前筛选');
      case 'recent':
        scope = _ExportScope(
            bankIds: bankIds, recentFirst: true, label: '最近做过的');
      case 'w7d':
        scope = _ExportScope(bankIds: bankIds, window: '7d', label: '近 7 天做过的');
      case 'w30d':
        scope =
            _ExportScope(bankIds: bankIds, window: '30d', label: '近 30 天做过的');
      case 'pick':
        final ids = await _pickQuestions(bankIds: bankIds);
        if (ids == null || !mounted) return;
        scope = _ExportScope(questionIds: ids, label: '自选 ${ids.length} 题');
      default:
        if (action.startsWith('kp:')) {
          final kp = action.substring(3);
          scope = _ExportScope(
              bankIds: bankIds, knowledgePoint: kp, label: '知识点：$kp');
        }
    }
    if (scope == null || !mounted) return;

    final style = await _showExportStyle(scope);
    if (style == null || !mounted) return;
    switch (style) {
      case 'json':
        await _exportJson(scope);
      case 'docx_under_question':
        await _exportDocx(scope, DocxAnswerPlacement.underQuestion);
      case 'docx_last_page':
        await _exportDocx(scope, DocxAnswerPlacement.lastPage);
    }
  }

  /// 第二步：答案怎么排。
  ///
  /// 这一屏带一个示意动画，把「答案跟着题目」和「答案集中在末页」两种排布
  /// 直接演出来——光看文字说明（尤其「最后一页」）很难立刻想象成稿什么样。
  Future<String?> _showExportStyle(_ExportScope scope) async {
    final ac = AppThemeColors.of(context);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ac.background,
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(MaoRadius.card))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(MaoSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('答案放在哪里？',
                    style: MaoType.h2Style.copyWith(color: ac.textPrimary)),
                const SizedBox(height: MaoSpace.xxs),
                Text('导出「${scope.label}」的 Word 打印稿（.docx），可以直接打印成纸质题',
                    style:
                        MaoType.captionStyle.copyWith(color: ac.textSecondary)),
                const SizedBox(height: MaoSpace.md),
                const _AnswerStylePreview(),
                const SizedBox(height: MaoSpace.md),
                _ExportOption(
                  icon: Icons.vertical_align_top_rounded,
                  title: 'DOCX · 答案在题目下方',
                  subtitle: '题目和答案连着印，适合复习背诵',
                  onTap: () => Navigator.pop(ctx, 'docx_under_question'),
                ),
                _ExportOption(
                  icon: Icons.vertical_align_bottom_rounded,
                  title: 'DOCX · 答案在最后一页',
                  subtitle: '先做题，翻到最后对答案',
                  onTap: () => Navigator.pop(ctx, 'docx_last_page'),
                ),
                const Divider(height: MaoSpace.xl),
                _ExportOption(
                  icon: Icons.data_object_rounded,
                  title: 'JSON（可再导入回猫卷）',
                  subtitle: '要把这批题导回猫卷时选这个，不适合打印',
                  onTap: () => Navigator.pop(ctx, 'json'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 自定义选题：列表多选，返回选中的题目 id（取消或空选返回 null）。
  Future<Set<int>?> _pickQuestions({Set<int>? bankIds}) async {
    final appState = context.read<AppState>();
    final ac = AppThemeColors.of(context);
    final cards = await appState.getErrorQuestionCards(_filter, bankIds: bankIds);
    if (!mounted) return null;
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前筛选下暂无错题')));
      return null;
    }
    final selected = <int>{};

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ac.background,
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(MaoRadius.card))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(MaoSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('选择要导出的错题',
                        style: MaoType.h2Style.copyWith(color: ac.textPrimary)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setSheet(() {
                        if (selected.length == cards.length) {
                          selected.clear();
                        } else {
                          selected.addAll(cards.map((c) => c.question.id!));
                        }
                      }),
                      child: Text(selected.length == cards.length ? '取消全选' : '全选',
                          style: MaoType.captionStyle.copyWith(color: ac.accent)),
                    ),
                  ],
                ),
                const SizedBox(height: MaoSpace.xs),
                // 懒加载 + 限高：错题可能上百道，不用 Column 一次全展开
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: cards.length,
                    itemBuilder: (_, i) {
                      final it = cards[i];
                      final id = it.question.id!;
                      final checked = selected.contains(id);
                      return CheckboxListTile(
                        dense: true,
                        value: checked,
                        onChanged: (v) => setSheet(() {
                          if (v == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(it.question.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                MaoType.bodyStyle.copyWith(color: ac.textPrimary)),
                        subtitle: Text(questionStatLine(it),
                            // 单行：窄屏（LG G7 可用宽约 275px）下这行不截断就会
                            // 折成两行，列表里行高参差
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MaoType.microStyle
                                .copyWith(color: ac.textSecondary)),
                      );
                    },
                  ),
                ),
                const SizedBox(height: MaoSpace.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, true),
                    // 空选时说明该做什么，而不是显示自相矛盾的「确定（0 题）」
                    child: Text(selected.isEmpty
                        ? '请先选择题目（共 ${cards.length} 题）'
                        : '下一步（${selected.length} 题）'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return null;
    return selected;
  }

  /// 导出为 .json（可再导入回猫卷）。
  Future<void> _exportJson(_ExportScope s) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    // 先声明再在 try 里赋值：catch 分支一定 return，Dart 的定值分析能通过
    (String?, int) result;
    try {
      result = await appState.exportErrorQuestionsJson(
        _filter,
        bankIds: s.bankIds,
        questionIds: s.questionIds,
        knowledgePoint: s.knowledgePoint,
        window: s.window,
        recentFirst: s.recentFirst,
        includeStats: true, // 带上「做过几次/正确率/FSRS」，便于外部查看
      );
    } catch (e) {
      // 导出链路里的数据库异常（例如旧机上绑定变量超限）以前会静默抛出，
      // 用户点了没有任何反应；这里至少让他看到失败原因。
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
      return;
    }
    final (path, count) = result;
    if (!mounted) return;
    if (path == null) {
      messenger.showSnackBar(const SnackBar(content: Text('当前范围下暂无错题')));
      return;
    }
    await _share(messenger, path, '已导出 $count 题', '猫卷错题导出');
  }

  /// 导出为 .docx 打印稿（纸质题目）。
  Future<void> _exportDocx(
      _ExportScope s, DocxAnswerPlacement placement) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    (String?, int) result;
    try {
      result = await appState.exportErrorQuestionsDocx(
        _filter,
        bankIds: s.bankIds,
        questionIds: s.questionIds,
        knowledgePoint: s.knowledgePoint,
        window: s.window,
        recentFirst: s.recentFirst,
        placement: placement,
        subtitle: s.label,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
      return;
    }
    final (path, count) = result;
    if (!mounted) return;
    if (path == null) {
      messenger.showSnackBar(const SnackBar(content: Text('当前范围下暂无错题')));
      return;
    }
    final where = placement == DocxAnswerPlacement.underQuestion
        ? '答案在题目下方'
        : '答案在最后一页';
    await _share(messenger, path, '已导出 $count 题（$where）', '猫卷错题练习');
  }

  /// 把产物交给系统分享，并告诉用户文件保存到了哪个文件夹。
  ///
  /// 提示放在分享**之后**：系统分享面板是全屏的，先弹的 SnackBar 会在用户从
  /// 面板返回之前就超时消失，等于白提示。有了文件夹，用户即使没分享、也没记住
  /// 文件名，也能自己按目录翻出来（打印、发同学、存档）。
  Future<void> _share(ScaffoldMessengerState messenger, String path,
      String okText, String subject) async {
    var shared = true;
    try {
      await Share.shareXFiles([XFile(path)], subject: subject);
    } catch (e) {
      // v1.0.2 设计审查修复：分享失败不再静默
      shared = false;
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content:
              Text('分享失败：$e\n文件已保存：${ExportStorage.fileNameOf(path)}'),
          duration: const Duration(seconds: 6),
        ));
      }
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(shared ? okText : '$okText（已保存，未分享）'),
          const SizedBox(height: 3),
          Text('保存位置：${ExportStorage.folderOf(path)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MaoType.microStyle
                  .copyWith(color: Colors.white.withOpacity(0.85))),
        ],
      ),
      action: SnackBarAction(
        label: '复制路径',
        onPressed: () {
          // 连文件名一起复制：目录里可能有多份导出，只有目录分不出哪份是这次的
          Clipboard.setData(ClipboardData(text: path));
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(const SnackBar(
            content: Text('已复制文件完整路径'),
            duration: Duration(seconds: 2),
          ));
        },
      ),
    ));
  }

  Future<void> _startReview() async {
    final appState = context.read<AppState>();
    if (_guard(appState)) return;

    final bankIds = _selectedBanks.isEmpty ? null : _selectedBanks;
    // v1.0.2 修复：复习前确认数量（对齐首页「定向爆破」的选择行为）
    final count = await appState.getFullErrorCount(_filter, bankIds: bankIds);
    if (!mounted) return;
    if (count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        // v1.0.2 对齐里程碑：暂无符合条件的题目
        const SnackBar(content: Text('暂无符合条件的题目')),
      );
      return;
    }
    final label = _filters.firstWhere((f) => f.$1 == _filter).$2;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('错题复习'),
        content: Text('本次复习「$label」共 $count 题，确定开始？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始复习')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await appState.startErrorReview(mode: _filter, bankIds: bankIds);
    if (appState.quizQuestions.isEmpty) {
      // 无匹配时清空残留旧题（防泄漏）
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        // v1.0.2 对齐里程碑：暂无符合条件的题目
        const SnackBar(content: Text('暂无符合条件的题目')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const QuizScreen()));
    // v1.0.2 修复：复习返回后刷新统计（FSRS 已更新）
    await _loadStats();
  }

  Future<void> _startKpReview(String kp) async {
    final appState = context.read<AppState>();
    if (_guard(appState)) return;
    final bankIds = _selectedBanks.isEmpty ? null : _selectedBanks;
    await appState.startErrorReview(
        mode: _filter, bankIds: bankIds, kp: kp);
    if (appState.quizQuestions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        // v1.0.2 对齐里程碑：该知识点暂无符合条件的题目
        const SnackBar(content: Text('该知识点暂无符合条件的题目')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const QuizScreen()));
    // v1.0.2 修复：复习返回后刷新统计
    await _loadStats();
  }

  /// 单张题库卡（窄屏列表与宽屏网格共用）
  Widget _bankCard(int i, AppThemeColors ac) {
    final s = _stats![i];
    final bankId = s['bank_id'] as int;
    final due = s['due_count'] as int? ?? 0;
    final bookmark = s['bookmark_count'] as int? ?? 0;
    final count = s[_countKey] as int? ?? 0;
    final selected = _selectedBanks.contains(bankId);
    return _BankErrorCard(
      bankName: s['bank_name'] as String,
      count: count,
      due: due,
      bookmark: bookmark,
      // v1.0.2 FSRS 可见化：题库最早到期时间
      nextDueAt: s['next_due_at'] as String?,
      selected: selected,
      ac: ac,
      onTap: () {
        setState(() {
          if (selected) {
            _selectedBanks.remove(bankId);
          } else {
            _selectedBanks.add(bankId);
          }
        });
        // 知识点面板与「最薄弱知识点」导出都随已选题库收窄
        _loadKpStats(context.read<AppState>());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);

    return Scaffold(
      backgroundColor: ac.background,
      appBar: AppBar(
        title: const Text('错题本'),
        actions: [
          // v1.0.2 对齐里程碑：导出错题为 .json
          IconButton(
            tooltip: '导出错题',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _showExportOptions,
          ),
        ],
      ),
      // 平板适配：内容限宽居中（手机无影响）
      body: ResponsivePage(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stats == null || _stats!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: ac.accent.withOpacity(0.6)),
                      const SizedBox(height: 16),
                      Text(_emptyText, style: const TextStyle(fontSize: MaoType.h3)),
                      const SizedBox(height: 8),
                      Text('继续刷题积累吧！',
                          style: TextStyle(
                              fontSize: MaoType.body, color: ac.textSecondary)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 整页一起滚：筛选栏 / 统计条 / 薄弱知识点面板 / 生成建议 / 题库卡
                    // 放在同一个滚动视图里。此前只有题库列表能滚，知识点一多（十几个
                    // 标签）面板就把列表挤到只剩一两张卡的位置——知识点看不全、
                    // 卡片也翻不动。底部主按钮固定，不随内容滚走。
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Column(
                              children: [
                                // 筛选栏
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                                  child: Row(
                                    children: [
                                      for (final (value, label) in _filters)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: ChoiceChip(
                                            label: Text(label,
                                                style: const TextStyle(fontSize: MaoType.caption)),
                                            selected: _filter == value,
                                            onSelected: (_) => _switchFilter(value),
                                          ),
                                        ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: _toggleSelectAll,
                                        child: Text(
                                          _allSelected ? '取消全选' : '全选',
                                          style: const TextStyle(fontSize: MaoType.caption),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // 统计条
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  child: Row(
                                    children: [
                                      Text(
                                        '共 ${_totalCount} 题待复习',
                                        style: TextStyle(
                                            fontSize: MaoType.body, color: ac.textPrimary),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '收藏 ${_stats!.fold<int>(0, (s, x) => s + ((x['bookmark_count'] as int?) ?? 0))} 题',
                                        style: TextStyle(
                                            fontSize: MaoType.body, color: ac.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                // 知识点分组面板（v1.0.2 对齐原版：薄弱知识点标签云，点击弹题目列表）
                                if (_kpStats.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: ac.surfaceAlt.withOpacity(0.4),
                                        borderRadius: BorderRadius.circular(MaoRadius.small),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.insights,
                                                  size: 15, color: ac.accent),
                                              const SizedBox(width: 6),
                                              Text('薄弱知识点',
                                                  style: TextStyle(
                                                      fontSize: MaoType.body,
                                                      fontWeight: FontWeight.w600,
                                                      color: ac.textPrimary)),
                                              const Spacer(),
                                              // v1.0.2 对齐里程碑：按知识点分组
                                              Text('按知识点分组',
                                                  style: TextStyle(
                                                      fontSize: MaoType.caption,
                                                      color: ac.textSecondary)),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          // v1.0.2 对齐里程碑：优先复习知识点
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text('优先复习知识点',
                                                style: TextStyle(
                                                    fontSize: MaoType.caption,
                                                    color: ac.textSecondary)),
                                          ),
                                          const SizedBox(height: 10),
                                          // 标签云（圆角 8px 卡片）
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              for (final kp in _kpStats.take(10))
                                                InkWell(
                                                  borderRadius: BorderRadius.circular(MaoRadius.small),
                                                  onTap: () =>
                                                      _showKpQuestions(kp['kp'] as String),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 12, vertical: 7),
                                                    decoration: BoxDecoration(
                                                      color: ac.accent.withOpacity(0.12),
                                                      borderRadius:
                                                          BorderRadius.circular(MaoRadius.small),
                                                      border: Border.all(
                                                          color: ac.accent
                                                              .withOpacity(0.25)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          '${kp['kp']}',
                                                          style: TextStyle(
                                                              fontSize: MaoType.body,
                                                              color: ac.textPrimary),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          '${kp['cnt']} 题',
                                                          style: TextStyle(
                                                              fontSize: MaoType.micro,
                                                              color: ac.accent),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                // 生成建议（v1.0.2 对齐里程碑）
                                if (_kpStats.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: ac.accentSoft.withOpacity(0.35),
                                        borderRadius: BorderRadius.circular(MaoRadius.small),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '本地精炼已按错题统计排序；配置 API Key 后可生成 AI 深度诊断。',
                                            style: TextStyle(
                                                fontSize: MaoType.caption,
                                                color: ac.textSecondary,
                                                height: 1.4),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '点击「生成建议」，AI 将基于上方统计精炼薄弱知识点与复习优先级。',
                                            style: TextStyle(
                                                fontSize: MaoType.caption,
                                                color: ac.textSecondary,
                                                height: 1.4),
                                          ),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: double.infinity,
                                            child: FilledButton.tonalIcon(
                                              icon: _adviceLoading
                                                  ? const SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child: CircularProgressIndicator(
                                                          strokeWidth: 2))
                                                  : const Icon(Icons.auto_awesome,
                                                      size: 16),
                                              label: Text(
                                                  _adviceLoading ? '正在生成建议...' : '生成建议',
                                                  style:
                                                      const TextStyle(fontSize: MaoType.body)),
                                              onPressed:
                                                  _adviceLoading ? null : _generateAdvice,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // 题库卡：宽屏两列网格，窄屏单列
                          SliverPadding(
                            padding: const EdgeInsets.all(14),
                            sliver: isWideLayout(context)
                                ? SliverGrid(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 0,
                                      // 固定行高而非 childAspectRatio：宽屏卡片里元信息
                                      // 行改为 Wrap 后可折成两行，比例锁高会转为纵向溢出。
                                      // 114 = 两行元信息 + 选中态描边所需高度（约 112.4）：
                                      // 100 时折行会溢出 11.6px，卡片底部被下一张压住。
                                      mainAxisExtent: 114,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, i) => _bankCard(i, ac),
                                      childCount: _stats!.length,
                                    ),
                                  )
                                : SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, i) => _bankCard(i, ac),
                                      childCount: _stats!.length,
                                    ),
                                  ),
                          ),
                          const SliverToBoxAdapter(
                              child: SizedBox(height: MaoSpace.md)),
                        ],
                      ),
                    ),
                    // 底部按钮
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _startReview,
                            child: Text(
                              _selectedBanks.isEmpty
                                  ? '全题库重刷（共 $_totalCount 题）'
                                  : '开始重刷（已选 $_totalSelected 题）',
                              style: const TextStyle(fontSize: MaoType.h3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}

class _BankErrorCard extends StatelessWidget {
  final String bankName;
  final int count;
  final int due;
  final int bookmark;
  // v1.0.2 FSRS 可见化：该题库到期卡中最早到期时间（ISO，无到期卡为 null）
  final String? nextDueAt;
  final bool selected;
  final AppThemeColors ac;
  final VoidCallback onTap;

  const _BankErrorCard({
    required this.bankName,
    required this.count,
    required this.due,
    required this.bookmark,
    this.nextDueAt,
    required this.selected,
    required this.ac,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {

    return InkWell(
      borderRadius: MaoRadius.controlBorder,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: MaoSpace.xs),
        padding: const EdgeInsets.all(MaoSpace.sm + 2),
        decoration: BoxDecoration(
          color: ac.surface,
          borderRadius: MaoRadius.controlBorder,
          border: Border.all(
            color: selected ? ac.accent : ac.border,
            width: selected ? 1.4 : MaoLine.width,
          ),
        ),
        child: Row(
          // 题库名与右侧题数顶部对齐（此前默认 center 让「N 题」浮在两行文字之间）
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: selected ? ac.accent : ac.border,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bankName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: MaoType.body,
                          fontWeight: FontWeight.w600,
                          color: ac.textPrimary)),
                  const SizedBox(height: 4),
                  // 用 Wrap 而非 Row：窄屏下「173 题到期 · 175 收藏 · 下次到期：已到期179天」
                  // 总宽约 314px 而可用只有约 229px，Row 的子项不可收缩会直接溢出、
                  // 被屏幕右缘裁断（真机表现为末尾「天」字被切）。
                  // Wrap 信息零丢失、放不下时自然折到第二行。
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (due > 0)
                        Text('$due 题到期',
                            style: TextStyle(
                                fontSize: MaoType.body, color: ac.danger)),
                      if (due > 0 && bookmark > 0)
                        Text('·',
                            style: TextStyle(
                                fontSize: MaoType.body, color: ac.textSecondary)),
                      Text('$bookmark 收藏',
                          style: TextStyle(
                              fontSize: MaoType.body, color: ac.textSecondary)),
                      // v1.0.2 FSRS 可见化：最早到期的卡（SQL 只取 <= now 的卡，
                      // 所以这一定是「已到期/今天」，写「下次到期」自相矛盾）
                      if (nextDueAt != null) ...[
                        Text('·',
                            style: TextStyle(
                                fontSize: MaoType.body, color: ac.textSecondary)),
                        Text(
                          '最早到期：${relativeDayLabel(DateTime.parse(nextDueAt!))}',
                          style: TextStyle(
                              fontSize: MaoType.body, color: ac.danger),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Text('$count 题',
                style: TextStyle(
                    fontSize: MaoType.body,
                    fontWeight: FontWeight.w600,
                    color: ac.accent)),
          ],
        ),
      ),
    );
  }
}

/// 导出选项行（底部弹窗用）：图标 + 标题 + 副标题。
class _ExportOption extends StatelessWidget {
  const _ExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: MaoRadius.controlBorder,
      child: Padding(
        // 垂直留白收在 xs：6 个选项 ≤ 640dp 短屏时不滚动，也就不会出现
        // Android 上「没有滚动条、最后一项被切一半」的观感问题。
        padding: const EdgeInsets.symmetric(vertical: MaoSpace.xs),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ac.accent),
            const SizedBox(width: MaoSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: MaoType.bodyStyle.copyWith(
                          fontWeight: FontWeight.w600, color: ac.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MaoType.microStyle.copyWith(color: ac.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: ac.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 逐题统计一行：`做过 N 次 · 正确率 P% · FSRS 复习 M 轮 · 下次复习：X`
///
/// 数据全部来自批量查询（`getErrorQuestionCards`：题目 + 作答统计 + FSRS 卡，
/// 共两条 SQL），不要在列表里逐题查库。
String questionStatLine(
    ({Question question, int answered, int correct, FSRSCardState? card}) it) {
  final parts = <String>['做过 ${it.answered} 次'];
  if (it.answered > 0) {
    parts.add('正确率 ${(it.correct / it.answered * 100).toStringAsFixed(0)}%');
  }
  final card = it.card;
  if (card != null) {
    // 「复习 0 轮」（卡刚建立、还没复习过）不写：省下的宽度留给真正要看的
    // 下次复习时间，窄屏上也就不会被省略号截掉
    if (card.reviewCount > 0) parts.add('FSRS 复习 ${card.reviewCount} 轮');
    parts.add('下次复习：${relativeDayLabel(card.nextReviewAt)}');
  }
  return parts.join(' · ');
}

/// 一次导出要覆盖的范围：范围弹窗选完就固定下来，后面的「答案放哪」和
/// 真正的导出都读它，避免同一个参数在两层弹窗之间来回传。
class _ExportScope {
  const _ExportScope({
    this.bankIds,
    this.questionIds,
    this.knowledgePoint,
    this.window,
    this.recentFirst = false,
    required this.label,
  });

  final Set<int>? bankIds;
  final Set<int>? questionIds;
  final String? knowledgePoint;
  final String? window;
  final bool recentFirst;

  /// 写进卷头与提示文案的范围名，如「近 7 天做过的」
  final String label;
}

/// 「答案在题目下方 ⇄ 答案在最后一页」的示意动画。
///
/// 纸上 3 道题：答案块在「跟着题目走」和「集中到页底」之间来回移动，
/// 页底那条虚线代表答案区，只在末页模式显现——两种选择的差别直接演出来，
/// 比一行文字说明直观。
class _AnswerStylePreview extends StatefulWidget {
  const _AnswerStylePreview();

  @override
  State<_AnswerStylePreview> createState() => _AnswerStylePreviewState();
}

class _AnswerStylePreviewState extends State<_AnswerStylePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _morph;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 5200));
    // 停 → 移到末页 → 停 → 移回题目下方 → 停：两端各留出看清的时间
    _morph = _ctrl.drive(TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 16),
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 22),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 18),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 22),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 22),
    ]));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统开了「减弱动态效果」就停在第一种排布，不做循环动画
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _ctrl.stop();
      _ctrl.value = 0;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Container(
      height: 176,
      width: double.infinity,
      decoration: BoxDecoration(
        color: ac.surfaceAlt,
        borderRadius: BorderRadius.circular(MaoRadius.small),
        border: Border.all(color: ac.border, width: MaoLine.width),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: AnimatedBuilder(
        animation: _morph,
        builder: (context, _) {
          final atEnd = _morph.value > 0.5;
          return Column(
            children: [
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _AnswerStylePainter(
                    t: _morph.value,
                    paper: ac.surface,
                    line: ac.border,
                    accent: ac.accent,
                    faint: ac.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: Text(
                  atEnd ? '答案在最后一页' : '答案在题目下方',
                  key: ValueKey(atEnd),
                  style: MaoType.microStyle.copyWith(
                      color: atEnd ? ac.accent : ac.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AnswerStylePainter extends CustomPainter {
  _AnswerStylePainter({
    required this.t,
    required this.paper,
    required this.line,
    required this.accent,
    required this.faint,
  });

  /// 0 = 答案跟着题目，1 = 答案集中到页底
  final double t;
  final Color paper;
  final Color line;
  final Color accent;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sheet = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h), const Radius.circular(8));
    canvas.drawRRect(sheet, Paint()..color = paper);
    canvas.drawRRect(
        sheet,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    // 卷头小条
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(14, 12, 52, 6), const Radius.circular(3)),
      Paint()..color = faint.withOpacity(0.45),
    );

    const qX = 14.0;
    const qW = 96.0;
    const qH = 7.0;
    const gap = 22.0;
    const qTop = 30.0;

    // 页底的答案区虚线：末页模式才显现
    if (t > 0.01) {
      final dashY = h - 34;
      final dash = Paint()
        ..color = accent.withOpacity(0.35 * t)
        ..strokeWidth = 1;
      for (var x = 14.0; x < w - 16; x += 8) {
        canvas.drawLine(Offset(x, dashY), Offset(x + 4, dashY), dash);
      }
    }

    final questionPaint = Paint()..color = faint.withOpacity(0.42);
    final answerPaint = Paint()..color = accent.withOpacity(0.9);
    for (var i = 0; i < 3; i++) {
      final qy = qTop + i * gap;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(qX, qy, qW * (i == 2 ? 0.68 : 1.0), qH),
            const Radius.circular(3)),
        questionPaint,
      );
      // 答案块：从「题目下方」插值到「页底堆叠」
      final startX = qX + 10;
      final endX = qX;
      final startY = qy + 12;
      final endY = h - 30 + i * 9.0;
      final startW = qW * 0.5;
      final endW = qW * 0.34;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(
              startX + (endX - startX) * t,
              startY + (endY - startY) * t,
              startW + (endW - startW) * t,
              6,
            ),
            const Radius.circular(3)),
        answerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnswerStylePainter old) =>
      old.t != t ||
      old.paper != paper ||
      old.line != line ||
      old.accent != accent ||
      old.faint != faint;
}

