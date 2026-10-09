import '../models/question.dart';
import '../models/question_image.dart';

/// 题目配图占位符：`{{img:N}}`，N 为题内槽位（0 起）。
/// 取双花括号是因为中文试卷正文里几乎不会出现，AI 也不易误改写。
final RegExp questionImageTokenPattern = RegExp(r'\{\{img:(\d+)\}\}');

/// 抢修归一用的容错形态：`{{img:3}}` / `{{图3}}` / `img:3`。
/// 刻意不含 `[图3]`/`【图3】`——试卷正文里「如[图3]所示」是真实文字，
/// 误认成占位符会吞掉正文。
final RegExp _tolerantTokenPattern = RegExp(
    r'\{\{\s*(?:img|图)\s*:?\s*(\d+)\s*\}\}|(?<![A-Za-z0-9_])img\s*:\s*(\d+)');

/// 题目文本片段：文字段或图片槽位（图文交替的内容流）
sealed class QuestionTextSegment {
  const QuestionTextSegment();
}

class QuestionTextRun extends QuestionTextSegment {
  const QuestionTextRun(this.text);
  final String text;
}

class QuestionImageSlot extends QuestionTextSegment {
  const QuestionImageSlot(this.slot);
  final int slot;
}

/// 把题目文本切成「文字段 ↔ 图片槽位」交替序列（按出现顺序）
List<QuestionTextSegment> splitByImageTokens(String text) {
  final out = <QuestionTextSegment>[];
  var cursor = 0;
  for (final m in questionImageTokenPattern.allMatches(text)) {
    if (m.start > cursor) out.add(QuestionTextRun(text.substring(cursor, m.start)));
    out.add(QuestionImageSlot(int.parse(m.group(1)!)));
    cursor = m.end;
  }
  if (cursor < text.length) out.add(QuestionTextRun(text.substring(cursor)));
  return out;
}

/// 文本中出现的图片槽位（升序去重）
Set<int> imageSlotsIn(String text) {
  return questionImageTokenPattern
      .allMatches(text)
      .map((m) => int.parse(m.group(1)!))
      .toSet();
}

