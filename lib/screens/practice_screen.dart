import '../utils/design_tokens.dart';
import '../services/theme_service.dart';
import 'package:flutter/material.dart';
import '../models/question.dart';
import '../utils/responsive.dart';
import '../widgets/answer_sheet_widget.dart';
import 'quiz_screen.dart';

enum PracticeTiming { timed, untimed }

/// 练习模式入口：选择时间模式（v1.0.2 统一重构：选择后进入统一答题页）
class PracticeEntryScreen extends StatelessWidget {
  const PracticeEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('选择练习模式')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.timer, size: 64, color: ac.accent),
            const SizedBox(height: 16),
            const Text('练习模式', style: TextStyle(fontSize: MaoType.display, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            SizedBox(width: 300, child: _card(context, ac, Icons.hourglass_empty, '不限时练习', '不设截止时间，正计时', '自由作答，随时手动提交', () => _start(context, PracticeTiming.untimed, 0))),
            const SizedBox(height: 16),
            SizedBox(width: 300, child: _card(context, ac, Icons.timer, '限时练习', '倒计时自动交卷', '模拟考试压力，设定时长', () => _pickMinutes(context))),
          ]),
        ),
      ),
    );
  }

  Widget _card(BuildContext ctx, AppThemeColors ac, IconData icon, String title, String desc, String hint, VoidCallback onTap) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(MaoRadius.control),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(icon, size: 36, color: ac.accent),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: MaoType.h2, fontWeight: FontWeight.w600, color: ac.textPrimary)),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary)),
              Text(hint, style: TextStyle(fontSize: MaoType.caption, color: ac.border)),
            ])),
            Icon(Icons.chevron_right, color: ac.border),
          ]),
        ),
      ),
    );
  }

  void _pickMinutes(BuildContext context) {
    showModalBottomSheet(
      context: context,
      // 平板适配：弹窗限宽居中
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('设定练习时长（分钟）', style: TextStyle(fontSize: MaoType.h2, fontWeight: FontWeight.bold)),
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

/// 练习结果页（v1.0.2 统一重构保留）：正确率大数字 + 复盘答题卡 + 错题回顾折叠卡
class PracticeResultScreen extends StatefulWidget {
  final int correct, wrong, blank, total, elapsedSeconds, durationMinutes;
  final String accuracy;
  final PracticeTiming timing;
  final List<Map<String, dynamic>> wrongList;
  final List<Question> questions;
  final Map<int, String> answers;
  /// v1.0.2 七项改进：复盘答题卡状态（已答 + 判定结果）
  final List<PracticeAnswerState> answerStates;

  const PracticeResultScreen({super.key, required this.correct, required this.wrong, required this.blank, required this.total, required this.accuracy, required this.elapsedSeconds, required this.timing, required this.durationMinutes, required this.wrongList, required this.questions, required this.answers, this.answerStates = const []});

  @override
  State<PracticeResultScreen> createState() => _PracticeResultScreenState();
}

class _PracticeResultScreenState extends State<PracticeResultScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _tileKeys = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _fmt(int s) { final m = s ~/ 60; return '$m分${s % 60}秒'; }

  /// v1.0.2 七项改进：答题卡点格子滚动定位到对应错题卡
  void _jumpTo(int index) {
    final key = _tileKeys[index];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('练习结果'), leading: IconButton(icon: const Icon(Icons.home), onPressed: () => Navigator.popUntil(context, (r) => r.isFirst))),
      // 平板适配：内容限宽居中（手机无影响）
      body: ResponsivePage(
        child: ListView(controller: _scrollController, padding: const EdgeInsets.all(20), children: [
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: LinearGradient(colors: [ac.accent, ac.accent.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(MaoRadius.card)),
          child: Column(children: [Text('${widget.accuracy}%', style: MaoType.displayStyle.copyWith(fontSize: MaoType.display, color: ac.onAccent)), const SizedBox(height: 8), Text('正确${widget.correct} · 错误${widget.wrong} · 未答${widget.blank}', style: MaoType.h3Style.copyWith(color: ac.onAccent.withOpacity(0.85))), const SizedBox(height: 4), Text(widget.timing == PracticeTiming.timed ? '限时${widget.durationMinutes}分钟 · 实际${_fmt(widget.elapsedSeconds)}' : '不限时 · 用时${_fmt(widget.elapsedSeconds)}', style: MaoType.captionStyle.copyWith(color: ac.onAccent.withOpacity(0.7)))])),
        const SizedBox(height: 20),
        // v1.0.2 七项改进：复盘答题卡（答对绿/答错红/未答灰，点格子定位错题）
        if (widget.answerStates.isNotEmpty) ...[
          Card(
            child: AnswerSheetWidget(
              answers: widget.answerStates,
              currentIndex: -1,
              showResult: true,
              onJumpTo: _jumpTo,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.wrongList.isNotEmpty) ...[Text('错题回顾 (${widget.wrongList.length}题)', style: const TextStyle(fontSize: MaoType.h2, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
          ...widget.wrongList.map((w) { final q = w['q'] as Question, ua = w['ua'] as String;
            final idx = (w['idx'] as int?) ?? -1;
            return Card(key: idx >= 0 ? (_tileKeys[idx] ??= GlobalKey()) : null, child: ExpansionTile(
              leading: CircleAvatar(backgroundColor: ac.danger.withOpacity(0.15), radius: 16, child: Icon(Icons.close, color: ac.danger, size: 16)),
              title: Text(q.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: MaoType.body)),
              subtitle: Text('你的答案: $ua  →  正确答案: ${q.correctAnswer}', style: const TextStyle(fontSize: MaoType.caption)),
              children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Divider(), const Text('题目解析', style: TextStyle(fontWeight: FontWeight.bold, fontSize: MaoType.body)), const SizedBox(height: 4), Text(q.analysis ?? '暂无解析', style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary, height: 1.5))]))],
            ));
          })],
        if (widget.wrongList.isEmpty) ...[const SizedBox(height: 40), Icon(Icons.celebration, size: 64, color: ac.accent), const SizedBox(height: 12), const Text('全部正确！', style: TextStyle(fontSize: MaoType.h1, fontWeight: FontWeight.bold), textAlign: TextAlign.center)],
      ]),
      ),
    );
  }
}
