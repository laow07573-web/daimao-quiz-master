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

  String get formattedDuration {
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    final seconds = totalDurationSeconds % 60;
    if (hours > 0) {
      return '${hours}小时${minutes}分钟';
    }
    if (minutes > 0) {
      return seconds > 0 ? '${minutes}分${seconds}秒' : '${minutes}分钟';
    }
    return '${seconds}秒';
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
