import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_chat/core/utils/formatters.dart';

void main() {
  test('compact numbers', () {
    expect(Fmt.compact(999), '999');
    expect(Fmt.compact(1000), '1K');
    expect(Fmt.compact(1500), '1.5K');
    expect(Fmt.compact(3400000), '3.4M');
  });

  group('RankingPeriod (must match Cloud Functions periodIds)', () {
    // 2026-09-23 is a Wednesday; its ISO week starts Monday 2026-09-21.
    final d = DateTime.utc(2026, 9, 23, 12);
    test('daily', () => expect(RankingPeriod.daily(d), '2026-09-23'));
    test('weekly starts on Monday', () => expect(RankingPeriod.weekly(d), 'w_2026-09-21'));
    test('weekly on a Monday is itself', () => expect(RankingPeriod.weekly(DateTime.utc(2026, 9, 21, 1)), 'w_2026-09-21'));
    test('weekly on a Sunday belongs to the previous Monday', () => expect(RankingPeriod.weekly(DateTime.utc(2026, 9, 27, 23)), 'w_2026-09-21'));
    test('monthly', () => expect(RankingPeriod.monthly(d), '2026-09'));
    test('id() dispatch', () {
      expect(RankingPeriod.id('daily', d), '2026-09-23');
      expect(RankingPeriod.id('weekly', d), 'w_2026-09-21');
      expect(RankingPeriod.id('monthly', d), '2026-09');
    });
  });

  group('LevelMath (must match Cloud Functions xpForLevel/levelFromXp)', () {
    test('thresholds', () {
      expect(LevelMath.xpForLevel(1), 0);
      expect(LevelMath.xpForLevel(2), 100);
      expect(LevelMath.xpForLevel(3), 300);
    });
    test('levelFromXp', () {
      expect(LevelMath.levelFromXp(0), 1);
      expect(LevelMath.levelFromXp(99), 1);
      expect(LevelMath.levelFromXp(100), 2);
      expect(LevelMath.levelFromXp(299), 2);
      expect(LevelMath.levelFromXp(300), 3);
    });
    test('progress is within 0..1', () {
      expect(LevelMath.progress(0), 0);
      expect(LevelMath.progress(150), closeTo(0.25, 1e-9));
    });
  });
}
