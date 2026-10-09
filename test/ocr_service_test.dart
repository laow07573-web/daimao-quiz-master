// 端上 OCR 服务的纯逻辑回归（识别本身是平台通道，真机/模拟器验证）。
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/ocr_service.dart';

void main() {
  test('mergePageTexts：页间空行分隔、空页跳过', () {
    final merged = OcrService.mergePageTexts([
      '第一章 绪论\n00001.临床血液学研究的对象是',
      '   ',
      '00002.人体最早的造血器官是',
    ]);
    expect(merged, contains('临床血液学研究的对象是'));
    expect(merged, contains('人体最早的造血器官是'));
    expect('  0002'.trim().isEmpty, isFalse); // 空白页确实被跳过（对照）
    final pages = merged.trim().split('\n\n');
    expect(pages.length, 2, reason: '两页非空内容各自成段');
  });

  test('mergePageTexts：全空输入得到空串（调用方据此走视觉退路）', () {
    expect(OcrService.mergePageTexts(['', '  ', '']).trim(), isEmpty);
  });
}
