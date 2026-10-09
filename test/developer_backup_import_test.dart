import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/screens/backup_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/theme_service.dart';

class _Picker extends FilePicker {
  _Picker(this.result, {this.error});
  final FilePickerResult? result;
  final Object? error;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  late FilePicker original;

  setUp(() => original = FilePicker.platform);
  tearDown(() => FilePicker.platform = original);

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
          ChangeNotifierProvider(create: (_) => ThemeService()),
        ],
        // 2026-10-08：数据库导入/导出已从开发者选项移入普通设置，
        // 现在是独立页面 BackupScreen（设置 → 同步与提醒 → 数据库备份），
        // 因此这里不再需要开发者密码解锁。
        child: const MaterialApp(home: BackupScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapImport(WidgetTester tester) async {
    await tester.tap(find.text('导入数据库备份'));
    await tester.pump();
  }

  testWidgets('picker exception is visible and does not leave busy guard',
      (tester) async {
    FilePicker.platform = _Picker(null, error: StateError('picker failed'));
    await pumpScreen(tester);
    await tapImport(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('打开文件选择器失败'), findsOneWidget);
    // A second attempt is allowed after the failure.
    expect(find.text('导入数据库备份'), findsOneWidget);
  });

  testWidgets('picker cancellation is visible', (tester) async {
    FilePicker.platform = _Picker(null);
    await pumpScreen(tester);
    await tapImport(tester);
    await tester.pumpAndSettle();
    expect(find.text('已取消选择备份文件'), findsOneWidget);
  });

  testWidgets('picker result without local path is visible', (tester) async {
    FilePicker.platform = _Picker(
      FilePickerResult([PlatformFile(name: 'cloud.db', size: 1)]),
    );
    await pumpScreen(tester);
    await tapImport(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('无法获取文件的本地路径'), findsOneWidget);
  });

  testWidgets('valid path reaches destructive confirmation without importing',
      (tester) async {
    FilePicker.platform = _Picker(
      FilePickerResult(
          [PlatformFile(name: 'backup.db', size: 1, path: 'backup.db')]),
    );
    await pumpScreen(tester);
    await tapImport(tester);
    await tester.pumpAndSettle();
    expect(find.text('导入数据库备份'), findsNWidgets(2));
    expect(find.textContaining('覆盖当前所有数据'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    // Leave the destructive confirmation untouched: no database replacement occurs.
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(find.text('已取消导入备份'), findsOneWidget);
  });
}
