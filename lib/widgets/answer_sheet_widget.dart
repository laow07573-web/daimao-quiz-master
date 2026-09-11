import '../utils/design_tokens.dart';
import '../services/theme_service.dart';
import 'package:flutter/material.dart';

class PracticeAnswerState {
  bool answered = false;
  // v1.0.2 七项改进：练习结果页复盘用（提交后回填判定结果）
  bool correct = false;
}

class AnswerSheetWidget extends StatelessWidget {
  final List<PracticeAnswerState> answers;
  final int currentIndex;
  final void Function(int index) onJumpTo;
  /// v1.0.2 七项改进：是否显示对错（结果页复盘 = true；练习作答中 = false）
  final bool showResult;

  const AnswerSheetWidget({
    super.key,
    required this.answers,
    required this.currentIndex,
    required this.onJumpTo,
    this.showResult = false,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('答题卡', style: TextStyle(fontSize: MaoType.h2, fontWeight: FontWeight.w600, color: ac.textPrimary)),
          const SizedBox(height: 4),
          Row(
            children: [
              if (showResult) ...[
                _legend(ac.accent, '答对'),
                const SizedBox(width: 12),
                _legend(ac.danger, '答错'),
                const SizedBox(width: 12),
                _legend(ac.textSecondary, '未答'),
              ] else ...[
                _legend(ac.accent, '已答'),
                const SizedBox(width: 12),
                _legend(ac.textSecondary, '未答'),
              ],
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
                bg = ac.surfaceAlt;
                fg = ac.textSecondary;
              } else if (showResult && a.correct) {
                bg = ac.accent.withOpacity(0.2);
                fg = ac.accent;
              } else if (showResult) {
                bg = ac.danger.withOpacity(0.2);
                fg = ac.danger;
              } else {
                // 练习模式：已答用主题色（不判定对错）
                bg = ac.accent.withOpacity(0.2);
                fg = ac.accent;
              }
              if (i == currentIndex) {
                bg = ac.accentSoft;
              }
              return GestureDetector(
                onTap: () => onJumpTo(i),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(MaoRadius.chip),
                    border: Border.all(color: i == currentIndex ? ac.accent : ac.border, width: i == currentIndex ? 2 : 1),
                  ),
                  alignment: Alignment.center,
                  child: Text('${i + 1}',
                      style: TextStyle(fontSize: MaoType.body, fontWeight: FontWeight.w600, color: fg)),
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
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color.withOpacity(0.3), borderRadius: BorderRadius.circular(MaoRadius.chip))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: MaoType.caption)),
      ],
    );
  }
}
