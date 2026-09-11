import '../models/ink_annotation.dart';
import 'database_service.dart';
import 'device_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 手写批注持久化（v1.0.3 手写批注，REQ-006~012）
///
/// 答题后批注按题存 question_annotations 表（DB v11：复合主键
/// (question_id, device_id)）；答题中即时批注（REQ-002~005）为内存态，
/// 不经过本服务。
///
/// 局域网同步（v11）：批注按设备隔离——本机保存的批注带本机
/// `device_id`，同步收到他端批注存其 `device_id` 下，互不覆盖；
/// [load] 只返回本机批注（刷题页只显示本机批注，对他端完全透明）。
class AnnotationService {
  AnnotationService._();
  static final AnnotationService instance = AnnotationService._();

  /// 读取某题的本机批注（他端批注保留在库中但不显示，符合"各自保留"）
  Future<List<InkStroke>> load(int questionId) async {
    final rows = await DatabaseService.instance.getAnnotationsByDevice(
        questionId, await DeviceService.instance.deviceId);
    if (rows.isEmpty) return const [];
    return InkStroke.decodeList(rows.first['data'] as String?);
  }

  /// 保存（空笔迹 = 删本机行，不留空 JSON；不动他端批注）
  Future<void> save(int questionId, List<InkStroke> strokes) async {
    final db = await DatabaseService.instance.database;
    final deviceId = await DeviceService.instance.deviceId;
    if (strokes.isEmpty) {
      await db.delete('question_annotations',
          where: 'question_id = ? AND device_id = ?',
          whereArgs: [questionId, deviceId]);
      return;
    }
    await db.insert(
      'question_annotations',
      {
        'question_id': questionId,
        'device_id': deviceId,
        'data': InkStroke.encodeList(strokes),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 清除某题的本机批注（他端批注各自保留）
  Future<void> clear(int questionId) async {
    final db = await DatabaseService.instance.database;
    await db.delete('question_annotations',
        where: 'question_id = ? AND device_id = ?',
        whereArgs: [questionId, await DeviceService.instance.deviceId]);
  }
}
