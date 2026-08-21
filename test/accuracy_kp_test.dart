import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 正确率排行「按知识点」（v1.0.2 用户反馈修复）：
/// 查询返回的键名与 UI 读取键一致（name/total/correct），
/// 空/无效知识点被过滤，不产生 "null" 行。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_accuracy_kp.db';
    DatabaseService.overrideDbPath = dbPath;
    final dbFile = File(dbPath);
    if (await dbFile.exists()) await dbFile.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  Future<int> seedWithAnswers() async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '知识点测试库', createdAt: now));
    await db.insertQuestions([
      Question(
          bankId: bankId,
          title: '题A1',
          options: const ['A', 'B'],
          correctAnswer: 'A',
          knowledgePoint: '解剖学',
          createdAt: now),
      Question(
          bankId: bankId,
          title: '题A2',
          options: const ['A', 'B'],
          correctAnswer: 'A',
          knowledgePoint: '解剖学',
          createdAt: now),
      Question(
          bankId: bankId,
          title: '题B1',
          options: const ['A', 'B'],
          correctAnswer: 'A',
          knowledgePoint: '生理学',
          createdAt: now),
      Question(
          bankId: bankId,
          title: '题C1',
          options: const ['A', 'B'],
          correctAnswer: 'A',
          knowledgePoint: null,
          createdAt: now),
    ]);
    final raw = await db.database;
    final rows = await raw
        .rawQuery('SELECT id, knowledge_point FROM questions ORDER BY id');
    // 解剖学：A1 答对 + A2 答错；生理学：B1 答对；空知识点：C1 答对（应被过滤）
    final records = <Map<String, dynamic>>[];
    for (final r in rows) {
      records.add({
        'question_id': r['id'] as int,
        'user_answer': 'A',
        'is_correct': 1,
        'answered_at': now,
        'source': 'real',
        'hidden': 0,
      });
    }
    records[1]['is_correct'] = 0; // A2 答错
    records[1]['user_answer'] = 'B';
    for (final rec in records) {
      await raw.insert('answer_records', rec);
    }
    return bankId;
  }

  test('按知识点排行：键名归一 + 正确率计算 + 空知识点过滤', () async {
    await seedWithAnswers();
    final rows = await DatabaseService.instance.getAccuracyByKnowledgePoint();

    // 只有两个有效知识点，无 null/空名行
    expect(rows.length, 2);
    for (final r in rows) {
      expect(r.containsKey('name'), isTrue, reason: '必须含 name 键');
      expect(r['name'], isA<String>());
      expect((r['name'] as String).trim(), isNotEmpty,
          reason: '不应出现 null/空名称行');
    }
    final byName = {for (final r in rows) r['name'] as String: r};
    expect(byName['解剖学']!['total'], 2);
    expect(byName['解剖学']!['correct'], 1);
    expect(byName['生理学']!['total'], 1);
    expect(byName['生理学']!['correct'], 1);
  });

  test('归一后 accuracy 正确（UI 读取口径）', () async {
    await seedWithAnswers();
    final rows = await DatabaseService.instance.getAccuracyByKnowledgePoint();
    final normalized = rows.map((k) {
      final total = (k['total'] as num?) ?? 0;
      final correct = (k['correct'] as num?) ?? 0;
      return {
        'name': k['name'],
        'accuracy': total > 0 ? correct / total * 100 : 0.0,
      };
    }).toList();
    final byName = {for (final r in normalized) r['name'] as String: r};
    expect(byName['解剖学']!['accuracy'], 50.0);
    expect(byName['生理学']!['accuracy'], 100.0);
  });
}
