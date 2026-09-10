import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/ai_service.dart';

/// v1.27 导入截断修复验证：
/// 用户导入大题库时报「响应不是合法 JSON（Unexpected end of input）」——
/// 根因是单块题目太多、AI 输出 JSON 撞 max_tokens 上限被截断。
/// 修复三层：分块 7000→2000 字、max_tokens 4096→8192、截断抢修挽救前部。
void main() {
  group('截断抢修（repairTruncatedJson）', () {
    String questionJson(int i, {bool complete = true}) {
      final base = '{"title": "题目 $i？", "options": ["甲", "乙", "丙", "丁"], '
          '"correct_answer": "A", "question_type": "single_choice", '
          '"analysis": "", "knowledge_point": "微生物学"}';
      return complete ? base : base.substring(0, base.length - 20); // 截断在第 4 题内部
    }

    test('截断在第 4 题内部：挽救前 3 道完整题目', () {
      final truncated = '{"questions": ['
          '${questionJson(1)}, ${questionJson(2)}, ${questionJson(3)}, '
          '${questionJson(4, complete: false)}';
      final repaired = AIService.repairTruncatedJson(truncated);
      expect(repaired, isNotNull);
      final qs = repaired!['questions'] as List;
      expect(qs.length, 3);
      expect(qs[0]['title'], '题目 1？');
      expect(qs[2]['correct_answer'], 'A');
    });

    test('截断在完整题目后的逗号处：全部完整题目获救', () {
      final truncated =
          '{"questions": [${questionJson(1)}, ${questionJson(2)},';
      final repaired = AIService.repairTruncatedJson(truncated);
      expect(repaired, isNotNull);
      expect((repaired!['questions'] as List).length, 2);
    });

    test('带 ```json 围栏的截断输出同样可抢修', () {
      final truncated = '```json\n{"questions": [${questionJson(1)}, '
          '${questionJson(2, complete: false)}\n';
      final repaired = AIService.repairTruncatedJson(truncated);
      expect(repaired, isNotNull);
      expect((repaired!['questions'] as List).length, 1);
    });

    test('无可挽救内容（截在第一个题目内部且无完整对象）：返回 null', () {
      final repaired = AIService.repairTruncatedJson('{"questions": [{"title": "题');
      expect(repaired, isNull);
    });
  });

  group('分块上限（防输出撞顶）', () {
    test('长文档：每块 ≤ 2000 字且题目完整不被切断', () {
      // 构造 30 道题（含选项/答案行），总量远超 2000 字
      final buf = StringBuffer('第一章 概论\n一、单项选择题\n');
      for (var i = 1; i <= 30; i++) {
        buf.writeln('$i. 这是第 $i 道题的题干，描述微生物学相关内容？');
        buf.writeln('A. 选项甲的内容说明');
        buf.writeln('B. 选项乙的内容说明');
        buf.writeln('C. 选项丙的内容说明');
        buf.writeln('D. 选项丁的内容说明');
        buf.writeln('E. 选项戊的内容说明');
        buf.writeln('答案：A');
      }
      final chunks = AIService.splitTextIntoQuestionChunks(buf.toString());
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(2000),
            reason: '每块必须 ≤ 2000 字（防输出撞模型上限）');
      }
      // 全部 30 道题都在（内容无丢失）
      final joined = chunks.join('\n');
      for (var i = 1; i <= 30; i++) {
        expect(joined.contains('这是第 $i 道题'), isTrue);
      }
    });

    test('单题超过 2000 字（长问答）：独占一块不被切碎', () {
      final longAnswer = '答案要点：${'内容填充。' * 450}'; // 约 2250 字，超过块上限。
      final text = '1. 大型简答题题干？\n$longAnswer\n2. 下一题？\n答案：B';
      final chunks = AIService.splitTextIntoQuestionChunks(text);
      expect(chunks.length, 2);
      expect(chunks[0].contains('答案要点'), isTrue);
      expect(chunks[1].contains('下一题'), isTrue);
    });
  });

  group('输出上限自适应降级（换模型不撞墙）', () {
    test('识别常见「超过输出上限」错误文案', () {
      // OpenAI 兼容接口典型报错（max_tokens 超模型上限）
      expect(
          AIService.isTokenLimitError(
              '{"error":{"message":"This request would exceed your '
              'max_tokens limit of 4096"}}'),
          isTrue);
      expect(
          AIService.isTokenLimitError(
              'maximum context length is 8192 tokens, too many tokens'),
          isTrue);
      // 普通错误不误判。
      expect(AIService.isTokenLimitError('Invalid API key provided'), isFalse);
      expect(AIService.isTokenLimitError('network timeout'), isFalse);
    });
  });
}
