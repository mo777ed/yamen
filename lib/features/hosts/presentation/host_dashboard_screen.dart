import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';

final myHostProvider = StreamProvider.autoDispose<Host?>((ref) {
  final uid = ref.watch(myUidProvider);
  return ref.watch(firestoreProvider).doc('${Col.hosts}/$uid').snapshots().map((s) => s.exists ? Host.fromDoc(s) : null);
});

class HostDashboardScreen extends ConsumerWidget {
  const HostDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('host.title'))),
      body: AsyncBody<Host?>(
        value: ref.watch(myHostProvider),
        onRetry: () => ref.invalidate(myHostProvider),
        data: (h) {
          if (h == null) return EmptyState(message: context.tr('host.not_host'), icon: Icons.mic_none_rounded);
          return ListView(padding: const EdgeInsets.all(16), children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _card(context, Icons.diamond_rounded, AppColors.secondary, Fmt.number(h.earnings), 'host.earnings'),
                _card(context, Icons.card_giftcard_rounded, AppColors.gold, Fmt.number(h.giftsReceived), 'profile.gifts_received'),
                _card(context, Icons.timer_rounded, AppColors.success, h.totalHours.toStringAsFixed(1), 'host.hours'),
                _card(context, Icons.bolt_rounded, AppColors.primary, '${h.level}', 'host.level'),
              ],
            ),
            const SizedBox(height: 16),
            if (h.agencyId.isNotEmpty) OutlinedButton.icon(onPressed: () => context.push('/agency/${h.agencyId}'), icon: const Icon(Icons.business_rounded), label: Text(context.tr('host.my_agency'))),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => context.push('/rankings'), icon: const Icon(Icons.leaderboard_rounded), label: Text(context.tr('rank.title'))),
          ]);
        },
      ),
    );
  }

  Widget _card(BuildContext context, IconData icon, Color color, String value, String key) => GlassCard(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Text(context.tr(key), style: TextStyle(fontSize: 12, color: context.palette.textMuted)),
        ]),
      );
}
