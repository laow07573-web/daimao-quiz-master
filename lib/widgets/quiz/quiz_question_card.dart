import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../../services/theme_service.dart';
import '../../utils/design_tokens.dart';
import '../kit/mj_kit.dart';

/// 答题页 · 题干卡（纯展示，无副作用）
///
/// 从 quiz_screen 抽出：顶部元信息带（题型标签 + 作答统计 + FSRS 下次复习）
/// + 发丝分隔 + 题干正文。
class QuizQuestionCard extends StatelessWidget {
  const QuizQuestionCard({
    super.key,
    required this.question,
    required this.attempts,
    required this.accuracyPercent,
    this.nextReviewLabel,
  });

  final Question question;

  /// 历史作答次数（0 表示首次）
  final int attempts;

  /// 历史正确率（0~100）
  final int accuracyPercent;

  /// 下次复习文案（如「今天」「3 天后」），null 时不显示
  final String? nextReviewLabel;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final hasStats = attempts > 0;
    final meta = hasStats
        ? '作答$attempts次  正确率$accuracyPercent%'
            '${nextReviewLabel != null ? ' · 下次复习：$nextReviewLabel' : ''}'
        : null;

    return MJSurface(
      padding: const EdgeInsets.all(MaoSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MJTag(question.typeLabel, tone: MJTagTone.accent),
              const Spacer(),
              if (meta != null)
                Flexible(
                  child: Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: MaoType.microStyle
                          .copyWith(color: ac.textTertiary)),
                ),
            ],
          ),
          const SizedBox(height: MaoSpace.sm),
          Container(height: MaoLine.width, color: ac.border),
          const SizedBox(height: MaoSpace.sm),
          Text(question.title,
              style: MaoType.h3Style
                  .copyWith(height: 1.65, color: ac.textPrimary)),
        ],
      ),
    );
  }
}

/// 选项行（单选 / 多选 / 背题高亮共用）
///
/// Linear 式小方块选择器：未选中显示字母、选中显示勾；
/// [state] 用于答后着色（正确/错误/中性）。
class QuizOptionRow extends StatelessWidget {
  const QuizOptionRow({
    super.key,
    required this.label,
    required this.text,
    required this.selected,
    required this.onTap,
    this.state = QuizOptionState.neutral,
    this.trailing,
  });

  /// 选项字母（A/B/C…）
  final String label;
  final String text;
  final bool selected;

  /// 作答后的判定着色
  final QuizOptionState state;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);

    // 答后状态优先决定配色；未判定时用选中态
    Color bg;
    Color bd;
    Color fg;
    IconData? badge;
    switch (state) {
      case QuizOptionState.correct:
        bg = ac.successSoft;
        bd = ac.success;
        fg = ac.success;
        badge = Icons.check;
      case QuizOptionState.wrong:
        bg = ac.dangerSoft;
        bd = ac.danger;
        fg = ac.danger;
        badge = Icons.close;
      case QuizOptionState.answered:
        bg = ac.surfaceAlt;
        bd = ac.border;
        fg = ac.textTertiary;
      case QuizOptionState.neutral:
        bg = selected ? ac.accentSoft : ac.surface;
        bd = selected ? ac.accent : ac.border;
        fg = selected ? ac.accent : ac.textPrimary;
        badge = selected ? Icons.check : null;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: MaoSpace.xs - 2),
      child: Material(
        color: bg,
        borderRadius: MaoRadius.controlBorder,
        child: InkWell(
          onTap: onTap,
          borderRadius: MaoRadius.controlBorder,
          splashColor: ac.accent.withOpacity(0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: MaoSpace.sm, vertical: MaoSpace.sm + 1),
            decoration: BoxDecoration(
              borderRadius: MaoRadius.controlBorder,
              border: Border.all(
                color: bd,
                width: (selected || state != QuizOptionState.neutral)
                    ? 1.4
                    : MaoLine.width,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: badge != null ? bd : Colors.transparent,
                    borderRadius: MaoRadius.chipBorder,
                    border: Border.all(color: bd, width: 1.2),
                  ),
                  child: Center(
                    child: badge != null
                        ? Icon(badge,
                            size: 13,
                            color: state == QuizOptionState.neutral
                                ? ac.onAccent
                                : Colors.white)
                        : Text(label,
                            style: MaoType.number(MaoType.micro,
                                    weight: FontWeight.w600)
                                .copyWith(color: ac.textTertiary)),
                  ),
                ),
                const SizedBox(width: MaoSpace.sm),
                Expanded(
                  child: Text(text,
                      style: MaoType.bodyStyle
                          .copyWith(height: 1.45, color: fg)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 选项的作答状态
enum QuizOptionState { neutral, correct, wrong, answered }

/// 「查看 AI 解析」入口卡（答对后默认折叠时显示）。
///
/// 精密暗色：发丝描边面板 + 强调色文案，取代旧版带色块的大按钮。
class QuizViewAnalysisCard extends StatelessWidget {
  const QuizViewAnalysisCard({
    super.key,
    required this.onTap,
    this.exampleOnly = false,
  });

  final VoidCallback onTap;

  /// 无 Key 且题目自带解析时为 true：展开的是「示例解析」而非 AI 解析，
  /// 标题照此写明，免得用户以为点了会调 AI（与展开后的面板标题保持同一口径）。
  final bool exampleOnly;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return MJSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: MaoSpace.sm + 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lightbulb_outline, color: ac.accent, size: 17),
          const SizedBox(width: MaoSpace.xs),
          Text(exampleOnly ? '查看示例解析' : '查看AI解析',
              style: MaoType.h3Style.copyWith(
                  fontWeight: FontWeight.w600, color: ac.accent)),
        ],
      ),
    );
  }
}

