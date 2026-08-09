import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 调试日志服务 — 单例，内存中累积，可导出为文件
class DebugLogService {
  DebugLogService._();
  static final DebugLogService _instance = DebugLogService._();
  static DebugLogService get instance => _instance;

  final List<_LogEntry> _entries = [];
  bool _enabled = false;

  bool get enabled => _enabled;

  void enable() {
    _enabled = true;
    _log('DEBUG', '日志服务已启用');
  }

  void disable() => _enabled = false;

  void logRawResponse(String endpoint, int statusCode, int byteLength) {
    if (!_enabled) return;
    _log('PIPE:RAW',
        'endpoint=$endpoint  status=$statusCode  bytes=$byteLength');
  }

  void logUtf8Decode(int rawBytes, int decodedChars, String preview) {
    if (!_enabled) return;
    final safePreview =
        preview.length > 120 ? '${preview.substring(0, 120)}…' : preview;
    _log('PIPE:UTF8',
        'rawBytes=$rawBytes  decodedChars=$decodedChars  preview=$safePreview');
  }

  void logSanitize(int beforeLen, int afterLen, int removedCount) {
    if (!_enabled) return;
    _log('PIPE:SANITIZE',
        'before=$beforeLen chars  after=$afterLen chars  removed=$removedCount zero-width chars');
  }

  void logAnswerSubmit({
    required String userAnswer,
    required String correctAnswer,
    required bool isCorrect,
    required String questionType,
    required String questionTitle,
  }) {
    if (!_enabled) return;
    final shortTitle =
        questionTitle.length > 60 ? '${questionTitle.substring(0, 60)}…' : questionTitle;
    _log('PIPE:ANSWER',
        'type=$questionType  userAnswer="$userAnswer"  correctAnswer="$correctAnswer"  isCorrect=$isCorrect  title=$shortTitle');
  }

  void logResultFeedback(String correctDisplay, String userDisplay) {
    if (!_enabled) return;
    _log('PIPE:FEEDBACK',
        'correctDisplay="$correctDisplay"  userDisplay="$userDisplay"');
  }

  void log(String tag, String message) {
    if (!_enabled) return;
    _log(tag, message);
  }

  Future<File> exportToFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File('${dir.path}/debug_log_$timestamp.txt');

    final buffer = StringBuffer();
    buffer.writeln('=== 呆猫刷题宝 调试日志 ===');
    buffer.writeln('导出时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('条目数: ${_entries.length}');
    buffer.writeln('');

    for (final entry in _entries) {
      buffer.writeln(entry.toString());
    }

    await file.writeAsString(buffer.toString(), encoding: utf8);
    _log('DEBUG', '日志已导出到: ${file.path}');
    return file;
  }

  String exportToString() {
    final buffer = StringBuffer();
    buffer.writeln('=== 呆猫刷题宝 调试日志 ===');
    buffer.writeln('导出时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('条目数: ${_entries.length}');
    buffer.writeln('');

    for (final entry in _entries) {
      buffer.writeln(entry.toString());
    }
    return buffer.toString();
  }

  void clear() {
    _entries.clear();
    _log('DEBUG', '日志已清空');
  }

  void _log(String tag, String message) {
    _entries.add(_LogEntry(DateTime.now(), tag, message));
  }
}

class _LogEntry {
  final DateTime time;
  final String tag;
  final String message;

  _LogEntry(this.time, this.tag, this.message);

  @override
  String toString() {
    final ts = time.toIso8601String().substring(11, 23);
    return '[$ts] [$tag] $message';
  }
}
