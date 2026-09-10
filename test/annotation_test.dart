import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/ink_annotation.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/annotation_service.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/widgets/annotation_controller.dart';

/// 手写批注测试（v1.0.3）：
/// 笔迹模型序列化/命中/平移、持久化往返、空批注不留行、删题库级联清理、DB v10 迁移
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir =
        Directory(Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_annotation.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  group('InkStroke 模型', () {
    test('JSON 序列化往返（含笔型）', () {
      final s = InkStroke(
        pts: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6],
        color: 0xFFE53935,
        width: 3.0,
        penType: PenType.highlighter,
      );
      final back = InkStroke.fromJson(s.toJson());
      expect(back.pts, s.pts);
      expect(back.color, s.color);
      expect(back.width, s.width);
      expect(back.penType, PenType.highlighter);
    });

    test('整组编解码往返 + 损坏数据容错', () {
      final strokes = [
        InkStroke(pts: [0.1, 0.1, 0.2, 0.2], color: 0xFF212121, width: 1.5),
        InkStroke(pts: [0.5, 0.5], color: 0xFF1E88E5, width: 3.0), // 单点笔迹
      ];
      final decoded = InkStroke.decodeList(InkStroke.encodeList(strokes));
      expect(decoded.length, 2); // 单点也是有效笔迹（画圆点）
      expect(decoded[0].pts, [0.1, 0.1, 0.2, 0.2]);
      expect(InkStroke.decodeList('not json'), isEmpty); // 损坏数据不抛
      expect(InkStroke.decodeList(null), isEmpty);
    });

    test('hitTest 命中与容差（像素坐标转归一化）', () {
      final canvas = const Size(400, 800);
      final s = InkStroke(
          pts: [0.5, 0.5, 0.5, 0.6], // 画布上 (200,400)-(200,480)
          color: 0xFF212121,
          width: 3.0);
      expect(s.hitTest(const Offset(200, 420), 12, canvas), isTrue);
      expect(s.hitTest(const Offset(201, 430), 12, canvas), isTrue);
      expect(s.hitTest(const Offset(350, 700), 12, canvas), isFalse); // 远处不命中
      expect(s.hitTest(const Offset(203, 415), 4, canvas), isTrue); // 容差内（距线段 3px）
      expect(s.hitTest(const Offset(215, 415), 4, canvas), isFalse); // 容差外（距线段 15px）
    });

    test('translate 平移并 clamp 到画布内', () {
      final s = InkStroke(
          pts: [0.05, 0.05, 0.95, 0.95], color: 0xFF212121, width: 3.0);
      final moved = s.translate(0.1, -0.2);
      expect(moved.pts[0], closeTo(0.15, 1e-9));
      expect(moved.pts[1], closeTo(0.0, 1e-9)); // clamp 到 0
      expect(moved.pts[2], closeTo(1.0, 1e-9)); // clamp 到 1
      expect(moved.pts[3], closeTo(0.75, 1e-9));
    });
  });

  group('AnnotationController 状态机', () {
    test('绘制：begin/extend/end 生成笔迹，抽稀生效', () {
      final c = AnnotationController();
      c.beginStroke(const Offset(0.1, 0.1), 1.0);
      c.extendStroke(const Offset(0.1, 0.1), 1.0); // 距离过近被抽稀
      c.extendStroke(const Offset(0.5, 0.5), 1.0);
      expect(c.liveStroke, isNotNull);
      c.endStroke();
      expect(c.strokes.length, 1);
      expect(c.strokes.first.pointCount, 2); // 抽稀掉重复点
      c.dispose();
    });

    test('橡皮擦整笔删除 + 选择/移动/删除', () {
      final c = AnnotationController();
      c.loadFrom([
        InkStroke(pts: [0.2, 0.2, 0.4, 0.4], color: 0xFF212121, width: 3.0),
        InkStroke(pts: [0.6, 0.6, 0.8, 0.8], color: 0xFF212121, width: 3.0),
      ]);
      const canvas = Size(400, 400);

      // 橡皮擦：擦第一条
      c.setTool(AnnoTool.eraser);
      expect(c.eraseAt(const Offset(100, 100), canvas), isTrue);
      expect(c.strokes.length, 1);
      expect(c.eraseAt(const Offset(100, 100), canvas), isFalse); // 已无此笔

      // 选择：命中剩下那条
      c.setTool(AnnoTool.select);
      expect(c.selectAt(const Offset(280, 280), canvas), isTrue);
      expect(c.selectedIndex, 0);
      // 拖动平移
      c.moveSelected(const Offset(40, 40), canvas);
      expect(c.strokes[0].pts[0], closeTo(0.7, 1e-9));
      // 删除选中
      c.deleteSelected();
      expect(c.strokes, isEmpty);
      c.dispose();
    });
  });

  group('AnnotationService 持久化', () {
    test('save/load/clear 往返 + 空批注不留行', () async {
      final db = DatabaseService.instance;
      final now = DateTime.now().toIso8601String();
      final bankId = await db.insertBank(QuestionBank(name: '批注库', createdAt: now));
      await db.insertQuestions([
        Question(bankId: bankId, title: 'q', correctAnswer: 'A', createdAt: now),
      ]);
      final qs = await db.getQuestionsByBank(bankId);
      final qid = qs.first.id!;
      final svc = AnnotationService.instance;

      expect(await svc.load(qid), isEmpty); // 初始无批注

      final strokes = [
        InkStroke(pts: [0.1, 0.1, 0.2, 0.2], color: 0xFFE53935, width: 3.0,
            penType: PenType.normal),
        InkStroke(pts: [0.5, 0.5, 0.6, 0.6], color: 0xFF43A047, width: 10.0,
            penType: PenType.highlighter),
      ];
      await svc.save(qid, strokes);
      final loaded = await svc.load(qid);
      expect(loaded.length, 2);
      expect(loaded[0].color, 0xFFE53935);
      expect(loaded[1].penType, PenType.highlighter);

      // 空批注 save = 删行
      await svc.save(qid, const []);
      expect(await svc.load(qid), isEmpty);
      final raw = await (await DatabaseService.instance.database)
          .query('question_annotations');
      expect(raw, isEmpty); // 不留空 JSON 行

      await svc.clear(qid); // clear 幂等
    });

    test('删题库级联清理批注（外键级联 + deleteBank 显式清理）', () async {
      final db = DatabaseService.instance;
      final now = DateTime.now().toIso8601String();
      final bankId = await db.insertBank(QuestionBank(name: '级联库', createdAt: now));
      await db.insertQuestions([
        Question(bankId: bankId, title: 'q', correctAnswer: 'A', createdAt: now),
      ]);
      final qs = await db.getQuestionsByBank(bankId);
      final qid = qs.first.id!;
      await AnnotationService.instance.save(qid, [
        InkStroke(pts: [0.1, 0.1, 0.2, 0.2], color: 0xFF212121, width: 3.0),
      ]);
      expect(await AnnotationService.instance.load(qid), isNotEmpty);

      await db.deleteBank(bankId);
      expect(await AnnotationService.instance.load(qid), isEmpty);
    });

    test('DB v11：新装库含复合主键的 question_annotations 表', () async {
      final db = await DatabaseService.instance.database;
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='question_annotations'");
      expect(tables, isNotEmpty);
      // v11：批注表含 device_id 列（复合主键，按设备隔离）
      final cols = (await db.rawQuery('PRAGMA table_info(question_annotations)'))
          .map((r) => r['name'] as String)
          .toList();
      expect(cols, contains('device_id'));
      final version = await db.rawQuery('PRAGMA user_version');
      expect(version.first.values.first, 11);
    });
  });
}