/// 摘要用：去掉占位符（列表行/单行标题里无法内联出图，只留纯文字）
String stripImageTokens(String text) =>
    text.replaceAll(questionImageTokenPattern, '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// 抢修归一：把 AI 改写过的容错形态恢复成规范 `{{img:N}}`
String normalizeImageTokens(String text) {
  return text.replaceAllMapped(_tolerantTokenPattern, (m) {
    final n = m.group(1) ?? m.group(2);
    return '{{img:$n}}';
  });
}

/// 一题的图文重排结果：文本已按题内槽位重编，[images] 为该题配图
typedef QuestionImagesRewrite = ({
  String title,
  List<String> options,
  String? analysis,
  List<QuestionImage> images,
});

/// 把题目的 (title, options, analysis) 里的图片槽位按阅读顺序
/// 重编为题内 0..m-1，并从 [pool]（文档级全局槽位 → 图）产出该题配图。
///
/// [pool] 里没有的槽位仍保留占位（渲染时显示「图片缺失」），绝不静默丢图位。
/// 入口先做 [normalizeImageTokens]，容错形态一并归一。
QuestionImagesRewrite rewriteQuestionImages({
  required String title,
  required List<String> options,
  required String? analysis,
  required Map<int, QuestionImage> pool,
}) {
  var next = 0;
  final images = <QuestionImage>[];

  String mapText(String s) {
    final normalized = normalizeImageTokens(s);
    return normalized.replaceAllMapped(questionImageTokenPattern, (m) {
      final global = int.parse(m.group(1)!);
      final local = next++;
      final src = pool[global];
      if (src != null) images.add(src.asDraftAt(local));
      return '{{img:$local}}';
    });
  }

  return (
    title: mapText(title),
    options: options.map(mapText).toList(),
    analysis: analysis == null ? null : mapText(analysis),
    images: images,
  );
}

/// 编辑保存后的删除清理：把 [deletedSlots] 对应的占位符从所有文本字段清掉。
/// 图片删除即从题目内容中移除（含不可编辑的选项/解析字段）。
({String title, List<String> options, String? analysis}) stripDeletedImageSlots({
  required String title,
  required List<String> options,
  required String? analysis,
  required Set<int> deletedSlots,
}) {
  String strip(String s) {
    var out = s;
    for (final slot in deletedSlots) {
      out = out.replaceAll('{{img:$slot}}', '');
    }
    return out;
  }

  return (
    title: strip(title),
    options: options.map(strip).toList(),
    analysis: analysis == null ? null : strip(analysis),
  );
}

/// 导入物化结果
class MaterializeResult {
  const MaterializeResult({required this.questions, required this.orphans});
  final List<Question> questions;

  /// AI 丢掉占位符、又挂不上题的图（全局槽位 → 图）：预览页手动指派
  final Map<int, QuestionImage> orphans;
}

/// 导入物化：把 AI 解析出的题目（文本带文档级全局 `{{img:N}}`）重编为题内槽位，
/// 并把 [pool] 里的图挂到各题上（图片是题目的一部分，随题走）。
///
/// AI 丢掉占位符的图不静默丢：按 anchor 的期望题序补挂到对应题末，
/// 仍挂不上的留在 [MaterializeResult.orphans]，由预览页手动指派。
MaterializeResult materializeQuestionImages({
  required List<Question> questions,
  required Map<int, QuestionImage> pool,
}) {
  // 「上图所示」版式：图在两题之间时，占位符会以上一题的尾巴收场。
  // 下一题首行提到上图/前图的，把尾巴上的占位符搬到该题最前——
  // 这是文本层的确定性修正，不猜几何（反向的「下图所示」尾巴图保持原题不动）
  final moved = <Question>[];
  for (var i = 0; i < questions.length; i++) {
    var title = questions[i].title;
    if (i + 1 < questions.length &&
        RegExp(r'上图|前图').hasMatch(questions[i + 1].title.split('\n').first)) {
      final trailing = RegExp(r'(?:\{\{img:\d+\}\}\s*)+$');
      final m = trailing.firstMatch(title.trimRight());
      if (m != null) {
        final tokens = m.group(0)!.trim();
        title = title.replaceRange(m.start, m.end, '').trimRight();
        moved.add(questions[i].copyWith(title: title));
        moved.add(questions[i + 1].copyWith(title: '$tokens\n${questions[i + 1].title}'));
        i++; // 下一题已并入处理
        continue;
      }
    }
    moved.add(questions[i].copyWith(title: title));
  }

  final used = <int>{};
  for (final q in moved) {
    used.addAll(imageSlotsIn(q.title));
    for (final o in q.options) {
      used.addAll(imageSlotsIn(o));
    }
    if (q.analysis != null) used.addAll(imageSlotsIn(q.analysis!));
  }

  final out = <Question>[];
  for (final q in moved) {
    final r = rewriteQuestionImages(
      title: q.title,
      options: q.options,
      analysis: q.analysis,
      pool: pool,
    );
    out.add(q.copyWith(
      title: r.title,
      options: r.options,
      analysis: r.analysis,
      images: r.images,
    ));
  }

  final orphans = <int, QuestionImage>{};
  pool.forEach((g, img) {
    if (used.contains(g)) return;
    final ordinal = expectedQuestionIndexFromAnchor(img.anchor);
    if (ordinal == null || ordinal < 0 || ordinal >= out.length) {
      orphans[g] = img;
      return;
    }
    final q = out[ordinal];
    final slot = nextFreeSlot(q);
    out[ordinal] = q.copyWith(
      title: '${q.title}\n{{img:$slot}}',
      images: [...q.images, img.asDraftAt(slot)],
    );
  });
  return MaterializeResult(questions: out, orphans: orphans);
}

/// anchor 里的期望题序（`页码:y:题序` 第三段）
int? expectedQuestionIndexFromAnchor(String? anchor) {
  if (anchor == null) return null;
  final parts = anchor.split(':');
  if (parts.length < 3) return null;
  return int.tryParse(parts[2]);
}

/// 该题下一个可用图片槽位（已用槽位取 max+1；跳过悬空位防串图）
int nextFreeSlot(Question q) {
  var max = -1;
  void scan(String? s) {
    if (s == null) return;
    for (final n in imageSlotsIn(s)) {
      if (n > max) max = n;
    }
  }

  scan(q.title);
  for (final o in q.options) {
    scan(o);
  }
  scan(q.analysis);
  for (final i in q.images) {
    if (i.position > max) max = i.position;
  }
  return max + 1;
}
