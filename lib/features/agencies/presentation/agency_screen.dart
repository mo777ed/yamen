import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/user_repository.dart';

final agencyProvider = StreamProvider.autoDispose.family<Agency?, String>((ref, id) =>
    ref.watch(firestoreProvider).doc('${Col.agencies}/$id').snapshots().map((s) => s.exists ? Agency.fromDoc(s) : null));

final agencyHostsProvider = StreamProvider.autoDispose.family<List<Host>, String>((ref, id) => ref
    .watch(firestoreProvider)
    .collection(Col.hosts)
    .where('agencyId', isEqualTo: id)
    .orderBy('earnings', descending: true)
    .limit(100)
    .snapshots()
    .map((s) => s.docs.map(Host.fromDoc).toList()));

class AgencyScreen extends ConsumerWidget {
  const AgencyScreen({super.key, required this.agencyId});
  final String agencyId;

  Future<void> _addHost(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('agency.add_host')),
        content: TextField(controller: c, autofocus: true, textDirection: TextDirection.ltr, decoration: InputDecoration(hintText: ctx.tr('profile.username'), prefixText: '@')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ctx.tr('agency.add'))),
        ],
      ),
    );
    if (username == null || username.isEmpty) return;
    try {
      final users = await ref.read(userRepositoryProvider).searchUsers(username);
      final match = users.where((u) => u.username == username.toLowerCase().replaceFirst('@', '')).firstOrNull;
      if (match == null) throw const Failure('not-found', 'المستخدم غير موجود');
      await ref.read(functionsClientProvider).call(Fn.agencyAddHost, {'agencyId': agencyId, 'uid': match.id});
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('agency.host_added'))));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agency = ref.watch(agencyProvider(agencyId));
    final hosts = ref.watch(agencyHostsProvider(agencyId));
    final me = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('agency.title'))),
      body: AsyncBody<Agency?>(
        value: agency,
        onRetry: () => ref.invalidate(agencyProvider(agencyId)),
        data: (a) {
          if (a == null) return EmptyState(message: context.tr('agency.not_found'), icon: Icons.business_rounded);
          final canManage = a.ownerId == me?.id || (me?.role.isAdmin ?? false);
          return ListView(padding: const EdgeInsets.all(16), children: [
            GlassCard(
              child: Column(children: [
                const Icon(Icons.business_rounded, size: 40, color: AppColors.primary),
                const SizedBox(height: 8),
                Text(a.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                Chip(label: Text(context.tr('agency.status_${a.status}'))),
                const SizedBox(height: 8),
                Row(children: [
                  _stat(context, Fmt.number(a.hostsCount), 'agency.hosts'),
                  _stat(context, '${a.commissionPct}%', 'agency.commission'),
                  if (canManage) _stat(context, Fmt.number(a.earnings), 'agency.earnings'),
                ]),
              ]),
            ),
            if (canManage && a.status == 'active')
              Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton.icon(onPressed: () => _addHost(context, ref), icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(context.tr('agency.add_host')))),
            Padding(padding: const EdgeInsets.only(top: 20, bottom: 8), child: Text(context.tr('agency.hosts'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            hosts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorState(error: e),
              data: (list) => list.isEmpty
                  ? Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(context.tr('agency.no_hosts'))))
                  : Column(children: [
                      for (final h in list)
                        ListTile(
                          onTap: () => context.push('/profile/${h.uid}'),
                          leading: UserAvatar(url: h.avatarUrl, name: h.displayName, size: 44),
                          title: Text(h.displayName),
                          subtitle: Text('${h.totalHours.toStringAsFixed(1)} ${context.tr('host.hours')} · ${Fmt.compact(h.giftsReceived)} ${context.tr('profile.gifts_received')}', style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
                          trailing: canManage ? Text('💎 ${Fmt.compact(h.earnings)}', style: const TextStyle(fontWeight: FontWeight.w800)) : null,
                        ),
                    ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _stat(BuildContext context, String v, String k) => Expanded(child: Column(children: [
        Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        Text(context.tr(k), style: TextStyle(fontSize: 12, color: context.palette.textMuted)),
      ]));
}
