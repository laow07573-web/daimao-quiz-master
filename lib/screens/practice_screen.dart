import 'package:flutter/material.dart';
import '../models/question.dart';
import 'quiz_screen.dart';

enum PracticeTiming { timed, untimed }

/// 练习模式入口：选择时间模式（v1.0.2 统一重构：选择后进入统一答题页）
class PracticeEntryScreen extends StatelessWidget {
  final List<Question> questions;
  const PracticeEntryScreen({super.key, required this.questions});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('选择练习模式')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.timer, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            const Text('练习模式', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            SizedBox(width: 300, child: _card(context, cs, Icons.hourglass_empty, '不限时练习', '不设截止时间，正计时', '自由作答，随时手动提交', () => _start(context, PracticeTiming.untimed, 0))),
            const SizedBox(height: 16),
            SizedBox(width: 300, child: _card(context, cs, Icons.timer, '限时练习', '倒计时自动交卷', '模拟考试压力，设定时长', () => _pickMinutes(context))),
          ]),
        ),
      ),
    );
  }

  Widget _card(BuildContext ctx, ColorScheme cs, IconData icon, String title, String desc, String hint, VoidCallback onTap) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(icon, size: 36, color: cs.primary),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              Text(hint, style: TextStyle(fontSize: 11, color: cs.outline)),
            ])),
            Icon(Icons.chevron_right, color: cs.outline),
          ]),
        ),
      ),
    );
  }

  void _pickMinutes(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('设定练习时长（分钟）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 12, children: [
            ... [15, 30, 45, 60, 90, 120].map((m) => ChoiceChip(label: Text('$m 分钟'), selected: false, onSelected: (_) { Navigator.pop(ctx); _start(context, PracticeTiming.timed, m); })),
            ChoiceChip(label: const Text('自定义'), selected: false, onSelected: (_) { Navigator.pop(ctx); _showCustomInput(context); }),
          ]),
        ]),
      ),
    );
  }

  void _showCustomInput(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义时长'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '输入分钟数', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () {
            final min = int.tryParse(ctrl.text);
            if (min != null && min > 0) {
              Navigator.pop(ctx);
              _start(context, PracticeTiming.timed, min);
            }
          }, child: const Text('开始')),
        ],
      ),
    ).then((_) => ctrl.dispose());
  }

  /// v1.0.2 统一重构：进入统一答题页（练习模式）
  void _start(BuildContext context, PracticeTiming timing, int minutes) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => QuizScreen(
          quizMode: QuizMode.practice,
          practiceTiming: timing,
          practiceDurationMinutes: minutes,
        ),
      ),
    );
  }
}

/// 练习结果页（v1.0.2 统一重构保留）：正确率大数字 + 错题回顾折叠卡
class PracticeResultScreen extends StatelessWidget {
  final int correct, wrong, blank, total, elapsedSeconds, durationMinutes;
  final String accuracy;
  final PracticeTiming timing;
  final List<Map<String, dynamic>> wrongList;
  final List<Question> questions;
  final Map<int, String> answers;

  const PracticeResultScreen({super.key, required this.correct, required this.wrong, required this.blank, required this.total, required this.accuracy, required this.elapsedSeconds, required this.timing, required this.durationMinutes, required this.wrongList, required this.questions, required this.answers});

  String _fmt(int s) { final m = s ~/ 60; return '$m分${s % 60}秒'; }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('练习结果'), leading: IconButton(icon: const Icon(Icons.home), onPressed: () => Navigator.popUntil(context, (r) => r.isFirst))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [Text('$accuracy%', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 8), Text('正确$correct · 错误$wrong · 未答$blank', style: const TextStyle(fontSize: 16, color: Colors.white70)), const SizedBox(height: 4), Text(timing == PracticeTiming.timed ? '限时${durationMinutes}分钟 · 实际${_fmt(elapsedSeconds)}' : '不限时 · 用时${_fmt(elapsedSeconds)}', style: const TextStyle(fontSize: 13, color: Colors.white54))])),
        const SizedBox(height: 20),
        if (wrongList.isNotEmpty) ...[Text('错题回顾 (${wrongList.length}题)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
          ...wrongList.map((w) { final q = w['q'] as Question, ua = w['ua'] as String;
            return Card(child: ExpansionTile(
              leading: CircleAvatar(backgroundColor: cs.error.withOpacity(0.15), radius: 16, child: Icon(Icons.close, color: cs.error, size: 16)),
              title: Text(q.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
              subtitle: Text('你的答案: $ua  →  正确答案: ${q.correctAnswer}', style: const TextStyle(fontSize: 12)),
              children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Divider(), const Text('题目解析', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(height: 4), Text(q.analysis ?? '暂无解析', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5))]))],
            ));
          })],
        if (wrongList.isEmpty) ...[const SizedBox(height: 40), Icon(Icons.celebration, size: 64, color: cs.primary), const SizedBox(height: 12), const Text('全部正确！', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center)],
      ]),
    );
  }
}
