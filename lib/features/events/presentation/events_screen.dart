import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/states.dart';

final eventsProvider = StreamProvider.autoDispose<List<EventItem>>((ref) => ref
    .watch(firestoreProvider)
    .collection(Col.events)
    .where('active', isEqualTo: true)
    .orderBy('startsAt', descending: true)
    .limit(30)
    .snapshots()
    .map((s) => s.docs.map(EventItem.fromDoc).toList()));

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = context.isArabic;
    final locale = ar ? 'ar' : 'en';
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('events.title'))),
      body: AsyncBody<List<EventItem>>(
        value: ref.watch(eventsProvider),
        isEmpty: (l) => l.isEmpty,
        emptyMessage: context.tr('events.empty'),
        emptyIcon: Icons.celebration_rounded,
        onRetry: () => ref.invalidate(eventsProvider),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final e = list[i];
            return GlassCard(
              padding: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (e.imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: CachedNetworkImage(imageUrl: e.imageUrl, height: 140, width: double.infinity, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox(height: 140)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Chip(label: Text(context.tr('events.${e.kind}'), style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact, backgroundColor: AppColors.primary.withOpacity(0.2)),
                    ]),
                    Text(e.title(ar), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    if (e.description(ar).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(e.description(ar), style: TextStyle(color: context.palette.textMuted))),
                    if (e.startsAt != null && e.endsAt != null)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text('${Fmt.date(e.startsAt!, locale)} → ${Fmt.date(e.endsAt!, locale)}', style: const TextStyle(fontSize: 12, color: AppColors.gold))),
                  ]),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}
