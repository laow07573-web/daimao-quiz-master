import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/widgets/ai_response_widget.dart';

/// AI 回复渲染器（v1.0.2 自研轻量解析）：
/// Markdown 表格块渲染 + 加粗/列表不残留原始语法。
void main() {
  Widget wrap(String text) => MaterialApp(
        home: Scaffold(body: AiResponseWidget(text: text)),
      );

  testWidgets('Markdown 表格渲染为 Table 组件', (tester) async {
    const md = '| 选项 | 说明 |\n|---|---|\n| A | 大分子 |\n| B | 蛋白质 |';
    await tester.pumpWidget(wrap(md));

    expect(find.byType(Table), findsOneWidget);
    // 表头与单元格文本存在
    expect(find.textContaining('选项'), findsOneWidget);
    expect(find.textContaining('大分子'), findsOneWidget);
    // 不残留原始表格语法
    expect(find.textContaining('|'), findsNothing);
    expect(find.textContaining('---'), findsNothing);
  });

  testWidgets('表格后接文本段可正常渲染', (tester) async {
    const md = '| a | b |\n|---|---|\n| 1 | 2 |\n\n后面还有文字。';
    await tester.pumpWidget(wrap(md));

    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('后面还有文字。'), findsOneWidget);
  });

  testWidgets('加粗与列表不残留原始语法', (tester) async {
    const md = '**定性/计算**：内容\n\n- **排除法**：A 错\n- A对：描述';
    await tester.pumpWidget(wrap(md));

    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('- **'), findsNothing);
    expect(find.textContaining('定性/计算'), findsOneWidget);
    expect(find.textContaining('排除法'), findsOneWidget);
  });

  testWidgets('缩进嵌套列表前导 - 被转换', (tester) async {
    const md = '- 排除法\n  - A错：大分子';
    await tester.pumpWidget(wrap(md));

    for (final el in find.byType(RichText).evaluate()) {
      final elText = (el.widget as RichText).text.toPlainText();
      expect(elText.contains('- A错'), isFalse,
          reason: '嵌套列表不应残留 "- " 前缀');
      expect(elText.contains('A错'), isTrue);
    }
  });
}
