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
    return Padding(
      padding: const EdgeInsets.all(MaoSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('答题卡',
              style: MaoType.h3Style.copyWith(
                  fontWeight: FontWeight.w600, color: ac.textPrimary)),
          const SizedBox(height: MaoSpace.xs),
          // 图例：小方格 + 说明（精密风格不做色块，只用细边小格）
          Row(
            children: [
              if (showResult) ...[
                _legend(ac, ac.success, '答对'),
                const SizedBox(width: MaoSpace.sm),
                _legend(ac, ac.danger, '答错'),
                const SizedBox(width: MaoSpace.sm),
                _legend(ac, ac.textTertiary, '未答'),
              ] else ...[
                _legend(ac, ac.accent, '已答'),
                const SizedBox(width: MaoSpace.sm),
                _legend(ac, ac.textTertiary, '未答'),
              ],
            ],
          ),
          const SizedBox(height: MaoSpace.sm),
          Wrap(
            spacing: MaoSpace.xs - 2,
            runSpacing: MaoSpace.xs - 2,
            children: List.generate(answers.length, (i) {
              final a = answers[i];
              Color bg;
              Color fg;
              Color bd;
              if (!a.answered) {
                bg = Colors.transparent;
                fg = ac.textTertiary;
                bd = ac.border;
              } else if (showResult && a.correct) {
                bg = ac.successSoft;
                fg = ac.success;
                bd = ac.success;
              } else if (showResult) {
                bg = ac.dangerSoft;
                fg = ac.danger;
                bd = ac.danger;
              } else {
                // 练习模式：已答用强调色（不判定对错）
                bg = ac.accentSoft;
                fg = ac.accent;
                bd = ac.accent;
              }
              final isCurrent = i == currentIndex;
              if (isCurrent) {
                bg = ac.accent;
                fg = ac.onAccent;
                bd = ac.accent;
              }
              return InkWell(
                borderRadius: MaoRadius.smallBorder,
                onTap: () => onJumpTo(i),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: MaoRadius.smallBorder,
                    border: Border.all(
                        color: bd,
                        width: isCurrent ? 1.6 : MaoLine.width),
                  ),
                  alignment: Alignment.center,
                  child: Text('${i + 1}',
                      style: MaoType.number(MaoType.caption,
                              weight: FontWeight.w600)
                          .copyWith(color: fg)),
                ),
              );
            }),
          ),
          const SizedBox(height: MaoSpace.md),
        ],
      ),
    );
  }

  Widget _legend(AppThemeColors ac, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color.withOpacity(0.18),
            borderRadius: MaoRadius.chipBorder,
            border: Border.all(color: color.withOpacity(0.55), width: 1),
          ),
        ),
        const SizedBox(width: MaoSpace.xxs + 1),
        Text(label,
            style: MaoType.microStyle.copyWith(color: ac.textSecondary)),
      ],
    );
  }
}
