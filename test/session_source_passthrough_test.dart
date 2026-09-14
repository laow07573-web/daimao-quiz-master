import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 会话 source 透传链路：
/// DB 行 → _sessionFromRow → QuizSession.source → 历史记录标签。
///
/// 背景：模拟数据的 mode 是 'single'、真实来源在 source='simulation'。
/// 曾因 _sessionFromRow 重建对象时漏传 source，导致模拟会话全部回落到
/// 'real'，在历史记录里被显示成「单题库」——所以这里逐层锁住。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final p = '${dir.path}/flashcard_app/test_session_source.db';
    DatabaseService.overrideDbPath = p;
    final f = File(p);
    if (await f.exists()) await f.delete();
    DatabaseService.includeSimulatedData = true;
  });
  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    DatabaseService.includeSimulatedData = false;
  });

  test('模拟会话经 getAllSessions 后 source 仍为 simulation', () async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '透传题库', createdAt: now));
    await db.insertQuestions([
      for (var i = 1; i <= 10; i++)
        Question(
            bankId: bankId,
            title: '题$i',
            correctAnswer: 'A',
            options: const ['A', 'B'],
            createdAt: now),
    ]);
    final r = await db.simulateLongTermUse(days: 5);
    expect(r.error, isNull);
    expect(r.records, greaterThan(0));

    final sessions = await db.getAllSessions();
    expect(sessions, isNotEmpty);
    // 关键断言：source 必须透传，不能全部回落成 'real'
    expect(sessions.every((s) => s.source == 'simulation'), isTrue,
        reason: '模拟会话的 source 在行转换中被丢失（回落成 real），'
            '历史记录会把它显示为「单题库」');
    // 且 mode 仍是 single —— 证明「只看 mode」的方案本来就无法区分
    expect(sessions.every((s) => s.mode == 'single'), isTrue);

    // 未包含模拟数据时，这些会话不应出现（隔离契约仍生效）
    DatabaseService.includeSimulatedData = false;
    final realOnly = await db.getAllSessions();
    expect(realOnly, isEmpty);
  });
}
