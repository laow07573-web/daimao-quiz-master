/// v1.0.2 设计审查修复：散落各处的日期键/问候语/时间格式化收敛于此。
/// 任何一处格式漂移都会造成连击/热力图键匹配失效，必须单一来源。
library;

/// 'YYYY-MM-DD' 日期键（连击统计 / 热力图 / 每日明细共用）
String dateKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 按时段问候语（首页 hero / 我的页头部共用）
String greetingNow({DateTime? now}) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 5) return '夜深了，注意休息…';
  if (h < 9) return '早上好！';
  if (h < 12) return '上午好！';
  if (h < 14) return '中午好！';
  if (h < 18) return '下午好！';
  if (h < 23) return '晚上好！';
  return '夜深了，注意休息…';
}

/// 秒 → 'MM:SS'（刷题页计时徽标 / 小结页用时）
String fmtClock(int s) =>
    '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

/// 秒 → 'X分Y秒'（练习结果页）
String fmtDurationCn(int s) => '${s ~/ 60}分${s % 60}秒';

/// FSRS 可见化：相对天数标签（按自然日粒度）。
/// 返回 '已到期N天' / '今天' / '明天' / 'N天后'
String relativeDayLabel(DateTime due, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(due.year, due.month, due.day);
  final diff = d.difference(today).inDays;
  if (diff < 0) return '已到期${-diff}天';
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  return '$diff天后';
}
