import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/bank_file_service.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/doc_parser_service.dart';

/// 导入相关测试（v1.0.2）：
/// - JSON 分组建库
/// - DOCX 多选答案归一（A、C → A,C）
/// - DOCX 合并行选项拆回
/// - deleteBank 级联清理
Directory tmpDir() =>
    Directory(Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);

void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    // 每次测试使用独立数据库文件（多测试文件并行隔离）
    final dir = tmpDir();
    final dbPath = '${dir.path}/flashcard_app/test_import.db';
    DatabaseService.overrideDbPath = dbPath;
    final dbFile = File(dbPath);
    if (await dbFile.exists()) await dbFile.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  /// 构造最小 docx（word/document.xml 段落）
  Future<String> writeDocx(List<String> paragraphs) async {
    final dir = tmpDir();
    final path = '${dir.path}/test_${DateTime.now().microsecondsSinceEpoch}.docx';
    final runs = paragraphs.map((p) {
      return '<w:p><w:r><w:t xml:space="preserve">$p</w:t></w:r></w:p>';
    }).join();
    final docXml = '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$runs</w:body></w:document>';
    final archive = Archive()
      ..addFile(ArchiveFile(
          '[Content_Types].xml', 0,
          utf8.encode(
              '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
              '<Default Extension="xml" ContentType="application/xml"/>'
              '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
              '</Types>')))
      ..addFile(ArchiveFile('word/document.xml', 0, utf8.encode(docXml)));
    final bytes = ZipEncoder().encode(archive)!;
    await File(path).writeAsBytes(bytes);
    return path;
  }

  group('DOCX 解析修复', () {
    test('多选答案归一：A、C → A,C', () async {
      final path = await writeDocx([
        '1. 以下哪些属于血细胞？',
        'A. 红细胞',
        'B. 白细胞',
        'C. 血小板',
        'D. 肝细胞',
        '答案：A、C',
      ]);
      final questions = await DocParserService.parseFileInIsolate(path, 1);
      expect(questions.length, 1);
      expect(questions.first.correctAnswer, 'A,C');
      expect(questions.first.questionType, 'multi_choice');
    });

    test('合并行选项拆回：一行多选项', () async {
      final path = await writeDocx([
        '2. 蛋白质的基本单位是？',
        'A. 氨基酸 B. 核苷酸 C. 葡萄糖 D. 脂肪酸',
        '答案：A',
      ]);
      final questions = await DocParserService.parseFileInIsolate(path, 1);
      expect(questions.length, 1);
      final q = questions.first;
      expect(q.options.length, 4, reason: '一行多选项应拆为 4 个选项');
      expect(q.options.first, '氨基酸');
      expect(q.correctAnswer, 'A');
    });

    test('普通换行选项不受影响', () async {
      final path = await writeDocx([
        '3. 血液中运输氧气的细胞是？',
        'A. 红细胞',
        'B. 白细胞',
        'C. 血小板',
        '答案：A',
      ]);
      final questions = await DocParserService.parseFileInIsolate(path, 1);
      expect(questions.first.options.length, 3);
      expect(questions.first.correctAnswer, 'A');
    });
  });

  group('JSON 分组建库', () {
    test('对象分组 → 多个题库', () async {
      final path =
          '${tmpDir().path}/groups_${DateTime.now().microsecondsSinceEpoch}.json';
      await File(path).writeAsString(jsonEncode({
        '临床检验': [
          {
            'title': '白细胞正常值',
            'options': ['A', 'B', 'C', 'D'],
            'correct_answer': 'A',
            'knowledge_point': '血常规',
          },
          {
            'title': '多选归一题',
            'options': ['x', 'y'],
            'answer': 'A、C',
            'type': 'multi_choice',
          },
        ],
        '生化检验': [
          {'title': '血糖正常值', 'correct_answer': '3.9-6.1', 'type': 'fill_blank'},
        ],
      }));
      final (banks, questions, err, renamed) =
          await BankFileService.importJsonFile(path);
      expect(err, isNull);
      expect(renamed, 0);
      expect(banks, 2);
      expect(questions, 3);
      final all = await DatabaseService.instance.getAllBanks();
      expect(all.map((b) => b.name).toSet(),
          {'临床检验', '生化检验'});
      final jc = all.firstWhere((b) => b.name == '临床检验');
      final qs = await DatabaseService.instance.getQuestionsByBank(jc.id!);
      expect(qs.length, 2);
      expect(qs[1].correctAnswer, 'A,C'); // 多选归一
      expect(qs[0].knowledgePoint, '血常规');
    });

    test('数组 → 单题库（以文件名命名）', () async {
      final path =
          '${tmpDir().path}/single_bank_${DateTime.now().microsecondsSinceEpoch}.json';
      await File(path).writeAsString(jsonEncode([
        {'title': '题一', 'correct_answer': 'A'},
        {'title': '题二', 'correct_answer': 'B'},
      ]));
      final (banks, questions, err, renamed) =
          await BankFileService.importJsonFile(path);
      expect(err, isNull);
      expect(renamed, 0);
      expect(banks, 1);
      expect(questions, 2);
      final all = await DatabaseService.instance.getAllBanks();
      expect(all.first.name, contains('single_bank'));
    });
  });

  group('deleteBank 级联', () {
    test('删题库清理题目/答案记录/错题收藏', () async {
      final db = DatabaseService.instance;
      final now = DateTime.now().toIso8601String();
      final bankId = await db.insertBank(
          QuestionBank(name: '待删题库', createdAt: now));
      final q = Question(
          bankId: bankId, title: 't', correctAnswer: 'A', createdAt: now);
      await db.insertQuestions([q]);
      final qs = await db.getQuestionsByBank(bankId);
      await db.addToErrorBook(qs.first.id!);
      await db.deleteBank(bankId);
      expect((await db.getAllBanks()).length, 0);
      expect(await db.getFullErrorCount('all'), 0);
    });
  });
}