/// 作答结果反馈：正确答案（绿）+ 你的答案（对绿错红）。
class QuizResultFeedback extends StatelessWidget {
  const QuizResultFeedback({
    super.key,
    required this.correctAnswer,
    required this.userAnswer,
    required this.isCorrect,
  });

  final String correctAnswer;
  final String userAnswer;
  final bool isCorrect;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('正确答案: $correctAnswer',
            style: MaoType.h3Style.copyWith(
                fontWeight: FontWeight.w600, color: ac.success)),
        const SizedBox(height: MaoSpace.xxs),
        // v1.0.2 设计审查修复：答对时「你的答案」不再恒显示错误红色
        Text('你的答案: $userAnswer',
            style: MaoType.h3Style.copyWith(
                fontWeight: FontWeight.w600,
                color: isCorrect ? ac.success : ac.danger)),
      ],
    );
  }
}

/// 判断题作答按钮（✓ 正确 / ✗ 错误）。
///
/// 精密暗色：发丝描边 + 语义色文字；练习模式下选中项用语义浅底。
class QuizTrueFalseButtons extends StatelessWidget {
  const QuizTrueFalseButtons({
    super.key,
    required this.onTrue,
    required this.onFalse,
    this.practiceSelected,
  });

  final VoidCallback onTrue;
  final VoidCallback onFalse;

  /// 练习模式当前已选项（'对' / '错' / null）
  final String? practiceSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _btn(
            context,
            label: '✓  正确',
            color: AppThemeColors.of(context).success,
            softColor: AppThemeColors.of(context).successSoft,
            selected: practiceSelected == '对',
            onTap: onTrue,
          ),
        ),
        const SizedBox(width: MaoSpace.sm),
        Expanded(
          child: _btn(
            context,
            label: '✗  错误',
            color: AppThemeColors.of(context).danger,
            softColor: AppThemeColors.of(context).dangerSoft,
            selected: practiceSelected == '错',
            onTap: onFalse,
          ),
        ),
      ],
    );
  }

  Widget _btn(
    BuildContext context, {
    required String label,
    required Color color,
    required Color softColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final ac = AppThemeColors.of(context);
    return AnimatedContainer(
      duration: MaoMotion.fast,
      curve: MaoMotion.standard,
      decoration: BoxDecoration(
        color: selected ? softColor : ac.surface,
        borderRadius: MaoRadius.controlBorder,
        border: Border.all(
          color: selected ? color : ac.border,
          width: selected ? 1.4 : MaoLine.width,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: MaoRadius.controlBorder,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: MaoSpace.md),
            child: Center(
              child: Text(label,
                  style: MaoType.h3Style.copyWith(
                      fontWeight: FontWeight.w600, color: color)),
            ),
          ),
        ),
      ),
    );
  }
}
