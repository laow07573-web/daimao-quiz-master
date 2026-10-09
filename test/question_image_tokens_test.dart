import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_image.dart';
import 'package:flashcard_app/services/bank_file_service.dart';
import 'package:flashcard_app/utils/question_image_tokens.dart';

/// 题目配图占位符与导入物化的回归测试。
///
/// 硬性约束：**题库题目里的图片必须显示出来、作为题目的一部分**。
/// 这一层钉住的是「图片跟得住题」的文本侧机制——槽位重编、丢 token 抢修、
/// 删图清理。这里错一处，图片就会在用户看不见的地方丢失。
void main() {
  Question q({
    String title = '',
    List<String> options = const [],
    String? analysis,
    List<QuestionImage> images = const [],
  }) =>
      Question(
        bankId: 1,
        title: title,
        options: options,
        correctAnswer: 'A',
        analysis: analysis,
        createdAt: '2026-09-23T00:00:00.000',
        images: images,
      );

  QuestionImage img(int position, {String? anchor, List<int> bytes = const [1, 2, 3]}) =>
      QuestionImage(
        position: position,
        width: 100,
        height: 60,
        anchor: anchor,
        content: Uint8List.fromList(bytes),
      );

  group('占位符切分', () {
    test('无占位符：整段文本', () {
      final segs = splitByImageTokens('心电图最可能的诊断是');
      expect(segs, hasLength(1));
      expect((segs.first as QuestionTextRun).text, '心电图最可能的诊断是');
    });

    test('文本-图-文本交替，槽位顺序保留', () {
      final segs = splitByImageTokens('对比下两幅图{{img:3}}与{{img:1}}可知');
      expect(segs, hasLength(5));
      expect((segs[0] as QuestionTextRun).text, '对比下两幅图');
      expect((segs[1] as QuestionImageSlot).slot, 3);
      expect((segs[2] as QuestionTextRun).text, '与');
      expect((segs[3] as QuestionImageSlot).slot, 1);
      expect((segs[4] as QuestionTextRun).text, '可知');
    });

    test('独占一段的占位符（图行）', () {
      final segs = splitByImageTokens('{{img:0}}');
      expect(segs, hasLength(1));
      expect((segs.single as QuestionImageSlot).slot, 0);
    });

    test('槽位集合与摘要去占位符', () {
      expect(imageSlotsIn('a{{img:2}}b{{img:0}}'), {0, 2});
      expect(stripImageTokens('题干 {{img:1}} 结束'), '题干 结束');
    });
  });

  group('抢修归一（容错）', () {
    test('容错形态恢复为规范占位符', () {
      expect(normalizeImageTokens('如{{图:7}}所示'), '如{{img:7}}所示');
      expect(normalizeImageTokens('见 img:12 可知'), '见 {{img:12}} 可知');
    });

    test('正文里的 [图3] 不动——那是真实文字不是占位符', () {
      expect(normalizeImageTokens('如[图3]所示'), '如[图3]所示');
      expect(normalizeImageTokens('见【图2】'), '见【图2】');
    });
  });

  group('题内槽位重编（全局 → 题内）', () {
    test('按阅读序 title → options → analysis 连续编号，图随槽位走', () {
      final pool = {3: img(3), 1: img(1), 7: img(7)};
      final r = rewriteQuestionImages(
        title: '题干见图{{img:3}}',
        options: ['选项{{img:1}}', '无图选项'],
        analysis: '解析图{{img:7}}',
        pool: pool,
      );
      expect(r.title, '题干见图{{img:0}}');
      expect(r.options, ['选项{{img:1}}', '无图选项']);
      expect(r.analysis, '解析图{{img:2}}');
      expect(r.images.map((i) => i.position), [0, 1, 2]);
      expect(r.images.map((i) => i.content), [
        pool[3]!.content,
        pool[1]!.content,
        pool[7]!.content,
      ]);
    });

    test('pool 里没有的槽位保留占位（显示「图片缺失」而不是静默丢）', () {
      final r = rewriteQuestionImages(
        title: '前{{img:0}}后{{img:9}}',
        options: const [],
        analysis: null,
        pool: {0: img(0)},
      );
      expect(r.title, '前{{img:0}}后{{img:1}}');
      expect(r.images, hasLength(1));
      expect(r.images.single.position, 0);
    });

    test('重复占位符各自占一个槽位（不合并、不覆盖）', () {
      final r = rewriteQuestionImages(
        title: '{{img:0}}前{{img:0}}后',
        options: const [],
        analysis: null,
        pool: {0: img(0)},
      );
      expect(r.title, '{{img:0}}前{{img:1}}后');
      expect(r.images, hasLength(2));
    });
  });

  group('删图清理', () {
    test('被删槽位的占位符从题干/选项/解析一并清掉', () {
      final r = stripDeletedImageSlots(
        title: '题干{{img:0}}结束',
        options: ['甲{{img:1}}', '乙{{img:2}}'],
        analysis: '解析{{img:2}}',
        deletedSlots: {1, 2},
      );
      expect(r.title, '题干{{img:0}}结束');
      expect(r.options, ['甲', '乙']);
      expect(r.analysis, '解析');
    });
  });

  group('导入物化（含丢 token 抢修）', () {
    test('正常路径：全局槽位重编 + 图挂到对应题', () {
      final pool = {0: img(0), 1: img(1)};
      final r = materializeQuestionImages(
        questions: [q(title: '一题{{img:0}}'), q(title: '二题{{img:1}}')],
        pool: pool,
      );
      expect(r.orphans, isEmpty);
      expect(r.questions[0].title, '一题{{img:0}}');
      expect(r.questions[1].title, '二题{{img:0}}');
      expect(r.questions[1].images.single.content, pool[1]!.content);
    });

    test('「上图所示」：上一题尾巴上的图搬到下一题最前', () {
      final pool = {0: img(0), 1: img(1)};
      final r = materializeQuestionImages(
        questions: [
          q(title: '一题内容\nA．甲\nB．乙\n{{img:0}}'),
          q(title: '2．如上图所示，病变部位是'),
        ],
        pool: pool,
      );
      expect(r.questions[0].images, isEmpty, reason: '尾巴图已搬走');
      expect(r.questions[1].title.trim(), startsWith('{{img:0}}'));
      expect(r.questions[1].images.map((i) => i.content), [pool[0]!.content]);
    });

    test('「下图所示」尾巴图保持原题（下一题没提上图就不搬）', () {
      final pool = {0: img(0)};
      final r = materializeQuestionImages(
        questions: [
          q(title: '一题\n{{img:0}}'),
          q(title: '2．与上题无关的题'),
        ],
        pool: pool,
      );
      expect(r.questions[0].images, hasLength(1));
      expect(r.questions[1].images, isEmpty);
    });

    test('AI 丢 token：按 anchor 期望题序补挂到题末', () {
      // 图 5 的占位符被 AI 吃掉；anchor 第三段=1 表示本该属于第 2 题
      final pool = {5: img(5, anchor: '1:320.5:1')};
      final r = materializeQuestionImages(
        questions: [q(title: '一题'), q(title: '二题')],
        pool: pool,
      );
      expect(r.orphans, isEmpty);
      expect(r.questions[1].title, contains('{{img:0}}'));
      expect(r.questions[1].images.single.position, 0);
      expect(r.questions[0].images, isEmpty);
    });

    test('期望题序越界：进待指派，不静默丢', () {
      final pool = {5: img(5, anchor: '1:320.5:9')};
      final r = materializeQuestionImages(
        questions: [q(title: '一题')],
        pool: pool,
      );
      expect(r.orphans.keys, {5});
    });

    test('补挂不撞悬空槽位（nextFreeSlot 取 max+1）', () {
      final pool = {5: img(5, anchor: '2:100.0:0')};
      final r = materializeQuestionImages(
        // 原 {{img:3}} 是 AI 留下的悬空引用（无图 → 渲染「图片缺失」）
        questions: [q(title: '题干{{img:3}}')],
        pool: pool,
      );
      // 悬空引用重编为 0（位置保留、渲染缺图占位），补挂图用下一个槽位 1，不串位
      expect(r.questions[0].title, contains('{{img:0}}'));
      expect(r.questions[0].title, contains('{{img:1}}'));
      expect(r.questions[0].images.single.position, 1);
    });

    test('anchor 解析', () {
      expect(expectedQuestionIndexFromAnchor('2:312.5:0'), 0);
      expect(expectedQuestionIndexFromAnchor('1'), isNull);
      expect(expectedQuestionIndexFromAnchor(null), isNull);
      expect(expectedQuestionIndexFromAnchor('1:2:x'), isNull);
    });

    test('nextFreeSlot：无图为 0，有图取 max+1（含文本占位符）', () {
      expect(nextFreeSlot(q(title: 'abc')), 0);
      expect(nextFreeSlot(q(title: '{{img:2}}', images: [img(5)])), 6);
    });
  });

  group('JSON 题库带图往返（bank_file）', () {
    test('images 键解析入题；坏条目跳过不整题报废', () async {
      final tmp = Directory.systemTemp.createTempSync('mj_json_img_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final f = File('${tmp.path}/t.json');
      f.writeAsStringSync(jsonEncode([
        {
          'title': '带图题{{img:0}}',
          'correct_answer': 'A',
          'images': [
            {
              'position': 0,
              'mime': 'image/png',
              'width': 3,
              'height': 2,
              'data_b64': base64Encode(Uint8List.fromList([9, 9])),
            },
            {'position': 1, 'data_b64': '!!不是base64!!'},
          ],
        }
      ]));
      final (groups, err) = await BankFileService.parseJsonFile(f.path);
      expect(err, isNull);
      final qs = groups.values.first;
      expect(qs.single.images, hasLength(1));
      expect(qs.single.images.single.position, 0);
      expect(qs.single.images.single.mime, 'image/png');
      expect(qs.single.images.single.content, [9, 9]);
    });

    test('旧文件（无 images 键）照常导入', () async {
      final tmp = Directory.systemTemp.createTempSync('mj_json_old_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final f = File('${tmp.path}/t.json');
      f.writeAsStringSync(jsonEncode([
        {'title': '普通题', 'correct_answer': 'A'}
      ]));
      final (groups, _) = await BankFileService.parseJsonFile(f.path);
      expect(groups.values.first.single.images, isEmpty);
    });
  });
}
