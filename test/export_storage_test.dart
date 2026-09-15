import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/export_storage.dart';

/// 导出落点与「保存位置」展示的回归测试。
///
/// 为什么要专门测：导出完要告诉用户文件在哪个文件夹，而用户能不能真的找到，
/// 取决于两件事——文件**确实**写在那个目录里，以及展示的目录字符串**确实**是
/// 文件所在目录（拆路径的参数化写法最容易在 Windows 的反斜杠上出错）。
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mj_export_dir_');
  });

  tearDown(() {
    ExportStorage.overrideDirForTest = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('导出目录', () {
    test('注入目录不存在时会自动创建（首次导出不能失败）', () async {
      final target = '${tmp.path}${Platform.pathSeparator}猫卷导出';
      expect(Directory(target).existsSync(), isFalse);
      ExportStorage.overrideDirForTest = target;

      final dir = await ExportStorage.resolve();
      expect(dir.path, target);
      expect(Directory(target).existsSync(), isTrue,
          reason: '目录要先建出来，否则写文件会抛「系统找不到指定的路径」');
    });

    test('目录名对用户可见（叫「猫卷导出」，不是随机名）', () {
      expect(ExportStorage.folderName, '猫卷导出');
    });
  });

  group('保存位置展示', () {
    test('从文件路径取出所在目录（Windows 反斜杠同样正确）', () {
      expect(ExportStorage.folderOf(r'C:\Users\me\Documents\猫卷导出\错题练习_1.docx'),
          r'C:\Users\me\Documents\猫卷导出');
      expect(ExportStorage.folderOf('/sdcard/Android/data/com.flashcard.app/files/猫卷导出/错题导出_1.json'),
          '/sdcard/Android/data/com.flashcard.app/files/猫卷导出');
      // 混用分隔符时按最后一个切，且保留原有写法（不能把 / 重组成 \）
      expect(ExportStorage.folderOf(r'C:\a/猫卷导出\错题导出_1.json'),
          r'C:\a/猫卷导出');
    });

    test('从文件路径取出文件名', () {
      expect(ExportStorage.fileNameOf(r'C:\a\猫卷导出\错题练习_9.docx'), '错题练习_9.docx');
      expect(ExportStorage.fileNameOf('/a/猫卷导出/错题导出_9.json'), '错题导出_9.json');
      // 只有文件名时不能把整串当目录
      expect(ExportStorage.folderOf('错题导出_1.json'), '错题导出_1.json');
    });
  });
}
