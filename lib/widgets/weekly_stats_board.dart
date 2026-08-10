import 'package:flutter/material.dart';
import 'year_heatmap.dart';

/// 首页本周战绩（v1.0.2 对齐原版设计：深色看板）
///
/// 独立深色卡片：背景 #0F1115、卡片 #1E222D、主色 #3B82F6
/// 标题「本周战绩」：4px 蓝色竖条 + 加粗白字
/// 数据卡：本周刷题 / 连续打卡（数值加粗）
/// 主体：月历分页（PageView，每页 3 个月）+ 蓝色四级热力阶梯 + 寒暑假标注 + 图例
/// 「历史报告」：深灰底描边矩形，点击弹近 7 天每日刷题明细
class WeeklyStatsBoard extends StatefulWidget {
  const WeeklyStatsBoard({
    super.key,
    required this.dailyTotals, // key: 'YYYY-MM-DD' -> 刷题数
    required this.streakDays,
    required this.weekTotal,
    this.vacationDays = const {},
    this.onHistoryReport, // v1.0.2 对齐原版：历史报告（近 7 天明细）
  });

  final Map<String, int> dailyTotals;
  final int streakDays;
  final int weekTotal;
  final Set<String> vacationDays;
  final VoidCallback? onHistoryReport;

  @override
  State<WeeklyStatsBoard> createState() => _WeeklyStatsBoardState();
}

class _WeeklyStatsBoardState extends State<WeeklyStatsBoard> {
  // 原版深色看板配色
  static const _bg = Color(0xFF0F1115);
  static const _card = Color(0xFF1E222D);
  static const _blue = Color(0xFF3B82F6);
  static const _textMuted = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：4px 蓝色竖条 + 本周战绩（20px 加粗白字）
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: _blue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '本周战绩',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 数据卡
          Row(
            children: [
              _DarkStat(label: '本周刷题', value: '${widget.weekTotal}', suffix: ' 题'),
              const SizedBox(width: 12),
              _DarkStat(label: '连续打卡', value: '${widget.streakDays}', suffix: ' 天'),
            ],
          ),
          const SizedBox(height: 14),
          // 月历热力图（蓝色四级阶梯）
          YearHeatmap(
            dailyTotals: widget.dailyTotals,
            vacationDays: widget.vacationDays,
            heatColors: const [
              Color(0xFF1E222D), // 空
              Color(0xFF0E4D64), // 少 <50
              Color(0xFF1E7E93), // 达标 50~199
              Color(0xFF2CB1D8), // 多 200+
            ],
          ),
          const SizedBox(height: 12),
          // 历史报告：深灰底描边矩形
          if (widget.onHistoryReport != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onHistoryReport,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _textMuted.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 16, color: _textMuted),
                    const SizedBox(width: 8),
                    const Text(
                      '历史报告',
                      style: TextStyle(fontSize: 13, color: Colors.white),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right, size: 16, color: _textMuted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DarkStat extends StatelessWidget {
  const _DarkStat(
      {required this.label, required this.value, required this.suffix});

  final String label;
  final String value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _WeeklyStatsBoardState._card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _WeeklyStatsBoardState._blue,
                    ),
                  ),
                  TextSpan(
                    text: suffix,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _WeeklyStatsBoardState._textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: _WeeklyStatsBoardState._textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
