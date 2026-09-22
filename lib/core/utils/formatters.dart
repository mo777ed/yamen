import 'package:intl/intl.dart';

class Fmt {
  /// 1200 -> 1.2K, 3400000 -> 3.4M
  static String compact(num n) {
    if (n.abs() >= 1000000) return '${_trim(n / 1000000)}M';
    if (n.abs() >= 1000) return '${_trim(n / 1000)}K';
    return n.toInt().toString();
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static String number(num n) => NumberFormat.decimalPattern('en').format(n);

  static String time(DateTime d, [String locale = 'ar']) => DateFormat.Hm(locale).format(d);

  static String date(DateTime d, [String locale = 'ar']) => DateFormat.yMMMd(locale).format(d);

  static String dateTime(DateTime d, [String locale = 'ar']) => DateFormat.yMMMd(locale).add_Hm().format(d);

  /// yyyy-MM-dd in UTC. Must match the Cloud Functions todayKey().
  static String utcDay(DateTime d) {
    final u = d.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
  }
}

/// Ranking period ids. Mirrors periodIds() in functions/src/lib/common.ts.
class RankingPeriod {
  static String daily([DateTime? now]) => Fmt.utcDay(now ?? DateTime.now());

  static String weekly([DateTime? now]) {
    final u = (now ?? DateTime.now()).toUtc();
    final monday = DateTime.utc(u.year, u.month, u.day).subtract(Duration(days: (u.weekday + 6) % 7));
    return 'w_${Fmt.utcDay(monday)}';
  }

  static String monthly([DateTime? now]) => Fmt.utcDay(now ?? DateTime.now()).substring(0, 7);

  static String id(String period, [DateTime? now]) {
    switch (period) {
      case 'weekly':
        return weekly(now);
      case 'monthly':
        return monthly(now);
      default:
        return daily(now);
    }
  }
}

/// XP curve. Mirrors xpForLevel()/levelFromXp() in the Cloud Functions.
class LevelMath {
  static int xpForLevel(int level) => 50 * level * (level - 1);

  static int levelFromXp(int xp) {
    var l = 1;
    while (xpForLevel(l + 1) <= xp) {
      l++;
    }
    return l;
  }

  /// 0..1 progress inside the current level.
  static double progress(int xp) {
    final l = levelFromXp(xp);
    final start = xpForLevel(l);
    final end = xpForLevel(l + 1);
    return ((xp - start) / (end - start)).clamp(0.0, 1.0);
  }
}
