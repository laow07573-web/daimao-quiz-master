import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 调试日志服务 — 单例，内存中累积，可导出为文件。
/// v1.0.2 设计审查修复：环形缓冲 500 条上限（此前无限追加，
/// 长时间开启内存持续增长；导出文件含作答内容，分享前请知悉）
class DebugLogService {
  DebugLogService._();
  static final DebugLogService _instance = DebugLogService._();
  static DebugLogService get instance => _instance;

  /// 环形缓冲上限：保留最近 500 条，超出丢弃最旧
  static const int _maxEntries = 500;

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
    buffer.writeln('=== 猫卷 调试日志 ===');
    buffer.writeln('导出时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('条目数: ${_entries.length}');
    // v1.0.2 七项改进：导出脱敏（作答内容与 AI 响应原文已隐藏）
    buffer.writeln('已脱敏：作答内容与 AI 响应已隐藏');
    buffer.writeln('');

    for (final entry in _entries) {
      buffer.writeln(_redact(entry.toString()));
    }

    await file.writeAsString(buffer.toString(), encoding: utf8);
    _log('DEBUG', '日志已导出到: ${file.path}');
    return file;
  }

  String exportToString() {
    final buffer = StringBuffer();
    buffer.writeln('=== 猫卷 调试日志 ===');
    buffer.writeln('导出时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('条目数: ${_entries.length}');
    // v1.0.2 七项改进：导出脱敏（作答内容与 AI 响应原文已隐藏）
    buffer.writeln('已脱敏：作答内容与 AI 响应已隐藏');
    buffer.writeln('');

    for (final entry in _entries) {
      buffer.writeln(_redact(entry.toString()));
    }
    return buffer.toString();
  }

  /// v1.0.2 七项改进：导出脱敏——隐藏作答内容与 AI 响应原文
  static String _redact(String line) {
    return line
        .replaceAll(RegExp(r'userAnswer="[^"]*"'), 'userAnswer="***"')
        .replaceAll(RegExp(r'correctAnswer="[^"]*"'), 'correctAnswer="***"')
        .replaceAll(RegExp(r'userDisplay="[^"]*"'), 'userDisplay="***"')
        .replaceAll(RegExp(r'correctDisplay="[^"]*"'), 'correctDisplay="***"')
        .replaceAll(RegExp(r'preview=[^ ]+'), 'preview=***');
  }

  void clear() {
    _entries.clear();
    _log('DEBUG', '日志已清空');
  }

  void _log(String tag, String message) {
    _entries.add(_LogEntry(DateTime.now(), tag, message));
    // v1.0.2 设计审查修复：环形缓冲，超出上限丢弃最旧条目
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
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
