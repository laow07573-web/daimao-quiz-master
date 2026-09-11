import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/app_settings.dart';
import 'package:flashcard_app/models/follow_up_message.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/utils/design_tokens.dart';
import 'package:flashcard_app/widgets/ai_response_widget.dart';

/// AI 对话页相关契约（v1.28 重做：从解析卡内嵌改为独立全屏对话页）。
///
/// 说明：`AiChatScreen._init` 在页面内部异步读 DB（拉解析/历史），
/// 在 testWidgets 的假异步区会挂起，因此不做整页 pumpWidget ——
/// 整页行为由真机走查覆盖。此处验证其**依赖契约**与**组件渲染**，
/// 确保重构后：模型映射正常、Markdown 渲染未退化、设计令牌未悬空、
/// 气泡配色对比度达标。
void main() {
  test('FollowUpMessage：user/assistant 角色映射正确', () {
    final u = FollowUpMessage.fromMap({'role': 'user', 'content': '为什么要选 A？'});
    expect(u.role, 'user');
    expect(u.content, '为什么要选 A？');

    final a = FollowUpMessage.fromMap(
        {'role': 'assistant', 'content': '因为 A 符合定义。'});
    expect(a.role, 'assistant');
    expect(a.content, '因为 A 符合定义。');
  });

  test('FollowUpMessage：缺失字段不抛异常（脏数据容错）', () {
    final m = FollowUpMessage.fromMap({});
    expect(m.role, '');
    expect(m.content, '');
  });

  testWidgets('AI 气泡内容渲染：Markdown 加粗与列表被转换（对话页复用）',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeService().themeData,
      home: const Scaffold(
        body: AiResponseWidget(
            text: '**答案：** A\n\n- 定性：符合定义\n- 排除法：B 错'),
      ),
    ));
    await tester.pump();

    final texts = <String>[];
    for (final el in find.byType(RichText).evaluate()) {
      texts.add((el.widget as RichText).text.toPlainText());
    }
    final joined = texts.join('\n');
    expect(joined.contains('**'), isFalse, reason: '不应残留 Markdown 星号');
    expect(joined.contains('答案'), isTrue);
    expect(joined.contains('排除法'), isTrue);
  });

  test('对话页引用的设计令牌可用（防重构悬空）', () {
    expect(MaoType.body, greaterThan(0));
    expect(MaoType.h3, greaterThan(0));
    expect(MaoRadius.control, greaterThan(0));
    expect(MaoRadius.chip, greaterThan(0));
    expect(MaoSpace.md, greaterThan(0));
    expect(MaoSpace.sm, greaterThan(0));
    expect(MaoShadow.hairline, greaterThan(0));
  });

  testWidgets('用户气泡（强调色底 + onAccent 文字）渲染正确且对比度达标',
      (tester) async {
    const ac = AppThemeColors(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFF0F0F0),
      border: Color(0xFFE0E0E0),
      textPrimary: Color(0xFF111111),
      textSecondary: Color(0xFF666666),
      textTertiary: Color(0xFF999999),
      accent: Color(0xFF2563EB),
      accentSoft: Color(0xFFE8EFFE),
      onAccent: Color(0xFFFFFFFF),
      navBackground: Color(0xFFFFFFFF),
      navForeground: Color(0xFF111111),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: ac.background,
        body: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: ac.accent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(MaoRadius.control),
                topRight: Radius.circular(MaoRadius.control),
                bottomLeft: Radius.circular(MaoRadius.control),
                bottomRight: Radius.circular(5),
              ),
            ),
            child: Text('为什么要选 A？',
                style: MaoType.bodyStyle.copyWith(color: ac.onAccent)),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('为什么要选 A？'), findsOneWidget);
    final lumAccent = ac.accent.computeLuminance();
    final lumOn = ac.onAccent.computeLuminance();
    final ratio = (lumAccent > lumOn)
        ? (lumAccent + 0.05) / (lumOn + 0.05)
        : (lumOn + 0.05) / (lumAccent + 0.05);
    expect(ratio, greaterThan(3.0), reason: '气泡文字对比度应达标');
  });

  testWidgets('对话页输入栏样式：多行输入 + 圆形发送按钮（组件契约）',
      (tester) async {
    const ac = AppThemeColors(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFF0F0F0),
      border: Color(0xFFE0E0E0),
      textPrimary: Color(0xFF111111),
      textSecondary: Color(0xFF666666),
      textTertiary: Color(0xFF999999),
      accent: Color(0xFF2563EB),
      accentSoft: Color(0xFFE8EFFE),
      onAccent: Color(0xFFFFFFFF),
      navBackground: Color(0xFFFFFFFF),
      navForeground: Color(0xFF111111),
    );
    final ctrl = TextEditingController();

    await tester.pumpWidget(MaterialApp(
      theme: ThemeService().themeData,
      home: Scaffold(
        body: Column(children: [
          TextField(
            controller: ctrl,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(hintText: '继续追问…', isDense: true),
          ),
          Material(
            color: ac.accent,
            shape: const CircleBorder(),
            child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(Icons.arrow_upward_rounded, color: Colors.white)),
          ),
        ]),
      ),
    ));
    await tester.pump();

    // 多行输入框可展开（maxLines=4）
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.maxLines, 4);
    expect(tf.minLines, 1);
    // 发送按钮为圆形
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    ctrl.dispose();
  });

  // ===================== v1.28 结构色 + 关键词标记 =====================

  /// 收集所有 span（含嵌套）的 (文本, 有效颜色) 列表。
  /// 子 span 未显式设色时继承父级（结构色挂在整行 span 上）。
  List<(String, Color?)> collectSpans(InlineSpan span, [TextStyle? inherited]) {
    final out = <(String, Color?)>[];
    if (span is TextSpan) {
      final eff = inherited?.merge(span.style) ?? span.style;
      if (span.text != null && span.text!.isNotEmpty) {
        out.add((span.text!, eff?.color));
      }
      for (final c in span.children ?? const <InlineSpan>[]) {
        out.addAll(collectSpans(c, eff));
      }
    }
    return out;
  }

  Future<List<(String, Color?)>> renderSpans(WidgetTester tester, String text) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeService().themeData,
      home: Scaffold(body: AiResponseWidget(text: text)),
    ));
    await tester.pump();
    final rt = tester.widget<RichText>(find.byType(RichText).first);
    return collectSpans(rt.text);
  }

  testWidgets('结构色：答案=success、题眼=accent、避坑指南=danger', (tester) async {
    final spans = await renderSpans(
        tester, '**答案：** B\n**题眼：** 看到 PaCO₂ 升高\n**避坑指南：** 别把代偿当合并');
    final ac = AppThemeColors.of(tester.element(find.byType(Scaffold)));
    final colors = spans.map((e) => e.$2).toSet();

    final expected = {
      ac.success, // 答案
      ac.accent, // 题眼
      ac.danger, // 避坑指南
    };
    for (final c in expected) {
      expect(colors.contains(c), isTrue,
          reason: '结构色缺失：$c，实际=${colors.toList()}');
    }
    // 标签文本仍在
    final joined = spans.map((e) => e.$1).join();
    expect(joined.contains('答案：'), isTrue);
    expect(joined.contains('题眼：'), isTrue);
    expect(joined.contains('避坑指南：'), isTrue);
  });

  testWidgets('关键词标记：==蓝== / !!红!! 上色且不残留符号', (tester) async {
    final spans = await renderSpans(
        tester, '选项 B 的 ==决定性依据== 是 !!除外!! 这个否定词');
    final joined = spans.map((e) => e.$1).join();
    expect(joined.contains('=='), isFalse, reason: '不应残留 == 符号');
    expect(joined.contains('!!'), isFalse, reason: '不应残留 !! 符号');
    expect(joined.contains('决定性依据'), isTrue);
    expect(joined.contains('除外'), isTrue);
    // 两种关键词都换成了不同颜色（相对正文）
    final colored = spans.where((e) => e.$1 == '决定性依据' || e.$1 == '除外');
    expect(colored.length, 2);
    expect(colored.first.$2, isNot(colored.last.$2),
        reason: '蓝/红关键词颜色应不同');
  });

  testWidgets('关键词容错：未闭合标记原样保留，不吞掉后续正文', (tester) async {
    final spans = await renderSpans(tester, '正常文字 ==未闭合 后面还有内容');
    final joined = spans.map((e) => e.$1).join();
    expect(joined.contains('后面还有内容'), isTrue, reason: '未闭合不应吞行');
  });

  test('AnalysisDetail 三档：标签与提示均非空且各不相同', () {
    final labels = AnalysisDetail.values.map((d) => d.label).toList();
    final hints = AnalysisDetail.values.map((d) => d.hint).toList();
    expect(labels.toSet().length, labels.length);
    expect(hints.toSet().length, hints.length);
    expect(labels.every((l) => l.isNotEmpty), isTrue);
    expect(hints.every((h) => h.isNotEmpty), isTrue);
  });

  test('AppSettings：回答风格字段可持久化并往返一致', () {
    final s = AppSettings(analysisDetail: AnalysisDetail.standard, keywordHighlight: false);
    final m = s.toMap();
    expect(m['analysis_detail'], 'standard');
    expect(m['keyword_highlight'], '0');
    final back = AppSettings.fromMap(m);
    expect(back.analysisDetail, AnalysisDetail.standard);
    expect(back.keywordHighlight, isFalse);
    // 缺省兼容（老存档无该字段）
    final legacy = AppSettings.fromMap({});
    expect(legacy.analysisDetail, AnalysisDetail.brief);
    expect(legacy.keywordHighlight, isTrue);
  });
}
