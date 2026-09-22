import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/states.dart';

const kRankTypes = ['hosts', 'gifters', 'rooms', 'agencies'];

/// Counters are written by Cloud Functions (onGiftTransactionCreated); the client only reads the top 50.
final rankingProvider = StreamProvider.autoDispose.family<List<RankEntry>, ({String type, String period})>((ref, k) {
  final set = '${k.type}_${k.period}_${RankingPeriod.id(k.period)}';
  return ref
      .watch(firestoreProvider)
      .collection('${Col.rankings}/$set/entries')
      .orderBy('score', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(RankEntry.fromDoc).toList());
});

class RankingsScreen extends ConsumerStatefulWidget {
  const RankingsScreen({super.key});
  @override
  ConsumerState<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends ConsumerState<RankingsScreen> {
  String _period = 'daily';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: kRankTypes.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('rank.title')),
          bottom: TabBar(isScrollable: true, tabs: [for (final t in kRankTypes) Tab(text: context.tr('rank.$t'))]),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: [for (final p in ['daily', 'weekly', 'monthly']) ButtonSegment(value: p, label: Text(context.tr('rank.$p')))],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
          ),
          Expanded(child: TabBarView(children: [for (final t in kRankTypes) _RankList(type: t, period: _period)])),
        ]),
      ),
    );
  }
}

class _RankList extends ConsumerWidget {
  const _RankList({required this.type, required this.period});
  final String type;
  final String period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rankingProvider((type: type, period: period)));
    return AsyncBody<List<RankEntry>>(
      value: async,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: context.tr('rank.empty'),
      emptyIcon: Icons.leaderboard_rounded,
      onRetry: () => ref.invalidate(rankingProvider((type: type, period: period))),
      data: (list) => ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) {
          final e = list[i];
          final medal = i == 0 ? const Color(0xFFFFD700) : i == 1 ? const Color(0xFFC0C0C0) : i == 2 ? const Color(0xFFCD7F32) : null;
          return ListTile(
            leading: SizedBox(
              width: 88,
              child: Row(children: [
                SizedBox(width: 30, child: medal != null ? Icon(Icons.emoji_events_rounded, color: medal) : Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted, fontWeight: FontWeight.w800))),
                UserAvatar(url: e.avatar, name: e.name, size: 44),
              ]),
            ),
            title: Text(e.name.isEmpty ? '—' : e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(type == 'hosts' ? Icons.diamond_rounded : Icons.monetization_on_rounded, size: 16, color: type == 'hosts' ? AppColors.secondary : AppColors.gold),
              const SizedBox(width: 4),
              Text(Fmt.compact(e.score), style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          );
        },
      ),
    );
  }
}
