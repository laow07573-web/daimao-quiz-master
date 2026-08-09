import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'quiz_screen.dart';

/// 错题本（v1.0.2 重写）
/// 三个筛选：全部（到期∪收藏去重）/ 错题（纯到期）/ 收藏
/// 知识点分组面板：计数与复习范围同口径
/// 切换筛选清空已选题库；无匹配清残留题；寒暑假 + API 未配置统一拦截
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

  static const _filters = [
    ('all', '全部'),
    ('wrong', '错题'),
    ('bookmark', '收藏'),
  ];

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
    final appState = context.read<AppState>();
    final stats = await appState.getErrorBookStats();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
    await _loadKpStats(appState);
  }

  Future<void> _loadKpStats(AppState appState) async {
    final filter = _filter;
    final kps = await appState.getKnowledgePointStats(filter);
    if (!mounted || _filter != filter) return; // 防竞态：筛选已切换则丢弃
    setState(() => _kpStats = kps);
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
    if (!appState.settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请先在设置中配置 DeepSeek API Key'),
            backgroundColor: Colors.orange),
      );
      return true;
    }
    return false;
  }

  Future<void> _startReview() async {
    final appState = context.read<AppState>();
    if (_guard(appState)) return;

    final bankIds = _selectedBanks.isEmpty ? null : _selectedBanks;
    await appState.startErrorReview(mode: _filter, bankIds: bankIds);
    if (appState.quizQuestions.isEmpty) {
      // 无匹配时清空残留旧题（防泄漏）
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前筛选下暂无错题')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const QuizScreen()));
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
        const SnackBar(content: Text('该知识点下暂无错题')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const QuizScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('错题本'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stats == null || _stats!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: cs.primary.withOpacity(0.6)),
                      const SizedBox(height: 16),
                      const Text('暂无错题', style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('继续刷题积累吧！',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
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
                                    style: const TextStyle(fontSize: 12)),
                                selected: _filter == value,
                                onSelected: (_) => _switchFilter(value),
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: _toggleSelectAll,
                            child: Text(
                              _allSelected ? '取消全选' : '全选',
                              style: const TextStyle(fontSize: 12),
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
                                fontSize: 13, color: cs.onSurface),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '收藏 ${_stats!.fold<int>(0, (s, x) => s + ((x['bookmark_count'] as int?) ?? 0))} 题',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    // 知识点分组面板（v1.0.2）
                    if (_kpStats.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              for (final kp in _kpStats.take(6))
                                InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () => _startKpReview(
                                      kp['kp'] as String),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 7),
                                    child: Row(
                                      children: [
                                        Icon(Icons.label_outline,
                                            size: 14, color: cs.primary),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '${kp['kp']}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: cs.onSurface),
                                          ),
                                        ),
                                        Text(
                                          '${kp['cnt']} 题',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: cs.onSurfaceVariant),
                                        ),
                                        Icon(Icons.chevron_right,
                                            size: 14,
                                            color: cs.onSurfaceVariant),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    // 题库列表
                    Expanded(
                      child: _stats!.isEmpty
                          ? const SizedBox.shrink()
                          : ListView.builder(
                              padding: const EdgeInsets.all(14),
                              itemCount: _stats!.length,
                              itemBuilder: (context, i) {
                                final s = _stats![i];
                                final bankId = s['bank_id'] as int;
                                final due = s['due_count'] as int? ?? 0;
                                final bookmark = s['bookmark_count'] as int? ?? 0;
                                final count = s[_countKey] as int? ?? 0;
                                final selected =
                                    _selectedBanks.contains(bankId);
                                return _BankErrorCard(
                                  bankName: s['bank_name'] as String,
                                  count: count,
                                  due: due,
                                  bookmark: bookmark,
                                  selected: selected,
                                  colorScheme: cs,
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
                              },
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
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _BankErrorCard extends StatelessWidget {
  final String bankName;
  final int count;
  final int due;
  final int bookmark;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _BankErrorCard({
    required this.bankName,
    required this.count,
    required this.due,
    required this.bookmark,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: selected ? cs.primary : cs.outlineVariant,
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (due > 0)
                        Text('$due 题到期',
                            style: TextStyle(
                                fontSize: 12, color: cs.error)),
                      if (due > 0 && bookmark > 0) ...[
                        const SizedBox(width: 8),
                        Text('·',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant)),
                        const SizedBox(width: 8),
                      ],
                      Text('$bookmark 收藏',
                          style: TextStyle(
                              fontSize: 12, color: cs.secondary)),
                    ],
                  ),
                ],
              ),
            ),
            Text('$count 题',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.primary)),
          ],
        ),
      ),
    );
  }
}
