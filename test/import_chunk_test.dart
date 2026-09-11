import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/ai_service.dart';

/// AI 导入切块正确性（v1.27）：
/// 用户关切的核心问题——切块不得把题目与答案分开。
/// 验证题目边界感知切块：题干+选项+答案+解析永不跨块、
/// 切点只落在题目之间、内容无丢失、超长单题独占块、无题号文档退路。
void main() {
  /// 构造一道跨多行的完整题目（题干/选项/答案/解析分行）
  String buildQuestion(int n, {int padLines = 0}) {
    final buf = StringBuffer();
    buf.writeln('$n. 这是第 $n 道题的题干描述，通常比较长？');
    buf.writeln('A. 选项甲的内容');
    buf.writeln('B. 选项乙的内容');
    buf.writeln('C. 选项丙的内容');
    buf.writeln('D. 选项丁的内容');
    for (var i = 0; i < padLines; i++) {
      buf.writeln('这是第 $n 题的补充说明行 $i，用于撑大题目块体积。');
    }
    buf.writeln('答案：B');
    buf.writeln('解析：这是第 $n 题的解析，解释为什么选 B。');
    return buf.toString();
  }

  group('题目边界感知切块', () {
    test('题干与答案永不跨块：每道题的全部行都在同一块内', () {
      // 10 道题，每道跨 8 行；用很小的 maxChars 强制产生多个块
      final text = List.generate(10, (i) => buildQuestion(i + 1)).join('\n');
      final chunks =
          AIService.splitTextIntoQuestionChunks(text, maxChars: 300);

      expect(chunks.length, greaterThan(1), reason: '小 maxChars 应切出多块');

      // 核心断言：每道题的题干行与答案行必须落在同一块
      for (var n = 1; n <= 10; n++) {
        final titleLine = '$n. 这是第 $n 道题';
        final answerLine = '答案：B'; // 答案文本相同，用解析行区分题号
        final analysisLine = '这是第 $n 题的解析';
        final titleChunkIdx = chunks.indexWhere((c) => c.contains(titleLine));
        final analysisChunkIdx =
            chunks.indexWhere((c) => c.contains(analysisLine));
        expect(titleChunkIdx, isNot(-1), reason: '第 $n 题题干丢失');
        expect(analysisChunkIdx, isNot(-1), reason: '第 $n 题解析丢失');
        expect(titleChunkIdx, analysisChunkIdx,
            reason: '第 $n 题的题干与答案/解析被切到了不同块');
        // 该题所在块包含答案行（同块内必然有「答案：B」）
        expect(chunks[titleChunkIdx].contains(answerLine), isTrue,
            reason: '第 $n 题所在块缺少答案行');
      }
    });

    test('切点只落在题目之间：除首块外每块以题目起始行开头', () {
      final text = List.generate(8, (i) => buildQuestion(i + 1)).join('\n');
      final chunks =
          AIService.splitTextIntoQuestionChunks(text, maxChars: 250);
      expect(chunks.length, greaterThan(1));
      for (var i = 1; i < chunks.length; i++) {
        final firstLine = chunks[i].split('\n').first;
        expect(RegExp(r'^\s*\d+[\.、．\)）]').hasMatch(firstLine), isTrue,
            reason: '第 ${i + 1} 块不是以题目起始行开头（切进了题目中间）：'
                '$firstLine');
      }
    });

    test('内容无丢失：全部题干恰好各出现一次', () {
      final text = List.generate(6, (i) => buildQuestion(i + 1)).join('\n');
      final chunks =
          AIService.splitTextIntoQuestionChunks(text, maxChars: 400);
      final joined = chunks.join('\n');
      for (var n = 1; n <= 6; n++) {
        final marker = '这是第 $n 道题的题干';
        expect('$joined'.split(marker).length - 1, 1,
            reason: '第 $n 题题干应恰好出现一次（实际 ${'$joined'.split(marker).length - 1}）');
      }
    });

    test('文档头并入第一块（保留大题说明上下文）', () {
      final text = '医学基础模拟卷\n三、单选题（每题 1 分）\n'
          '${buildQuestion(1)}\n${buildQuestion(2)}';
      final chunks =
          AIService.splitTextIntoQuestionChunks(text, maxChars: 400);
      expect(chunks.first.contains('医学基础模拟卷'), isTrue);
      expect(chunks.first.contains('三、单选题'), isTrue);
      expect(chunks.first.contains('1. 这是第 1 道题'), isTrue);
    });

    test('单个超长题目独占一块，不被切碎', () {
      final big = buildQuestion(1, padLines: 200); // 远超 maxChars
      final text = '$big\n${buildQuestion(2)}';
      final chunks =
          AIService.splitTextIntoQuestionChunks(text, maxChars: 500);
      // 大题完整出现在某一块中（含其答案与解析）
      final bigChunk = chunks.firstWhere(
          (c) => c.contains('这是第 1 道题的题干'),
          orElse: () => '');
      expect(bigChunk, isNotEmpty);
      expect(bigChunk.contains('这是第 1 题的解析'), isTrue,
          reason: '超长题目的答案/解析必须与题干同块');
      // 大题不与第 2 题混块（体积超限时独占）
      expect(bigChunk.contains('这是第 2 道题的题干'), isFalse);
    });

    test('无题号文档退回按段切块（不抛错、内容不丢）', () {
      final text = List.generate(30, (i) => '无编号段落文本第 $i 行。').join('\n');
      final chunks =
          AIService.splitTextIntoQuestionChunks(text, maxChars: 100);
      expect(chunks, isNotEmpty);
      final joined = chunks.join('\n');
      expect(joined.contains('无编号段落文本第 0 行'), isTrue);
      expect(joined.contains('无编号段落文本第 29 行'), isTrue);
    });

    test('兼容多种题号格式：1、/（1）/第1题/【第1题】均为边界', () {
      final text = '1、第一题题干？\n答案：A\n'
          '（2）第二题题干？\n答案：B\n'
          '第3题 第三题题干？\n答案：对\n'
          '【第4题】第四题题干？\n答案：C';
      final chunks =
          AIService.splitTextIntoQuestionChunks(text, maxChars: 25);
      expect(chunks.length, 4, reason: '四种题号格式各切一块（每块≤25字装不下两题）');
      expect(chunks[0].contains('答案：A'), isTrue);
      expect(chunks[1].contains('答案：B'), isTrue);
      expect(chunks[2].contains('答案：对'), isTrue);
      expect(chunks[3].contains('答案：C'), isTrue);
    });
  });
}
