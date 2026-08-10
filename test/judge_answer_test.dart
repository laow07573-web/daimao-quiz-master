import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/services/quiz_service.dart';

Question _q({
  required String type,
  required String answer,
  List<String> options = const [],
}) =>
    Question(
      bankId: 1,
      title: '测试题',
      options: options,
      correctAnswer: answer,
      questionType: type,
      createdAt: '2026-01-01T00:00:00',
    );

void main() {
  group('QuizService.judgeAnswer 共享判定', () {
    test('单选：忽略大小写与首尾空白', () {
      expect(
        QuizService.judgeAnswer(_q(type: 'single_choice', answer: 'A'), ' a '),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'single_choice', answer: 'A'), 'B'),
        isFalse,
      );
    });

    test('多选：集合比较忽略顺序与分隔符', () {
      expect(
        QuizService.judgeAnswer(_q(type: 'multi_choice', answer: 'A,C'), 'C,A'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'multi_choice', answer: 'A,C'), 'C、A'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'multi_choice', answer: 'A,C'), 'a c'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'multi_choice', answer: 'A,C'), 'A,B'),
        isFalse,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'multi_choice', answer: 'A,B,C'), 'C,A'),
        isFalse,
      );
    });

    test('填空：逐空去标点比对', () {
      expect(
        QuizService.judgeAnswer(
            _q(type: 'fill_blank', answer: '血红蛋白；红细胞'), '血红蛋白；红细胞'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(
            _q(type: 'fill_blank', answer: '血红蛋白；红细胞'), '血红蛋白。；红细 胞。'),
        isTrue,
      );
      // 空数不一致判错
      expect(
        QuizService.judgeAnswer(
            _q(type: 'fill_blank', answer: '血红蛋白；红细胞'), '血红蛋白'),
        isFalse,
      );
    });

    test('名解/简答/问答：去标点包含匹配，答案过短判错', () {
      expect(
        QuizService.judgeAnswer(
            _q(type: 'ming_jie', answer: '由原核细胞构成的微生物'),
            '由原核细胞构成的微生物，包括细菌等。'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(
            _q(type: 'jian_da', answer: '蛋白质是生命活动的主要承担者'), '蛋白质'),
        isFalse,
      );
    });

    test('空答案一律判错', () {
      expect(
        QuizService.judgeAnswer(_q(type: 'single_choice', answer: 'A'), ''),
        isFalse,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'fill_blank', answer: 'X'), '   '),
        isFalse,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'ming_jie', answer: 'abcde'), ''),
        isFalse,
      );
    });

    test('判断题：对/错', () {
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '对'), '对'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '错'), '对'),
        isFalse,
      );
    });

    test('判断题：输入归一（√/×/T/F/正确/错误）', () {
      // v1.0.2 完善：√/正确/T/TRUE → 对；×/错误/F/FALSE → 错
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '对'), '√'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '对'), '正确'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '对'), 'T'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '对'), 'true'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '错'), '×'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '错'), '错误'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '错'), 'F'),
        isTrue,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '错'), 'false'),
        isTrue,
      );
      // 否定类不误判为「对」
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '对'), '不正确'),
        isFalse,
      );
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '对'), '不对'),
        isFalse,
      );
      // 无法识别判错
      expect(
        QuizService.judgeAnswer(_q(type: 'true_false', answer: '对'), '是'),
        isFalse,
      );
    });
  });
}
