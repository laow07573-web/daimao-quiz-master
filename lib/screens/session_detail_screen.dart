import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quiz_session.dart';
import '../services/app_state.dart';

/// 会话详情（v1.0.2）：answer_records JOIN questions 逐题只读展示
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.session});

  final QuizSession session;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  List<Map<String, dynamic>>? _records;
  String? _error;
  late QuizSession _session = widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records =
          await context.read<AppState>().getSessionDetail(widget.session.id!);
      if (!mounted) return;
      setState(() => _records = records);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  /// v1.0.2 对齐里程碑：改判（判错了？/ 已改判为正确·错误）
  Future<void> _rejudge(int recordId, bool newCorrect) async {
    await context.read<AppState>().rejudgeAnswerRecord(recordId, newCorrect);
    if (!mounted) return;
    // 刷新记录 + 会话概览数字
    final records =
        await context.read<AppState>().getSessionDetail(widget.session.id!);
    final sessions = await context.read<AppState>().getRecentSessions(200);
    final updated = sessions
        .where((s) => s.id == widget.session.id)
        .firstOrNull;
    if (!mounted) return;
    setState(() {
      _records = records;
      if (updated != null) _session = updated;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newCorrect ? '已改判为正确' : '已改判为错误'),
        backgroundColor: newCorrect
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('会话详情')),
      body: _records == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // 会话概览
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _Info(label: '题数', value: '${s.totalQuestions}'),
                      _Info(label: '答对', value: '${s.correctCount}'),
                      _Info(label: '答错', value: '${s.wrongCount}'),
                      _Info(
                          label: '正确率',
                          value: '${s.accuracy.toStringAsFixed(1)}%'),
                      _Info(label: '用时', value: _fmt(s.durationSeconds)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: cs.error))
                else
                  for (final r in _records!)
                    _RecordTile(
                      record: r,
                      onRejudge: (newCorrect) =>
                          _rejudge(r['id'] as int, newCorrect),
                    ),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final sec = seconds % 60;
    return m > 0 ? '${m}分${sec}秒' : '${sec}秒';
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface)),
          Text(label,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.onRejudge});

  final Map<String, dynamic> record;
  final ValueChanged<bool> onRejudge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCorrect = (record['is_correct'] as int?) == 1;
    final title = (record['question_title'] as String?) ?? '未知题目';
    final userAnswer = (record['user_answer'] as String?)?.trim() ?? '';
    final correctAnswer = (record['correct_answer'] as String?) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2, right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isCorrect ? cs.primary : cs.error).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCorrect ? '对' : '错',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isCorrect ? cs.primary : cs.error,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 13, color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '你的答案：${userAnswer.isEmpty ? '（未作答）' : userAnswer}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (correctAnswer.isNotEmpty)
            Text(
              '正确答案：$correctAnswer',
              style: TextStyle(
                fontSize: 12,
                color: isCorrect ? cs.onSurfaceVariant : cs.error,
              ),
            ),
          // v1.0.2 对齐里程碑：改判
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor:
                    isCorrect ? cs.onSurfaceVariant : cs.tertiary,
              ),
              onPressed: () => onRejudge(!isCorrect),
              child: Text(
                isCorrect ? '改判为错误' : '判错了？',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
