import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/fsrs_service.dart';

/// FSRS 复习细化测试（error_refinement）：
/// - 错题（rating 1）间隔大幅缩短
/// - 答对后间隔增长
/// - inferRating 按反应时间分档
/// - isDue 判断
void main() {
  group('FSRSService 间隔重复', () {
    test('首次答错 → 间隔 ≈ 1 天（最紧）', () {
      final now = DateTime(2026, 8, 1, 10);
      final card = FSRSService.initCard(1, now);
      final refined = FSRSService.schedule(card, 1, now); // Again
      final interval = refined.nextReviewAt.difference(now).inDays;
      expect(interval, greaterThanOrEqualTo(1));
      expect(interval, lessThanOrEqualTo(2));
    });

    test('答对（Good）→ 稳定性比 Again 更高', () {
      final now = DateTime(2026, 8, 1, 10);
      final card = FSRSService.initCard(2, now);
      final again = FSRSService.schedule(card, 1, now);
      final good = FSRSService.schedule(card, 3, now);
      // 首次间隔可能都被钳制到 1 天，用稳定性验证评级方向
      expect(good.stability, greaterThan(again.stability));
    });

    test('连续答对间隔单调增长（复习次数越多间隔越长）', () {
      final now = DateTime(2026, 8, 1, 10);
      var card = FSRSService.initCard(3, now);
      final intervals = <int>[];
      for (var i = 0; i < 3; i++) {
        card = FSRSService.schedule(card, 3, now);
        intervals.add(card.nextReviewAt.difference(now).inDays);
      }
      expect(intervals[0], lessThanOrEqualTo(intervals[1]));
      expect(intervals[1], lessThanOrEqualTo(intervals[2]));
      expect(intervals[2], greaterThanOrEqualTo(intervals[0]));
    });

    test('inferRating：错→1；快答对→4；慢答对→2', () {
      expect(FSRSService.inferRating(false, 5000), 1);
      expect(FSRSService.inferRating(true, 2000), 4); // <3s
      expect(FSRSService.inferRating(true, 5000), 3); // <10s
      expect(FSRSService.inferRating(true, 15000), 2); // >=10s
    });

    test('isDue：到期/未到期判断', () {
      final now = DateTime(2026, 8, 1, 10);
      final due = FSRSCardState(
        questionId: 1,
        stability: 1,
        difficulty: 5,
        reviewCount: 1,
        lastReviewAt: now,
        nextReviewAt: now.subtract(const Duration(days: 1)),
      );
      expect(FSRSService.isDue(due, now), isTrue);
      final notDue = FSRSCardState(
        questionId: 2,
        stability: 1,
        difficulty: 5,
        reviewCount: 1,
        lastReviewAt: now,
        nextReviewAt: now.add(const Duration(days: 5)),
      );
      expect(FSRSService.isDue(notDue, now), isFalse);
    });

    test('难度与稳定性边界钳制', () {
      final now = DateTime(2026, 8, 1, 10);
      var card = FSRSService.initCard(4, now);
      for (var i = 0; i < 20; i++) {
        card = FSRSService.schedule(card, 1, now); // 连续错
      }
      expect(card.difficulty, lessThanOrEqualTo(10.0));
      expect(card.difficulty, greaterThanOrEqualTo(2.0));
      expect(card.stability, greaterThanOrEqualTo(0.01));
    });
  });
}
