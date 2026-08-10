import 'database_service.dart';

class StatsService {
  final DatabaseService _db = DatabaseService.instance;

  /// 获取首页统计数据
  Future<HomeStats> getHomeStats() async {
    final totalDuration = await _db.getTotalPracticeDuration();
    final totalQuestions = await _db.getTotalQuestionsAnswered();
    final overallAccuracy = await _db.getOverallAccuracy();

    return HomeStats(
      totalDurationSeconds: totalDuration,
      totalQuestions: totalQuestions,
      overallAccuracy: overallAccuracy,
    );
  }

  /// 获取各题库正确率（用于薄弱点分析）
  Future<List<BankAccuracy>> getBankAccuracies() async {
    final data = await _db.getAccuracyByBank();
    return data.map((d) {
      final total = d['total'] as int;
      final correct = d['correct'] as int;
      return BankAccuracy(
        bankId: d['bank_id'] as int,
        bankName: d['bank_name'] as String,
        total: total,
        correct: correct,
        accuracy: total > 0 ? (correct / total) * 100 : 0,
      );
    }).toList();
  }

  /// 周期统计（v1.0.2 统计页）：week / month / all
  Future<PeriodStats> getPeriodStats(String period) async {
    final raw = await _db.getPeriodStats(period);
    final questions = (raw['questions'] as int?) ?? 0;
    final correct = (raw['correct'] as int?) ?? 0;
    final duration = (raw['duration'] as int?) ?? 0;
    return PeriodStats(
      totalQuestions: questions,
      accuracy: questions > 0 ? (correct / questions) * 100 : 0,
      totalDurationSeconds: duration,
    );
  }

  /// 周期内最长连击（连续每天 >= 50 题的最大天数，无记录天中断）
  Future<int> getPeriodLongestStreak(String period) async {
    final now = DateTime.now();
    final int days;
    switch (period) {
      case 'week':
        days = now.weekday;
        break;
      case 'month':
        days = now.day;
        break;
      default:
        days = 3650;
    }
    final daily = await _db.getDailyStats(days);
    var best = 0;
    var run = 0;
    for (final d in daily) {
      if ((d['total'] as int) >= 50) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best;
  }
}

/// 周期统计结果（统计页总览板块）
class PeriodStats {
  final int totalQuestions;
  final double accuracy;
  final int totalDurationSeconds;

  PeriodStats({
    required this.totalQuestions,
    required this.accuracy,
    required this.totalDurationSeconds,
  });

  String get formattedDuration {
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}小时${minutes}分钟';
    if (minutes > 0) return '${minutes}分钟';
    return '${totalDurationSeconds}秒';
  }

  String get formattedAccuracy => '${accuracy.toStringAsFixed(1)}%';
}

class HomeStats {
  final int totalDurationSeconds;
  final int totalQuestions;
  final double overallAccuracy;

  HomeStats({
    required this.totalDurationSeconds,
    required this.totalQuestions,
    required this.overallAccuracy,
  });

  /// v1.0.2 扩展：刷题时长格式。
  /// 24 小时内显示 xx h xx m（如 2 h 35 m）；超过 24 小时显示 xx 天 xx 小时
  String get formattedDuration {
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    if (hours >= 24) {
      final days = hours ~/ 24;
      final remainHours = hours % 24;
      return '$days 天 $remainHours 小时';
    }
    return '$hours h $minutes m';
  }

  String get formattedAccuracy => '${overallAccuracy.toStringAsFixed(1)}%';
}

class BankAccuracy {
  final int bankId;
  final String bankName;
  final int total;
  final int correct;
  final double accuracy;

  BankAccuracy({
    required this.bankId,
    required this.bankName,
    required this.total,
    required this.correct,
    required this.accuracy,
  });

  String get formattedAccuracy => '${accuracy.toStringAsFixed(1)}%';
}
