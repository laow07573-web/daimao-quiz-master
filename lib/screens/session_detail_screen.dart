import '../utils/design_tokens.dart';
import '../services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quiz_session.dart';
import '../services/app_state.dart';
import '../utils/responsive.dart';

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
  // v1.0.2 修复：改判防双击
  bool _rejudging = false;

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
    if (_rejudging) return;
    _rejudging = true;
    // 先同步捕获 AppState，避免多次 await 之间反复使用 context
    final appState = context.read<AppState>();
    try {
      await appState.rejudgeAnswerRecord(recordId, newCorrect);
      if (!mounted) return;
      // v1.0.2 修复：按 sessionId 局部刷新概览，不再受 getRecentSessions(200) 限制
      final records = await appState.getSessionDetail(widget.session.id!);
      final updated = await appState.getSessionById(widget.session.id!);
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
    } finally {
      _rejudging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final s = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('会话详情')),
      // 平板适配：内容限宽居中（手机无影响）
      body: ResponsivePage(
        child: _records == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // 会话概览
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ac.surfaceAlt.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(MaoRadius.control),
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
                  Text(_error!, style: TextStyle(color: ac.danger))
                else if (_records!.isEmpty)
                  // v1.0.2 对齐里程碑：暂无该次作答记录
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('暂无该次作答记录',
                          style: TextStyle(
                              fontSize: MaoType.body, color: ac.textSecondary)),
                    ),
                  )
                else
                  for (final r in _records!)
                    _RecordTile(
                      record: r,
                      disabled: _rejudging,
                      onRejudge: (newCorrect) =>
                          _rejudge(r['id'] as int, newCorrect),
                    ),
                const SizedBox(height: 20),
              ],
            ),
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
    final ac = AppThemeColors.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: MaoType.h3,
                  fontWeight: FontWeight.bold,
                  color: ac.textPrimary)),
          Text(label,
              style: TextStyle(fontSize: MaoType.micro, color: ac.textSecondary)),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile(
      {required this.record, required this.onRejudge, this.disabled = false});

  final Map<String, dynamic> record;
  final ValueChanged<bool> onRejudge;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final isCorrect = (record['is_correct'] as int?) == 1;
    final title = (record['question_title'] as String?) ?? '未知题目';
    final userAnswer = (record['user_answer'] as String?)?.trim() ?? '';
    final correctAnswer = (record['correct_answer'] as String?) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ac.surfaceAlt.withOpacity(0.4),
        borderRadius: BorderRadius.circular(MaoRadius.small),
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
                  color: (isCorrect ? ac.accent : ac.danger).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(MaoRadius.chip),
                ),
                child: Text(
                  isCorrect ? '对' : '错',
                  style: TextStyle(
                    fontSize: MaoType.caption,
                    fontWeight: FontWeight.bold,
                    color: isCorrect ? ac.accent : ac.danger,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: MaoType.body, color: ac.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '你的答案：${userAnswer.isEmpty ? '（未作答）' : userAnswer}',
            style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary),
          ),
          if (correctAnswer.isNotEmpty)
            Text(
              '正确答案：$correctAnswer',
              style: TextStyle(
                fontSize: MaoType.body,
                color: isCorrect ? ac.textSecondary : ac.danger,
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
                    isCorrect ? ac.textSecondary : ac.accent,
              ),
              onPressed: disabled ? null : () => onRejudge(!isCorrect),
              child: Text(
                // v1.0.2 对齐里程碑：判错了，改判正确
                isCorrect ? '改判为错误' : '判错了，改判正确',
                style: const TextStyle(fontSize: MaoType.caption),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
