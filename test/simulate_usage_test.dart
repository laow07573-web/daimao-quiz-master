import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 模拟长期使用：幂等性测试（LOCALAPPDATA 隔离环境下运行）
void main() {
  setUp(() async {
    // 每个用例独立数据库
    await DatabaseService.instance.close();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  test('simulateLongTermUse 幂等：重复调用数据量不变', () async {
    final db = DatabaseService.instance;

    await db.simulateLongTermUse();
    final banksAfter1 = (await db.getAllBanks()).length;
    final records1 = await db.getTotalQuestionsAnswered();
    final sessions1 = (await db.getAllSessions()).length;

    await db.simulateLongTermUse();
    final banksAfter2 = (await db.getAllBanks()).length;
    final records2 = await db.getTotalQuestionsAnswered();
    final sessions2 = (await db.getAllSessions()).length;

    expect(banksAfter2, banksAfter1);
    expect(records2, records1);
    expect(sessions2, sessions1);
    expect(records1, greaterThan(0));
    expect(await db.getSetting('sim_done'), '1');
  });

  test('deleteBank 显式清理 answer_records', () async {
    final db = DatabaseService.instance;
    await db.simulateLongTermUse();
    final banks = await db.getAllBanks();
    final simBank = banks.firstWhere((b) => b.name == '模拟题库');
    final before = await db.getTotalQuestionsAnswered();
    expect(before, greaterThan(0));
    await db.deleteBank(simBank.id!);
    final after = await db.getTotalQuestionsAnswered();
    expect(after, 0); // 模拟数据外的记录也被级联清理
    expect((await db.getAllBanks()).any((b) => b.name == '模拟题库'), isFalse);
  });
}
