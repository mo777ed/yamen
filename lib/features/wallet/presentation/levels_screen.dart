import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/badges.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../data/wallet_repository.dart';

/// XP is granted only by Cloud Functions; this screen just displays it.
class LevelsScreen extends ConsumerWidget {
  const LevelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lvl = ref.watch(userLevelProvider).valueOrNull ?? const UserLevel();
    final next = LevelMath.xpForLevel(lvl.level + 1);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('levels.title'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GlassCard(
          child: Column(children: [
            LevelBadge(level: lvl.level),
            const SizedBox(height: 12),
            Text(context.tr('levels.level', {'n': lvl.level}), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: LevelMath.progress(lvl.xp), minHeight: 10, backgroundColor: context.palette.surfaceHigh, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text('${Fmt.number(lvl.xp)} / ${Fmt.number(next)} XP', style: TextStyle(color: context.palette.textMuted)),
            if (lvl.streak > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.tr('levels.streak', {'n': lvl.streak}), style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700))),
          ]),
        ),
        const SizedBox(height: 16),
        Text(context.tr('levels.how'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final k in ['levels.src_activity', 'levels.src_voice', 'levels.src_send', 'levels.src_receive', 'levels.src_daily', 'levels.src_events'])
          ListTile(dense: true, leading: const Icon(Icons.bolt_rounded, color: AppColors.gold), title: Text(context.tr(k))),
      ]),
    );
  }
}
