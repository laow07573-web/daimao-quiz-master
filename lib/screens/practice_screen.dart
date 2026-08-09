import 'dart:async';
import 'package:flutter/material.dart';
import '../models/question.dart';

enum PracticeTiming { timed, untimed }

/// 练习模式入口：选择时间模式
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
    );
  }

  void _start(BuildContext context, PracticeTiming timing, int minutes) {
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => PracticeScreen(timing: timing, questions: questions, durationMinutes: minutes),
    ));
  }
}

/// 答题屏幕
class PracticeScreen extends StatefulWidget {
  final PracticeTiming timing;
  final int durationMinutes;
  final List<Question> questions;
  const PracticeScreen({super.key, required this.timing, required this.questions, this.durationMinutes = 0});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final Map<int, String> _answers = {};
  int _currentIndex = 0;
  final ScrollController _scrollCtrl = ScrollController();
  Timer? _timer;
  int _elapsedSeconds = 0;
  int _remainingSeconds = 0;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    if (widget.timing == PracticeTiming.timed) _remainingSeconds = widget.durationMinutes * 60;
    _startTimer();
  }

  @override
  void dispose() { _timer?.cancel(); _scrollCtrl.dispose(); super.dispose(); }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _submitted) return;
      setState(() {
        _elapsedSeconds++;
        if (widget.timing == PracticeTiming.timed) { _remainingSeconds--; if (_remainingSeconds <= 0) _submit(); }
      });
    });
  }

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  void _submit() {
    if (_submitted) return;
    _timer?.cancel();
    setState(() => _submitted = true);
    final qs = widget.questions;
    int correct = 0, wrong = 0, blank = 0;
    final wrongList = <Map<String, dynamic>>[];
    for (int i = 0; i < qs.length; i++) {
      final ua = _answers[i];
      if (ua == null || ua.isEmpty) { blank++; continue; }
      if (_check(qs[i], ua)) { correct++; } else { wrong++; wrongList.add({'idx': i, 'q': qs[i], 'ua': ua}); }
    }
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final acc = qs.isNotEmpty ? (correct / qs.length * 100).toStringAsFixed(1) : '0';
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PracticeResultScreen(correct: correct, wrong: wrong, blank: blank, total: qs.length, accuracy: acc, elapsedSeconds: _elapsedSeconds, timing: widget.timing, durationMinutes: widget.durationMinutes, wrongList: wrongList, questions: qs, answers: _answers)));
    });
  }

  bool _check(Question q, String ua) {
    final cr = q.correctAnswer.toUpperCase().trim(), u = ua.toUpperCase().trim();
    if (q.questionType == 'multi_choice') {
      final crS = cr.split(',').map((e) => e.trim()).toSet(), uaS = u.split(',').map((e) => e.trim()).toSet();
      return crS.length == uaS.length && crS.containsAll(uaS);
    }
    return u == cr;
  }

  Future<bool> _onWillPop() async {
    if (_submitted) return true;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('退出练习'),
      content: Text(widget.timing == PracticeTiming.timed ? '退出即放弃本次练习。倒计时不暂停，时间走完将自动提交。' : '退出后本次练习记录将不保存。'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续练习')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定退出'), style: TextButton.styleFrom(foregroundColor: Colors.red))],
    ));
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qs = widget.questions;
    if (qs.isEmpty) return Scaffold(appBar: AppBar(title: const Text('练习')), body: const Center(child: Text('无题目')));
    final q = qs[_currentIndex], answered = _answers.length;
    final isTimed = widget.timing == PracticeTiming.timed;
    final warnSec = isTimed ? (widget.durationMinutes * 60 * 0.1).ceil().clamp(60, 300) : 0;
    final showWarn = isTimed && _remainingSeconds <= warnSec && _remainingSeconds > 0;

    return PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) async { if (!didPop) { final ok = await _onWillPop(); if (ok && mounted) Navigator.of(context).pop(); } },
      child: Scaffold(
        appBar: AppBar(
          title: Text('第 ${_currentIndex + 1}/${qs.length} 题'),
          actions: [
            Padding(padding: const EdgeInsets.only(right: 8), child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: showWarn ? Colors.red : cs.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
              child: Text(isTimed ? '剩余 ${_fmt(_remainingSeconds)}' : '已用 ${_fmt(_elapsedSeconds)}', style: TextStyle(fontSize: showWarn ? 16 : 14, fontWeight: FontWeight.bold, color: showWarn ? Colors.white : cs.onSurface)),
            ))),
            IconButton(icon: const Icon(Icons.grid_view), tooltip: '答题卡', onPressed: () => _showAnswerCard(cs)),
          ],
        ),
        body: Column(children: [
          if (showWarn) Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 6), color: Colors.red.shade700, child: const Center(child: Text('⚠ 时间即将耗尽', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)))),
          Expanded(child: SingleChildScrollView(controller: _scrollCtrl, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildQCard(q, cs), const SizedBox(height: 20), _buildOpts(q, cs)]))),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            decoration: BoxDecoration(color: cs.surface, boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, -2))]),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_ios, size: 18), onPressed: _currentIndex > 0 ? () { setState(() => _currentIndex--); _scrollCtrl.jumpTo(0); } : null),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(qs.length, (i) {
                      final cur = i == _currentIndex;
                      final ans = _answers.containsKey(i);
                      return GestureDetector(
                        onTap: () => setState(() => _currentIndex = i),
                        child: Container(
                          width: 26, height: 26, margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cur ? cs.primary : ans ? cs.primary.withOpacity(0.35) : cs.surfaceContainerHighest,
                            border: cur ? Border.all(color: cs.onPrimary, width: 2) : null,
                          ),
                          child: Center(child: Text('${i + 1}', style: TextStyle(fontSize: 10, fontWeight: cur ? FontWeight.bold : FontWeight.normal, color: cur ? cs.onPrimary : cs.onSurface))),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.arrow_forward_ios, size: 18), onPressed: _currentIndex < qs.length - 1 ? () { setState(() => _currentIndex++); _scrollCtrl.jumpTo(0); } : null),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: SizedBox(width: double.infinity, child: FilledButton.icon(icon: const Icon(Icons.assignment_turned_in), label: Text('提交练习 ($answered/${qs.length})'), onPressed: _showSubmit))),
        ]),
      ),
    );
  }

  Widget _buildQCard(Question q, ColorScheme cs) {
    final t = {'single_choice':'单选','multi_choice':'多选','true_false':'判断','fill_blank':'填空'};
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: cs.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(t[q.questionType] ?? '单选', style: TextStyle(fontSize: 11, color: cs.primary))), const SizedBox(width: 8), Expanded(child: Text(q.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)))]),
      ]));
  }

  Widget _buildOpts(Question q, ColorScheme cs) {
    final opts = q.questionType == 'true_false' ? ['对', '错'] : q.options;
    if (opts.isEmpty) {
      final ctrl = TextEditingController(text: _answers[_currentIndex] ?? '');
      return Column(children: [TextField(controller: ctrl, decoration: const InputDecoration(hintText: '输入答案...', border: OutlineInputBorder()), onChanged: (v) => _answers[_currentIndex] = v), const SizedBox(height: 8), FilledButton(onPressed: () => setState(() {}), child: const Text('确认'))]);
    }
    final isMulti = q.questionType == 'multi_choice';
    final ua = _answers[_currentIndex] ?? '';
    final sel = isMulti ? ua.split(',').map((e) => e.trim().toUpperCase()).toSet() : {ua.toUpperCase().trim()};
    return Column(children: List.generate(opts.length, (i) {
      final label = q.questionType == 'true_false' ? (i == 0 ? '对' : '错') : String.fromCharCode(65 + i);
      final s = sel.contains(label.toUpperCase());
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => setState(() {
        if (isMulti) { final x = (ua.isEmpty ? <String>{} : ua.split(',').map((e) => e.trim().toUpperCase()).toSet()); s ? x.remove(label.toUpperCase()) : x.add(label.toUpperCase()); _answers[_currentIndex] = (x.toList()..sort()).join(','); }
        else _answers[_currentIndex] = label;
      }), child: Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: s ? cs.primary.withOpacity(0.08) : cs.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: s ? cs.primary : cs.outlineVariant)),
        child: Row(children: [Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, color: s ? cs.primary : cs.surfaceContainerHighest), child: Center(child: s ? Icon(Icons.check, size: 14, color: cs.onPrimary) : Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurfaceVariant)))), const SizedBox(width: 12), Expanded(child: Text(opts[i], style: TextStyle(fontSize: 14, color: cs.onSurface)))]))));
    }));
  }

  void _showAnswerCard(ColorScheme cs) {
    final qs = widget.questions;
    showModalBottomSheet(context: context, builder: (_) => Container(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('答题卡', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: List.generate(qs.length, (i) => GestureDetector(onTap: () { Navigator.pop(context); setState(() => _currentIndex = i); }, child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: i == _currentIndex ? cs.primary : _answers.containsKey(i) ? cs.primary.withOpacity(0.35) : cs.surfaceContainerHighest, border: i == _currentIndex ? Border.all(color: cs.onPrimary, width: 2) : null), child: Center(child: Text('${i + 1}', style: TextStyle(color: i == _currentIndex ? cs.onPrimary : cs.onSurface))))))),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [_dot(cs.primary, '当前'), const SizedBox(width: 16), _dot(cs.primary.withOpacity(0.35), '已答'), const SizedBox(width: 16), _dot(cs.surfaceContainerHighest, '未答')]),
    ])));
  }

  Widget _dot(Color c, String l) => Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: c)), const SizedBox(width: 4), Text(l, style: const TextStyle(fontSize: 12))]);

  void _showSubmit() {
    final total = widget.questions.length, answered = _answers.length;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('提交练习'), content: Text('共$total题，已答$answered题，未答${total - answered}题。\n\n提交后将无法修改，确定提交？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('继续检查')), FilledButton(onPressed: () { Navigator.pop(ctx); _submit(); }, child: const Text('确认提交'))]));
  }
}

/// 结果页
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
              leading: CircleAvatar(backgroundColor: Colors.red.shade100, radius: 16, child: Text('✗', style: TextStyle(color: Colors.red.shade700, fontSize: 14))),
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
