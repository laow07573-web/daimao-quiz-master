import '../utils/design_tokens.dart';
import '../services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_state.dart';
import '../services/fsrs_service.dart';
import '../utils/format_utils.dart';
import '../utils/responsive.dart';
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

  Future<void> _loadKpStats(AppState appState) async {
    try {
      final filter = _filter;
      final kps = await appState.getKnowledgePointStats(filter);
      if (!mounted || _filter != filter) return; // 防竞态：筛选已切换则丢弃
      setState(() => _kpStats = kps);
    } catch (_) {
      // 知识点分组失败不影响主列表
    }
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
    final cards = await appState.getFsrsCardsByIds(
        questions.map((q) => q.id).whereType<int>().toList());
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
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${i + 1}. ${q.title}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: MaoType.body, color: ac.textPrimary),
                              ),
                            ),
                            // v1.0.2 FSRS 可见化：下次复习时间（到期红色）
                            if (card != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '下次复习：${relativeDayLabel(card.nextReviewAt)}',
                                style: TextStyle(
                                  fontSize: MaoType.caption,
                                  color: FSRSService.isDue(
                                          card, DateTime.now())
                                      ? ac.danger
                                      : ac.textSecondary,
                                ),
                              ),
                            ],
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
      final accByKp = await appState.getAccuracyByKnowledgePoint();
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
            child: SelectableText(result,
                style: const TextStyle(fontSize: MaoType.body, height: 1.5)),
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

  /// v1.0.2 对齐里程碑：导出当前筛选错题为 .json 题库文件
  Future<void> _exportJson() async {
    final appState = context.read<AppState>();
    final path = await appState.exportErrorQuestionsJson(_filter,
        bankIds: _selectedBanks.isEmpty ? null : _selectedBanks);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (path == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('当前筛选下暂无错题')),
      );
      return;
    }
    final count = await appState.getFullErrorCount(_filter,
        bankIds: _selectedBanks.isEmpty ? null : _selectedBanks);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('（共 $count 题）已导出为 .json 文件。'),
        backgroundColor: AppThemeColors.of(context).warning,
        duration: const Duration(seconds: 3),
      ),
    );
    try {
      await Share.shareXFiles([XFile(path)], subject: '猫卷错题导出');
    } catch (e) {
      // v1.0.2 设计审查修复：分享失败不再静默
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    }
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
            onPressed: _exportJson,
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
                    // 题库列表；v1.0.3 宽屏重设计：宽屏 2 列网格，窄屏维持单列
                    Expanded(
                      child: _stats!.isEmpty
                          ? const SizedBox.shrink()
                          : Builder(builder: (context) {
                              Widget buildCard(int i) {
                                final s = _stats![i];
                                final bankId = s['bank_id'] as int;
                                final due = s['due_count'] as int? ?? 0;
                                final bookmark =
                                    s['bookmark_count'] as int? ?? 0;
                                final count = s[_countKey] as int? ?? 0;
                                final selected =
                                    _selectedBanks.contains(bankId);
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
                                  },
                                );
                              }

                              if (isWideLayout(context)) {
                                return GridView.builder(
                                  padding: const EdgeInsets.all(14),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 0,
                                    childAspectRatio: 5.5,
                                  ),
                                  itemCount: _stats!.length,
                                  itemBuilder: (context, i) => buildCard(i),
                                );
                              }
                              return ListView.builder(
                                padding: const EdgeInsets.all(14),
                                itemCount: _stats!.length,
                                itemBuilder: (context, i) => buildCard(i),
                              );
                            }),
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
      borderRadius: BorderRadius.circular(MaoRadius.control),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ac.surfaceAlt.withOpacity(0.5),
          borderRadius: BorderRadius.circular(MaoRadius.control),
          border: Border.all(
            color: selected ? ac.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
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
                  Row(
                    children: [
                      if (due > 0)
                        Text('$due 题到期',
                            style: TextStyle(
                                fontSize: MaoType.body, color: ac.danger)),
                      if (due > 0 && bookmark > 0) ...[
                        const SizedBox(width: 8),
                        Text('·',
                            style: TextStyle(
                                fontSize: MaoType.body, color: ac.textSecondary)),
                        const SizedBox(width: 8),
                      ],
                      Text('$bookmark 收藏',
                          style: TextStyle(
                              fontSize: MaoType.body, color: ac.textSecondary)),
                      // v1.0.2 FSRS 可见化：下次到期（该题库最早到期卡）
                      if (nextDueAt != null) ...[
                        const SizedBox(width: 8),
                        Text('·',
                            style: TextStyle(
                                fontSize: MaoType.body, color: ac.textSecondary)),
                        const SizedBox(width: 8),
                        Text(
                          '下次到期：${relativeDayLabel(DateTime.parse(nextDueAt!))}',
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
