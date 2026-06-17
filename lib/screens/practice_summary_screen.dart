import 'package:flutter/material.dart';
import '../services/app_state.dart';

class PracticeSummaryScreen extends StatelessWidget {
  final int correct;
  final int wrong;
  final int blank;
  final int elapsedSeconds;

  const PracticeSummaryScreen({
    super.key,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.elapsedSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final total = correct + wrong + blank;
    final answered = correct + wrong;
    final acc = answered > 0 ? (correct / answered * 100).toStringAsFixed(1) : '0';
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('练习结算')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.emoji_events, size: 48, color: cs.primary),
              const SizedBox(height: 8),
              Text('练习完成', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 32),
              _stat(Icons.check_circle, '答对', correct, const Color(0xFF5CB85C)),
              _stat(Icons.cancel, '答错', wrong, const Color(0xFFD9534F)),
              _stat(Icons.help_outline, '空白', blank, cs.onSurfaceVariant),
              const Divider(height: 32),
              _stat(Icons.trending_up, '正确率（排除空白）', acc + '%', cs.secondary),
              _stat(Icons.timer, '用时', _fmt(elapsedSeconds), cs.primary),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.home),
                label: const Text('返回首页'),
                onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String label, Object value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 16, color: color)),
          const Spacer(),
          Text(value.toString(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  static String _fmt(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    if (m > 0) return '$m分$s秒';
    return '$s秒';
  }
}
