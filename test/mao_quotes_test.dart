import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/models/app_settings.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/mao_quotes.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/mao_quote_bubble.dart';
import 'package:flashcard_app/widgets/mao_quote_tappable.dart';

/// 2026-10-09 用户需求与纠正：
/// ① 「在首页或者我的页面里点击猫卷logo会触发随机语录，与一言的语录不同」；
/// ② 「语录的展示形式不是这样，而是一个类似于浮空的包含这文字的小弹窗，而且会
///    很快消散，在触发下一条语录的时候会马上消失」；
/// ③ 「在设置里面加入一个老吴模式，开启之后按照上述的操作不会弹出语录，
///    而是播放特定音频」。
///
/// 锁住三件事：气泡会自行消散、新的一条会让旧的**立刻**消失、
/// 老吴模式下不再弹语录。
class _FakeAppState extends ChangeNotifier implements AppState {
  _FakeAppState({bool laoWu = false})
      : _settings = AppSettings(laoWuMode: laoWu);

  final AppSettings _settings;

  @override
  AppSettings get settings => _settings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => MaoQuotes.pick(reset: true));
  tearDown(() {
    MaoQuotes.pick(reset: true);
    MaoQuoteBubble.dismiss();
  });

  test('语录是本地固定集合（与一言的网络内容无关）', () {
    expect(MaoQuotes.quotes, isNotEmpty, reason: '语录集为空时点 Logo 没内容可显示');
    for (final q in MaoQuotes.quotes) {
      expect(q.trim(), isNotEmpty);
    }
  });

  test('录入的是作者原文：34 条，特殊标点与 emoji 原样保留', () {
    // 2026-10-09 由作者给的 DOCX 录入。这条测试防的是「录入时被脚本改写/
    // 丢了特殊字符」——此前踩过脚本写入丢字符的坑。
    expect(MaoQuotes.quotes.length, 34, reason: 'DOCX 里有 34 条非空段落');
    expect(MaoQuotes.quotes.first, '老大老大……');
    expect(MaoQuotes.quotes.last, '莆田公交真的好贵……(悄悄话)');
    // 省略号必须是全角「……」，不是三个点；问号/叹号混用的也照原样
    expect(MaoQuotes.quotes.any((q) => q.contains('...')), isFalse,
        reason: '作者用的是「……」，不要被替换成 ASCII 的三个点');
    for (final must in ['😭', 'こ ↑ こ ↓', '呱?呱！', '9331?!', '325?!', '薯条？!']) {
      expect(MaoQuotes.quotes.any((q) => q.contains(must)), isTrue,
          reason: '原文里的「$must」丢了');
    }
  });

  test('老吴模式的音频集已就位（作者提供了两段）', () {
    expect(LaoWuMode.hasAudio, isTrue, reason: '没有音频时老吴模式点了没反应');
    expect(LaoWuMode.audioAssets, isNotEmpty);
    for (final a in LaoWuMode.audioAssets) {
      expect(a.trim(), isNotEmpty);
    }
  });

  test('连续取音频不会重复播同一段', () {
    if (LaoWuMode.audioAssets.length < 2) return;
    LaoWuMode.pickAudio(reset: true);
    var prev = LaoWuMode.pickAudio(random: Random(1));
    for (var i = 0; i < 20; i++) {
      final next = LaoWuMode.pickAudio(random: Random(i + 2));
      expect(LaoWuMode.audioAssets, contains(next));
      expect(next, isNot(prev), reason: '第 $i 次取到的音频与上一段重复了');
      prev = next;
    }
    LaoWuMode.pickAudio(reset: true);
  });

  testWidgets('两段音频确实被打进了资源包（文件名写错会在这里暴露）', (tester) async {
    for (final a in LaoWuMode.audioAssets) {
      final data = await rootBundle.load('assets/$a');
      expect(data.lengthInBytes, greaterThan(1000),
          reason: 'assets/$a 读不到或内容过小——文件名/声明有问题时，'
              '真机上点 Logo 只会看到「老吴的音频还在路上」');
    }
  });

  test('连续取词不会给出同一条（连点两下不该像没反应）', () {
    if (MaoQuotes.quotes.length < 2) return;
    MaoQuotes.pick(reset: true);
    var prev = MaoQuotes.pick(random: Random(1));
    for (var i = 0; i < 30; i++) {
      final next = MaoQuotes.pick(random: Random(i + 2));
      expect(next, isNot(prev), reason: '第 $i 次取词与上一条重复了');
      prev = next;
    }
  });

  test('取到的永远是集合里的内容', () {
    for (var i = 0; i < 20; i++) {
      expect(MaoQuotes.quotes, contains(MaoQuotes.pick(random: Random(i))));
    }
  });

  Future<void> pumpHost(WidgetTester tester, {bool laoWu = false}) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(
            value: _FakeAppState(laoWu: laoWu)),
        ChangeNotifierProvider<ThemeService>(create: (_) => ThemeService()),
      ],
      child: MaterialApp(
        theme: ThemeService().themeData,
        home: const Scaffold(
          body: Center(
            child: MaoQuoteTappable(box: 42, child: Icon(Icons.pets, size: 42)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 当前屏幕上出现的语录文本（气泡里的那句）
  List<String> visibleQuotes(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .where(MaoQuotes.quotes.contains)
      .toList();

  testWidgets('点 Logo 浮出语录，且会自行消散', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.byType(MaoQuoteTappable));
    await tester.pump(); // 插入 Overlay
    await tester.pump(MaoQuoteBubble.fadeIn);

    expect(MaoQuoteBubble.visible, isTrue);
    expect(visibleQuotes(tester), hasLength(1), reason: '应显示一条语录');

    // 等它自己走完（淡入 + 停留 + 淡出）后必须消失，不能一直挂在屏幕上
    await tester.pump(MaoQuoteBubble.total + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(MaoQuoteBubble.visible, isFalse);
    expect(visibleQuotes(tester), isEmpty);
  });

  testWidgets('触发下一条时，上一条马上消失（屏幕上不留两条）', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.byType(MaoQuoteTappable));
    await tester.pump();
    await tester.pump(MaoQuoteBubble.fadeIn);
    final first = visibleQuotes(tester);

    await tester.tap(find.byType(MaoQuoteTappable));
    await tester.pump();
    final second = visibleQuotes(tester);

    expect(second, hasLength(1), reason: '同时只允许存在一条语录');
    if (MaoQuotes.quotes.length > 1) {
      expect(second, isNot(first), reason: '连续取词不该重复');
    }
  });

  testWidgets('老吴模式：点 Logo 不弹语录', (tester) async {
    await pumpHost(tester, laoWu: true);
    await tester.tap(find.byType(MaoQuoteTappable));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(visibleQuotes(tester), isEmpty, reason: '老吴模式下不该出现随机语录');
  });
}
