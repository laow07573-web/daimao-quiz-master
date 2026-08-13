import 'package:flutter/material.dart';

class PracticeAnswerState {
  bool answered = false;
}

class AnswerSheetWidget extends StatelessWidget {
  final List<PracticeAnswerState> answers;
  final int currentIndex;
  final void Function(int index) onJumpTo;

  const AnswerSheetWidget({
    super.key,
    required this.answers,
    required this.currentIndex,
    required this.onJumpTo,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('答题卡', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 4),
          Row(
            children: [
              _legend(cs.primary, '已答'),
              const SizedBox(width: 12),
              _legend(cs.onSurfaceVariant, '未答'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(answers.length, (i) {
              final a = answers[i];
              Color bg;
              Color fg;
              if (!a.answered) {
                bg = cs.surfaceContainerHighest;
                fg = cs.onSurfaceVariant;
              } else {
                // 练习模式：已答用主题色（提交前不判定对错）
                bg = cs.primary.withOpacity(0.2);
                fg = cs.primary;
              }
              if (i == currentIndex) {
                bg = cs.primaryContainer;
              }
              return GestureDetector(
                onTap: () => onJumpTo(i),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: i == currentIndex ? cs.primary : cs.outlineVariant, width: i == currentIndex ? 2 : 1),
                  ),
                  alignment: Alignment.center,
                  child: Text('${i + 1}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color.withOpacity(0.3), borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
