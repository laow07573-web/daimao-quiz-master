// 与原版基线做四维对照：组件 / 权限 / 中文文案 / assets
// 用法: dart check.dart <待验证manifest.xml> <待验证strings.txt> <待验证assets.txt>
// 输出: 各维差异；全部为零则输出 PASS
import 'dart:io';

void main(List<String> args) {
  // reference 目录 = 脚本所在目录的上级两级的 reference/
  final refDir = '${File(Platform.script.toFilePath()).parent.path}\\..\\..\\reference';

  final newManifest = File(args[0]).readAsStringSync();
  final newStrings = File(args[1])
      .readAsLinesSync()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final newAssets = File(args[2])
      .readAsLinesSync()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();

  final refManifest = File('$refDir\\manifest_reference.xml').readAsStringSync();
  final refStrings = File('$refDir\\strings_reference.txt')
      .readAsLinesSync()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final refAssets = File('$refDir\\assets_reference.txt')
      .readAsLinesSync()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();

  final results = <String>[];
  var pass = true;

  // 组件/权限维度的已审阅差异白名单（如「局域网同步」新增的 Wi-Fi 权限）。
  // 与文案白名单同构，设 REFCHECK_MERGE=1 时把本轮差异并入。
  final manifestWlFile =
      File('$refDir\\known_manifest_differences.txt');
  final manifestWl = manifestWlFile.existsSync()
      ? manifestWlFile.readAsLinesSync().map((s) => s.trim()).toSet()
      : <String>{};
  final manifestReviewed = <String>{};

  // ---- 1. 组件（activity/service/receiver/provider）----
  final reComp = RegExp(r'android:name="([^"]+)"');
  Set<String> comps(String m) =>
      reComp.allMatches(m).map((e) => e.group(1)!).toSet();
  final refC = comps(refManifest);
  final newC = comps(newManifest);
  final onlyRef = refC.difference(newC).difference(manifestWl);
  final onlyNew = newC.difference(refC).difference(manifestWl);
  manifestReviewed
    ..addAll(refC.difference(newC))
    ..addAll(newC.difference(refC));
  results.add('【组件】原版有新版无: ${onlyRef.isEmpty ? "无" : onlyRef.join(", ")}');
  results.add('【组件】新版有原版无: ${onlyNew.isEmpty ? "无" : onlyNew.join(", ")}');
  if (onlyRef.isNotEmpty || onlyNew.isNotEmpty) pass = false;

  // ---- 2. 权限 ----
  final rePerm = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"');
  Set<String> perms(String m) =>
      rePerm.allMatches(m).map((e) => e.group(1)!).toSet();
  final refP = perms(refManifest);
  final newP = perms(newManifest);
  final onlyRefP = refP.difference(newP).difference(manifestWl);
  final onlyNewP = newP.difference(refP).difference(manifestWl);
  manifestReviewed
    ..addAll(refP.difference(newP))
    ..addAll(newP.difference(refP));
  results.add('【权限】原版有新版无: ${onlyRefP.isEmpty ? "无" : onlyRefP.join(", ")}');
  results.add('【权限】新版有原版无: ${onlyNewP.isEmpty ? "无" : onlyNewP.join(", ")}');
  if (onlyRefP.isNotEmpty || onlyNewP.isNotEmpty) pass = false;
  if (manifestReviewed.isNotEmpty &&
      Platform.environment['REFCHECK_MERGE'] == '1') {
    manifestWl.addAll(manifestReviewed);
    manifestWlFile.writeAsStringSync(
        (manifestWl.toList()..sort()).join('\n'), flush: true);
    results.add('（已将 ${manifestReviewed.length} 条组件/权限差异并入基线 '
        'known_manifest_differences.txt）');
  }

  // ---- 3. 中文文案（去空白包含匹配 + 白名单：只报真正的信号缺失）----
  // 去空白：Dart 字符串插值会把 '已隐藏 X 条' 拆成多段，空白差异不算数
  String norm(String s) => s.replaceAll(RegExp(r'\s'), '');
  final refList = refStrings.map(norm).toSet().toList();
  final newList = newStrings.map(norm).toSet().toList();

  // 白名单：人工确认的已知差异（保留项），不计 FAIL
  final whitelistFile =
      File('$refDir\\known_differences.txt');
  final whitelist = whitelistFile.existsSync()
      ? whitelistFile
          .readAsLinesSync()
          .map((s) => norm(s.trim()))
          .where((s) => s.isNotEmpty)
          .toSet()
      : <String>{};

  // 匹配规则：包含（任意方向）或 公共前缀 + 长度差 <= 4（吸收提取噪音尾缀）
  bool matched(String r, String m) {
    if (m.contains(r) || r.contains(m)) return true;
    final diff = (m.length - r.length).abs();
    if (diff <= 4 && (m.startsWith(r) || r.startsWith(m))) return true;
    return false;
  }

  // 按长度分桶加速（contains 需 m.len >= r.len）
  final byLen = <int, List<String>>{};
  for (final m in newList) {
    (byLen[m.length] ??= []).add(m);
  }

  bool anyMatch(String r) {
    // 前缀匹配候选：长度差 <= 4
    for (var l = r.length - 4; l <= r.length + 4; l++) {
      for (final m in byLen[l] ?? const <String>[]) {
        if (matched(r, m)) return true;
      }
    }
    // 包含匹配候选：m.len >= r.len
    for (var l = r.length; l <= (byLen.keys.isEmpty ? 0 : byLen.keys.reduce((a, b) => a > b ? a : b)); l++) {
      for (final m in byLen[l] ?? const <String>[]) {
        if (m.contains(r)) return true;
      }
    }
    return false;
  }

  final missing = refList.where((r) => !anyMatch(r)).toList()..sort();
  // "多余"判定（我的串在原版中无对应）：反向匹配
  final refByLen = <int, List<String>>{};
  for (final r in refList) {
    (refByLen[r.length] ??= []).add(r);
  }
  bool anyRefMatch(String m) {
    for (var l = m.length - 4; l <= m.length + 4; l++) {
      for (final r in refByLen[l] ?? const <String>[]) {
        if (matched(m, r)) return true;
      }
    }
    for (final r in refList) {
      if (r.contains(m)) return true;
    }
    return false;
  }

  final extra = newList.where((m) => !anyRefMatch(m)).toList()..sort();
  // 噪音过滤：含虚词级常用字才算真实文案
  final particles = '的了是在与或请已将按用点开有无限';
  bool real(String s) {
    var p = 0;
    for (final r in s.runes) {
      if (particles.contains(String.fromCharCode(r))) p++;
    }
    return p >= 1;
  }

  final missingReal = missing.where(real).toList();
  final extraReal = extra.where(real).toList();
  // 基线过滤：已审阅差异（known_differences.txt）不再重复告警；
  // 后续更新只报「基线外的新差异」——保证后续版本严格基于原版演进
  final missingDiff =
      missingReal.where((s) => !whitelist.contains(norm(s))).toList();
  final extraDiff =
      extraReal.where((s) => !whitelist.contains(norm(s))).toList();
  results.add('【文案】原版有新版无(疑似缺口): ${missingReal.length} 条'
      '（已确认白名单 ${missingReal.length - missingDiff.length} 条）');
  for (final s in missingDiff) {
    results.add('  缺: $s');
  }
  results.add('【文案】新版有原版无(疑似多余): ${extraReal.length} 条'
      '（已确认白名单 ${extraReal.length - extraDiff.length} 条）');
  for (final s in extraDiff) {
    results.add('  多: $s');
  }
  if (missingDiff.isNotEmpty || extraDiff.isNotEmpty) pass = false;

  // ---- 4. assets ----
  final onlyRefA = refAssets.difference(newAssets);
  final onlyNewA = newAssets.difference(refAssets);
  results.add('【资源】原版有新版无: ${onlyRefA.isEmpty ? "无" : onlyRefA.join(", ")}');
  results.add('【资源】新版有原版无: ${onlyNewA.isEmpty ? "无" : onlyNewA.join(", ")}');
  if (onlyRefA.isNotEmpty || onlyNewA.isNotEmpty) pass = false;

  results.add(pass ? '>>> PASS：四维对照全部一致' : '>>> FAIL：存在差异，见上方清单');
  // 把本轮已审阅条目并入基线（供下次增量对照）。
  // 默认仅在 PASS 时写回；设 REFCHECK_MERGE=1 可强制合并（用于
  // "本轮差异已人工确认、需要并入白名单"的收尾场景）。
  final forceMerge = Platform.environment['REFCHECK_MERGE'] == '1';
  if ((pass || forceMerge) && missingReal.isNotEmpty) {
    final existing = whitelistFile.existsSync()
        ? whitelistFile.readAsLinesSync().toSet()
        : <String>{};
    existing.addAll(missingReal.map(norm));
    existing.addAll(extraReal.map(norm));
    whitelistFile.writeAsStringSync(
        (existing.toList()..sort()).join('\n'), flush: true);
    results.add('（已将 ${missingReal.length + extraReal.length} 条已审阅差异并入基线 known_differences.txt）');
  }
  stdout.writeln(results.join('\n'));
  // 同时写 UTF-8 报告文件（控制台 GBK 显示会乱码，用文件阅读）
  final reportPath =
      '${File(Platform.script.toFilePath()).parent.path}\\reference_check_report.txt';
  File(reportPath).writeAsStringSync(results.join('\n'), flush: true);
}
