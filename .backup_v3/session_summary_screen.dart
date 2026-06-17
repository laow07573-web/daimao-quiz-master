import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quiz_session.dart';
import '../services/app_state.dart';
import '../widgets/ai_response_widget.dart';
import 'quiz_screen.dart';

class SessionSummaryScreen extends StatefulWidget {
  final QuizSession session;

  const SessionSummaryScreen({super.key, required this.session});

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  String? _summaryText;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generateSummary();
  }

  Future<void> _generateSummary() async {
    final appState = context.read<AppState>();
    final summary = await appState.generateSessionSummary(widget.session);
    if (mounted) {
      setState(() {
        _summaryText = summary;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final accuracy = session.accuracy;
    final minutes = session.durationSeconds ~/ 60;
    final seconds = session.durationSeconds % 60;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('刷题小结'),
        elevation: 0,
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 成绩卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, cs.primary.withAlpha(200)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text('本次刷题完成',
                      style: TextStyle(color: cs.onPrimary.withOpacity(0.7), fontSize: 14)),
                  const SizedBox(height: 12),
                  Text('${accuracy.toStringAsFixed(1)}%',
                      style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 48,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('正确率',
                      style: TextStyle(
                          color: cs.onPrimary.withOpacity(0.8), fontSize: 14)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 详细统计
            Row(
              children: [
                Expanded(
                  child: _StatChip(
                    icon: Icons.quiz_outlined,
                    label: '总题量',
                    value: '${session.totalQuestions}',
                    color: cs.primary,
                    surfaceColor: cs.surface,
                    onSurfaceVariant: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatChip(
                    icon: Icons.check_circle_outline,
                    label: '正确',
                    value: '${session.correctCount}',
                    color: const Color(0xFF5CB85C),
                    surfaceColor: cs.surface,
                    onSurfaceVariant: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatChip(
                    icon: Icons.cancel_outlined,
                    label: '错误',
                    value: '${session.wrongCount}',
                    color: cs.error,
                    surfaceColor: cs.surface,
                    onSurfaceVariant: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatChip(
                    icon: Icons.timer_outlined,
                    label: '用时',
                    value: '$minutes\'${seconds.toString().padLeft(2, '0')}"',
                    color: cs.secondary,
                    surfaceColor: cs.surface,
                    onSurfaceVariant: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // AI 小结
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome,
                          color: cs.secondary, size: 20),
                      const SizedBox(width: 8),
                      Text('AI 小结',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15, color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    Center(
                        child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: CircularProgressIndicator(color: cs.primary),
                    ))
                  else
                    AiResponseWidget(
                      text: _summaryText ?? '生成小结失败',
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 返回首页按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('返回首页', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final appState = context.read<AppState>();
                  await appState.startQuiz();
                  if (appState.quizQuestions.isEmpty) return;
                  if (!mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const QuizScreen()),
                  );
                },
                child: const Text('再来一轮', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color surfaceColor;
  final Color onSurfaceVariant;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.surfaceColor,
    required this.onSurfaceVariant,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: TextStyle(fontSize: 10, color: onSurfaceVariant)),
        ],
      ),
    );
  }
}
