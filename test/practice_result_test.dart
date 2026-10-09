import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/screens/practice_screen.dart';
import 'package:flashcard_app/screens/quiz_screen.dart';
import 'package:flashcard_app/services/theme_service.dart';

/// 2026-10-08 真机反馈（图一）：练习模式交白卷也判「全部正确！」。
///
/// 根因：结果页的彩蛋判定写的是 `wrongList.isEmpty` —— 交白卷时没有错题，
/// 错题列表为空 → 直接走全对分支。判定必须同时要求「有作答」且「没有未答」。
void main() {
  Widget host(Widget child) => ChangeNotifierProvider<ThemeService>(
        create: (_) => ThemeService(),
        child: MaterialApp(theme: ThemeService().themeData, home: child),
      );

  PracticeResultScreen result({
    required int correct,
    required int wrong,
    required int blank,
    List<Map<String, dynamic>> wrongList = const [],
  }) =>
      PracticeResultScreen(
        correct: correct,
        wrong: wrong,
        blank: blank,
        total: correct + wrong + blank,
        accuracy: (correct + wrong) == 0
            ? '0.0'
            : (correct / (correct + wrong) * 100).toStringAsFixed(1),
        elapsedSeconds: 19,
        timing: PracticeTiming.untimed,
        durationMinutes: 0,
        wrongList: wrongList,
        questions: const [],
        answers: const {},
        answerStates: const [],
      );

  testWidgets('交白卷显示原版彩蛋（blank_submit 图 + 您是完全不写是吗？）', (tester) async {
    await tester.pumpWidget(host(result(correct: 0, wrong: 0, blank: 50)));
    await tester.pumpAndSettle();

    expect(find.text('全部正确！'), findsNothing, reason: '交白卷（正确0·未答50）不该被判成全部正确');
    // 原版遗留彩蛋：手绘图 + 那句文案（资源在 assets/blank_submit.jpg）
    expect(find.text('您是完全不写是吗？'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget, reason: '彩蛋是一张图配一句话，图片必须渲染出来');
    expect(tester.takeException(), isNull);
  });

  testWidgets('全部作答且全对才显示彩蛋', (tester) async {
    await tester.pumpWidget(host(result(correct: 50, wrong: 0, blank: 0)));
    await tester.pumpAndSettle();

    expect(find.text('全部正确！'), findsOneWidget);
    expect(find.byIcon(Icons.celebration), findsOneWidget);
    expect(find.text('这次没有作答'), findsNothing);
  });

  testWidgets('有未答但没错题：不算全对（彩蛋不出现）', (tester) async {
    await tester.pumpWidget(host(result(correct: 30, wrong: 0, blank: 20)));
    await tester.pumpAndSettle();

    expect(find.text('全部正确！'), findsNothing, reason: '还有 20 题未答，不能算全部正确');
    expect(find.text('这次没有作答'), findsNothing);
  });

  testWidgets('有错题：正常显示错题回顾，无彩蛋', (tester) async {
    await tester.pumpWidget(host(result(
      correct: 30,
      wrong: 20,
      blank: 0,
      wrongList: [
        {
          'q': Question(
              bankId: 1,
              title: '示例错题',
              correctAnswer: 'A',
              options: const ['A', 'B'],
              createdAt: '2026-10-08T00:00:00.000'),
          'ua': 'B',
          'idx': 0,
        }
      ],
    )));
    await tester.pumpAndSettle();

    expect(find.text('全部正确！'), findsNothing);
    expect(find.textContaining('错题回顾'), findsOneWidget);
  });

  group('底部栏显示条件（交白卷能否走到结果页的前提）', () {
    test('练习模式一题未答也要显示底栏（否则没有提交入口）', () {
      expect(shouldShowBottomBar(mode: QuizMode.practice, isAnswered: false),
          isTrue,
          reason: '练习模式底栏就是「提交练习」；不显示就交不了白卷，'
              '白卷彩蛋这条路径直接走不到');
    });

    test('练习模式已答同样显示', () {
      expect(shouldShowBottomBar(mode: QuizMode.practice, isAnswered: true),
          isTrue);
    });

    test('背题模式始终显示（它的底栏是回到首页）', () {
      expect(shouldShowBottomBar(mode: QuizMode.memorize, isAnswered: false),
          isTrue);
    });

    test('刷题模式仍是答后才显示', () {
      expect(shouldShowBottomBar(mode: QuizMode.normal, isAnswered: false),
          isFalse);
      expect(
          shouldShowBottomBar(mode: QuizMode.normal, isAnswered: true), isTrue);
    });
  });
}
