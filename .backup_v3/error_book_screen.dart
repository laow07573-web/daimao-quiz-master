import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'quiz_screen.dart';

class ErrorBookScreen extends StatefulWidget {
  const ErrorBookScreen({super.key});

  @override
  State<ErrorBookScreen> createState() => _ErrorBookScreenState();
}

class _ErrorBookScreenState extends State<ErrorBookScreen> {
  List<Map<String, dynamic>>? _stats;
  bool _loading = true;
  final Set<int> _selectedBanks = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final appState = context.read<AppState>();
    final stats = await appState.getErrorBookStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _loading = false;
      });
    }
  }

  int get _totalDue => _stats?.fold<int>(
      0, (sum, s) => sum + (s['due_count'] as int)) ?? 0;
  int get _totalBookmarks => _stats?.fold<int>(
      0, (sum, s) => sum + (s['bookmark_count'] as int)) ?? 0;
  int get _totalSelected {
    return _stats
            ?.where((s) => _selectedBanks.contains(s['bank_id'] as int))
            .fold<int>(0, (sum, s) => sum + (s['due_count'] as int) + (s['bookmark_count'] as int)) ??
        0;
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
                          size: 64, color: cs.outlineVariant),
                      const SizedBox(height: 16),
                      Text('暂无错题',
                          style: TextStyle(
                              fontSize: 16, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Text('继续刷题积累吧！',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 统计条
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      color: cs.surfaceContainerHighest,
                      child: Row(
                        children: [
                          Text(
                            '共 $_totalDue 题待复习  |  $_totalBookmarks 题收藏',
                            style: TextStyle(
                                fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                if (_selectedBanks.length == _stats!.length) {
                                  _selectedBanks.clear();
                                } else {
                                  _selectedBanks.addAll(
                                      _stats!.map((s) => s['bank_id'] as int));
                                }
                              });
                            },
                            child: Text(
                              _selectedBanks.length == _stats!.length
                                  ? '取消全选'
                                  : '全选',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 题库列表
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _stats!.length,
                        itemBuilder: (context, index) {
                          final stat = _stats![index];
                          return _BankErrorCard(
                            bankName: stat['bank_name'] as String,
                            bankId: stat['bank_id'] as int,
                            dueCount: stat['due_count'] as int,
                            bookmarkCount: stat['bookmark_count'] as int,
                            isSelected:
                                _selectedBanks.contains(stat['bank_id']),
                            cs: cs,
                            onToggle: () {
                              setState(() {
                                final id = stat['bank_id'] as int;
                                if (_selectedBanks.contains(id)) {
                                  _selectedBanks.remove(id);
                                } else {
                                  _selectedBanks.add(id);
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
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _startReview(),
                            child: Text(
                              _selectedBanks.isEmpty
                                  ? '全题库重刷（共 ${_totalDue + _totalBookmarks} 题）'
                                  : '开始重刷（已选 $_totalSelected 题）',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<void> _startReview() async {
    final appState = context.read<AppState>();

    if (!appState.settings.isConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请先在设置中配置 API Key'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    // 未选择题库 → 传空 = 全题库
    await appState.startErrorReview(
        bankIds: _selectedBanks.isEmpty ? null : _selectedBanks);
    if (appState.quizQuestions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无到期错题')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuizScreen()),
    );
  }
}

class _BankErrorCard extends StatelessWidget {
  final String bankName;
  final int bankId;
  final int dueCount;
  final int bookmarkCount;
  final bool isSelected;
  final ColorScheme cs;
  final VoidCallback onToggle;

  const _BankErrorCard({
    required this.bankName,
    required this.bankId,
    required this.dueCount,
    required this.bookmarkCount,
    required this.isSelected,
    required this.cs,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected ? cs.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? cs.primary : cs.outlineVariant,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 16, color: cs.onPrimary)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bankName,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 13, color: cs.error),
                      const SizedBox(width: 4),
                      Text('$dueCount 题待复习',
                          style: TextStyle(
                              fontSize: 12, color: cs.error)),
                      const SizedBox(width: 12),
                      if (bookmarkCount > 0) ...[
                        Icon(Icons.bookmark, size: 13, color: cs.secondary),
                        const SizedBox(width: 4),
                        Text('$bookmarkCount 题收藏',
                            style: TextStyle(
                                fontSize: 12, color: cs.secondary)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: cs.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}
