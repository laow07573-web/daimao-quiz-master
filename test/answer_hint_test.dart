// 引导文案回归：刷题页未作答提示必须与真实交互一致。
//
// 背景（实机冒烟复现）：所有题型共用「点击选项提交答案，答对自动进入下一题」，
// 但只有单选/判断是点击即提交、答对自动跳题；多选必须选完点「确认提交」，
// 填空/名解/简答/问答必须点「提交答案」。文案与交互不符时，用户会以为
// 页面卡住（多选尤其明显：勾完选项没有任何反应）。
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/utils/format_utils.dart';

void main() {
  test('多选：提示要选完点「确认提交」，不再承诺自动跳题', () {
    final hint = answerHintText('multi_choice');
    expect(hint, contains('确认提交'));
    expect(hint, isNot(contains('自动进入下一题')));
  });

  test('填空/名解/简答/问答：提示填完点「提交答案」', () {
    for (final type in const ['fill_blank', 'ming_jie', 'jian_da', 'jie_da']) {
      final hint = answerHintText(type);
      expect(hint, contains('提交答案'), reason: type);
      expect(hint, isNot(contains('自动进入下一题')), reason: type);
    }
  });

  test('单选/判断（含未知题型兜底）：保留点击即提交的原文案', () {
    for (final type in const ['single_choice', 'true_false', '', 'who_knows']) {
      expect(answerHintText(type), '点击选项提交答案，答对自动进入下一题',
          reason: type);
    }
  });
}
