import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 导出文件落在哪里。
///
/// 为什么要专门挑目录：错题导出是给用户**拿出去用**的（打印纸质题、发同学、
/// 存档），所以要放在用户自己能翻到的位置，而不是应用私有缓存——
/// Android 的 `Directory.systemTemp` 是 `/data/user/0/<包名>/cache`，
/// 普通文件管理器根本进不去，导完就找不着了。
///
///   · Android：应用外部私有目录 `<外部存储>/Android/data/<包名>/files/猫卷导出`
///     （不需要任何存储权限；Android 10 的文件管理器可直接进入，11+ 部分机型
///     需要在文件管理器里开启「显示系统/Android 目录」，也能通过数据线在电脑上看到）
///   · Windows/macOS/Linux：`<文档目录>/猫卷导出`（资源管理器里直接可见）
///   · 插件不可用 / 取不到（单元测试、无外部存储）：回落到系统临时目录
class ExportStorage {
  ExportStorage._();

  /// 单元测试注入：给定则直接用它作为导出目录。
  /// 与 `DatabaseService.overrideDbPath` 同一套路，避免测试依赖 path_provider 插件。
  static String? overrideDirForTest;

  /// 导出目录名（用户可见，给个能认出来的名字）
  static const folderName = '猫卷导出';

  /// 取（必要时创建）导出目录
  static Future<Directory> resolve() async {
    final override = overrideDirForTest;
    if (override != null) return _ensure(Directory(override));
    try {
      final base = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      if (base != null) {
        return _ensure(Directory('${base.path}${Platform.pathSeparator}$folderName'));
      }
    } catch (_) {
      // path_provider 在单元测试里没有平台实现；真实设备上也可能取不到
      // （例如外部存储被卸载），这时候不能让导出整个失败。
    }
    return Directory.systemTemp;
  }

  static Directory _ensure(Directory dir) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 从导出的文件路径里取出「所在文件夹」，用于导出后展示给用户。
  ///
  /// 直接按最后一个分隔符截断，**不重新拼接**：路径里可能是 `/` 也可能是 `\`
  /// （取决于平台与拼接处），重组会把另一种分隔符改掉，展示出来就不是真实路径了。
  static String folderOf(String filePath) {
    final i = filePath.lastIndexOf(RegExp(r'[\\/]'));
    if (i < 0) return filePath; // 只有文件名，没有目录
    if (i == 0) return filePath.substring(0, 1); // 根目录下的文件
    return filePath.substring(0, i);
  }

  /// 从导出的文件路径里取出文件名
  static String fileNameOf(String filePath) =>
      filePath.split(RegExp(r'[\\/]')).last;
}
