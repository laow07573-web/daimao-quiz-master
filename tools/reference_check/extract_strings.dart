// 从 libapp.so (Dart AOT snapshot) 提取干净中文串（UTF-16LE 游程，CJK>=3）
// 双相位扫描：快照字符串不保证 2 字节对齐（存在奇数偏移），单相位会漏串
// 用法: dart extract_strings.dart <libapp.so> <out.txt>
import 'dart:io';

void main(List<String> args) {
  final bytes = File(args[0]).readAsBytesSync();
  final out = StringBuffer();
  final seen = <String>{};

  void flush(StringBuffer cur) {
    if (cur.length >= 4) {
      final s = cur.toString();
      if (seen.add(s)) out.writeln(s);
    }
    cur.clear();
  }

  for (final phase in [0, 1]) {
    final cur = StringBuffer();
    for (var i = phase; i + 1 < bytes.length; i += 2) {
      final u = bytes[i] | (bytes[i + 1] << 8);
      final isText = u >= 0x20 && u <= 0x7E ||
          (u >= 0x4E00 && u <= 0x9FFF) ||
          (u >= 0x3000 && u <= 0x303F) ||
          (u >= 0xFF00 && u <= 0xFFEF) ||
          (u >= 0x2000 && u <= 0x206F) ||
          (u >= 0x00A0 && u <= 0x00FF);
      if (isText) {
        cur.writeCharCode(u);
      } else {
        flush(cur);
      }
    }
    flush(cur);
  }

  final lines = out.toString().split('\n').where((s) {
    var cjk = 0;
    for (final r in s.runes) {
      if (r >= 0x4E00 && r <= 0x9FFF) cjk++;
    }
    return cjk >= 3;
  }).toList()..sort();
  File(args[1]).writeAsStringSync(lines.join('\n'));
  stdout.writeln('extracted ${lines.length} clean CJK strings');
}
