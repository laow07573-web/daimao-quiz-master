import 'dart:math';

/// FSRS-5 简化实现：Free Spaced Repetition Scheduler
///
/// 参考: https://github.com/open-spaced-repetition/fsrs4anki
///
/// 每道错题维护一个 FSRSCardState，记录：
///   - stability: 记忆稳定性（天），越大 = 忘得越慢
///   - difficulty: 题目难度 (1.0 ~ 10.0，越大越难)
///   - next_review_at: 下次应复习的时间
///
/// 答题后调用 schedule() 更新状态，自动计算下一次复习时间。
class FSRSService {
  FSRSService._();

  /// 请求保留率（目标：90% 的题目在复习时能答对）
  static const double _requestRetention = 0.9;

  /// FSRS-5 默认权重
  static const List<double> _w = [
    0.5701, 1.4436, 4.1383, 10.9353, 5.1442,
    1.2002, 0.6423, 1.3217, 0.0457, 1.5151,
    0.1575, 1.4249, 2.4068, 0.0423, 0.3148,
    1.2502, 0.1652, 0.8310, 1.7699,
  ];

  static final Random _random = Random();

  /// 创建一张新卡的初始 FSRS 状态
  static FSRSCardState initCard(int questionId, DateTime now) {
    // 初始稳定性 ~0.5 天，难度中等偏易
    final initStability = 0.5 + _random.nextDouble() * 0.3;
    final initDifficulty = 4.5 + _random.nextDouble() * 1.0;
    return FSRSCardState(
      questionId: questionId,
      stability: initStability,
      difficulty: initDifficulty,
      reviewCount: 0,
      lastReviewAt: now,
      nextReviewAt: now.add(Duration(hours: (initStability * 24).round())),
    );
  }

  /// 根据评分更新卡的状态
  ///
  /// [rating]: 1=Again(又忘了), 2=Hard(困难), 3=Good(正常), 4=Easy(简单)
  /// [reactionMs]: 答题反应时间（毫秒），用于微调
  static FSRSCardState schedule(
    FSRSCardState card,
    int rating,
    DateTime now, {
    int reactionMs = 3000,
  }) {
    final S = card.stability;
    final D = card.difficulty;
    final elapsedDays = max(0.0,
        now.difference(card.lastReviewAt).inMilliseconds / 86400000.0);
    final R = elapsedDays > 0 && S > 0
        ? exp(log(_requestRetention) * elapsedDays / S)
        : 1.0;

    double newD;
    double newS;

    if (rating == 1) {
      // Again: 稳定性大幅降低，难度增加
      newD = (D + _w[4] * (0.0 - _w[3])).clamp(2.0, 10.0);
      newS = max(S * _w[6], 0.15); // 不低于 0.15 天（≈4~12h 间隔）
    } else {
      // 成功回答：难度向 rating 映射的位置调整
      final ratingNorm = (rating - 1) / 3.0; // 2→0.33, 3→0.66, 4→1.0
      final meanR = _w[7] * exp(_w[8] * (D - _w[3])) /
          (1 + exp(_w[8] * (D - _w[3])));
      newD = (D - _w[5] * (ratingNorm - meanR)).clamp(2.0, 10.0);

      if (rating == 2) {
        // Hard
        newS = S * (1 + _w[9] * (11 - newD) * pow(S, -_w[10]) *
            (exp(_w[11] * (1 - R)) - 1));
        newS = min(newS, S * 1.2); // Hard 上限
      } else {
        // Good / Easy
        newS = S * (1 + _w[9] * (11 - newD) * pow(S, -_w[10]) *
            (exp(_w[11] * (1 - R)) - 1));
        if (rating == 4) {
          newS *= _w[15]; // Easy 加成
        }
      }
    }

    // 限幅
    newS = newS.clamp(0.01, 36500.0);
    newD = newD.clamp(2.0, 10.0);

    final nextInterval = newS *
        (9 * (1 / newD) - 1); // 近似：难度越高间隔越短

    return FSRSCardState(
      questionId: card.questionId,
      stability: newS,
      difficulty: newD,
      reviewCount: card.reviewCount + 1,
      lastReviewAt: now,
      nextReviewAt: now.add(Duration(days: max(1, nextInterval.round()))),
    );
  }

  /// 根据答题正确性 + 反应时间自动推断 FSRS 评分
  ///
  /// 无需用户手动评分，从行为推断：
  ///   答错                   → 1 (Again)
  ///   答对 + 反应 ≥ 10 秒    → 2 (Hard)
  ///   答对 + 反应 3~10 秒    → 3 (Good)
  ///   答对 + 反应 < 3 秒     → 4 (Easy)
  static int inferRating(bool isCorrect, int reactionMs) {
    if (!isCorrect) return 1; // Again
    if (reactionMs < 3000) return 4; // Easy
    if (reactionMs < 10000) return 3; // Good
    return 2; // Hard
  }

  /// 卡片是否到期需要复习
  static bool isDue(FSRSCardState card, DateTime now) {
    return card.nextReviewAt.isBefore(now) ||
        card.nextReviewAt.isAtSameMomentAs(now);
  }
}

/// FSRS 卡片状态（对应数据库 fsrs_cards 表）
class FSRSCardState {
  final int questionId;
  final double stability;
  final double difficulty;
  final int reviewCount;
  final DateTime lastReviewAt;
  final DateTime nextReviewAt;

  const FSRSCardState({
    required this.questionId,
    required this.stability,
    required this.difficulty,
    required this.reviewCount,
    required this.lastReviewAt,
    required this.nextReviewAt,
  });

  Map<String, dynamic> toMap() => {
        'question_id': questionId,
        'stability': stability,
        'difficulty': difficulty,
        'review_count': reviewCount,
        'last_review_at': lastReviewAt.toIso8601String(),
        'next_review_at': nextReviewAt.toIso8601String(),
      };

  factory FSRSCardState.fromMap(Map<String, dynamic> map) {
    return FSRSCardState(
      questionId: map['question_id'] as int,
      stability: (map['stability'] as num).toDouble(),
      difficulty: (map['difficulty'] as num).toDouble(),
      reviewCount: map['review_count'] as int? ?? 0,
      lastReviewAt: DateTime.parse(map['last_review_at'] as String),
      nextReviewAt: DateTime.parse(map['next_review_at'] as String),
    );
  }

  @override
  String toString() =>
      'FSRSCard(qid=$questionId, S=${stability.toStringAsFixed(2)}d, '
      'D=${difficulty.toStringAsFixed(2)}, next=${nextReviewAt.toString().substring(0, 10)})';
}
