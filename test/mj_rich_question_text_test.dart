import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question_image.dart';
import 'package:flashcard_app/widgets/kit/mj_rich_question_text.dart';

/// 图文混排渲染的契约测试——**硬性约束：题库题目带图必须显示出来，
/// 并且作为题目的一部分**。这里钉住的是「占位符处真的出 Image」这件事：
/// 出的是 Image.memory（图内联在内容流里），不是文字占位、不是外挂缩略图。
void main() {
  // 1×1 真 PNG（能被解码，避免测试里落进 errorBuilder）
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

  QuestionImage img(int pos) => QuestionImage(
      position: pos, width: 1, height: 1, content: Uint8List.fromList(png));

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('占位符处内联出图：Image.memory 就在题目内容流里', (tester) async {
    await tester.pumpWidget(wrap(MjRichQuestionText(
      text: '下图所示心电图{{img:0}}最可能的诊断是',
      images: [img(0)],
    )));
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    // 图前后的文字都在（图文交替，不是只有图）
    expect(find.textContaining('下图所示心电图'), findsOneWidget);
    expect(find.textContaining('最可能的诊断是'), findsOneWidget);
  });

  testWidgets('多图按槽位各就各位', (tester) async {
    await tester.pumpWidget(wrap(MjRichQuestionText(
      text: '甲{{img:1}}乙{{img:0}}',
      images: [img(0), img(1)],
    )));
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('缺图槽位显式占位（绝不静默丢图）', (tester) async {
    await tester.pumpWidget(wrap(const MjRichQuestionText(
      text: '见图{{img:0}}结束',
    )));
    expect(find.byType(Image), findsNothing);
    expect(find.text('图片缺失'), findsOneWidget);
  });

  testWidgets('无占位符：纯文本，无图', (tester) async {
    await tester.pumpWidget(wrap(MjRichQuestionText(
      text: '普通题干',
      images: [img(0)],
    )));
    expect(find.byType(Image), findsNothing);
    expect(find.text('普通题干'), findsOneWidget);
  });

  testWidgets('解析区可换文本渲染器（markdown 不受影响，图照样内联）', (tester) async {
    await tester.pumpWidget(wrap(MjRichQuestionText(
      text: '解析甲{{img:0}}解析乙',
      images: [img(0)],
      textBuilder: (context, t) => Text('MD:$t'),
    )));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('MD:解析甲'), findsOneWidget);
    expect(find.text('MD:解析乙'), findsOneWidget);
  });
}
