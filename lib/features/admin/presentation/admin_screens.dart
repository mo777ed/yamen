import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/roles.dart';
import '../../../core/errors/failures.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/user_repository.dart';

final adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(functionsClientProvider).call(Fn.adminStats));

Future<void> _guard(BuildContext context, Future<void> Function() a, {String? ok}) async {
  try {
    await a();
    if (ok != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(ok))));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

Future<String?> _prompt(BuildContext context, String title, {String hint = '', TextInputType? type}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, keyboardType: type, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ctx.tr('common.continue'))),
      ],
    ),
  );
}

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    final me = ref.watch(currentUserProvider);
    final isAdmin = me?.role.isAdmin ?? false;

    final tiles = <(IconData, String, String, bool)>[
      (Icons.people_alt_rounded, 'admin.users', '/admin/users', false),
      (Icons.flag_rounded, 'admin.reports', '/admin/reports', false),
      (Icons.card_giftcard_rounded, 'admin.gifts', '/admin/collection/gifts', true),
      (Icons.workspace_premium_rounded, 'admin.vip', '/admin/collection/vip_levels', true),
      (Icons.casino_rounded, 'admin.games', '/admin/collection/games', true),
      (Icons.celebration_rounded, 'admin.events', '/admin/collection/events', true),
      (Icons.image_rounded, 'admin.banners', '/admin/collection/banners', true),
      (Icons.tune_rounded, 'admin.settings', '/admin/collection/settings', true),
      (Icons.business_rounded, 'admin.agencies', '/admin/agencies', true),
      (Icons.history_rounded, 'admin.audit', '/admin/audit', true),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('admin.title')), actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => ref.invalidate(adminStatsProvider))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        stats.when(
          loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(adminStatsProvider)),
          data: (s) => GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.15,
            children: [
              for (final k in ['users', 'online', 'rooms', 'activeRooms', 'gifts', 'openReports', 'bans', 'hosts', 'agencies'])
                GlassCard(
                  padding: const EdgeInsets.all(8),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(Fmt.compact(asInt(s[k])), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    Text(context.tr('admin.stat_$k'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: context.palette.textMuted)),
                  ]),
                ),
            ],
          ),
        ),
        if (isAdmin)
          stats.maybeWhen(
            data: (s) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Expanded(child: GlassCard(child: Column(children: [Text('\$${asDouble(s['revenueUsd']).toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.success)), Text(context.tr('admin.stat_revenue'), style: const TextStyle(fontSize: 12))]))),
                const SizedBox(width: 10),
                Expanded(child: GlassCard(child: Column(children: [Text(Fmt.compact(asInt(s['coinsInCirculation'])), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.gold)), Text(context.tr('admin.stat_coins'), style: const TextStyle(fontSize: 12))]))),
              ]),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        const SizedBox(height: 16),
        for (final t in tiles)
          if (!t.$4 || isAdmin) ListTile(leading: Icon(t.$1, color: AppColors.primary), title: Text(context.tr(t.$2)), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => context.push(t.$3)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- users
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _debounce = Debouncer(const Duration(milliseconds: 450));
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  String _q = '';

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_q.trim().length < 2) {
      setState(() => _users = []);
      return;
    }
    setState(() => _loading = true);
    await _guard(context, () async {
      final res = await ref.read(functionsClientProvider).call(Fn.adminSearchUsers, {'q': _q.trim().replaceFirst('@', '')});
      _users = (res['users'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    });
    if (mounted) setState(() => _loading = false);
  }

  void _actions(Map<String, dynamic> u) {
    final fn = ref.read(functionsClientProvider);
    final me = ref.read(currentUserProvider);
    final id = u['id'] as String;
    final banned = u['status'] == 'banned';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: UserAvatar(url: (u['avatarUrl'] ?? '') as String, name: (u['displayName'] ?? '') as String, size: 44), title: Text((u['displayName'] ?? '') as String), subtitle: Text('@${u['username']} · ${u['role']}')),
          ListTile(leading: const Icon(Icons.person_rounded), title: Text(ctx.tr('room.view_profile')), onTap: () {
            Navigator.pop(ctx);
            context.push('/profile/$id');
          }),
          if (!banned) ...[
            ListTile(leading: const Icon(Icons.timer_rounded, color: AppColors.danger), title: Text(ctx.tr('admin.ban_temp')), onTap: () async {
              Navigator.pop(ctx);
              final days = await _prompt(context, ctx.tr('admin.ban_days'), type: TextInputType.number);
              final reason = days == null ? null : await _prompt(context, ctx.tr('admin.reason'));
              if (days != null && reason != null && context.mounted) {
                await _guard(context, () => fn.call(Fn.adminBanUser, {'uid': id, 'kind': 'temporary', 'days': int.tryParse(days) ?? 1, 'reason': reason.isEmpty ? '-' : reason}), ok: 'common.done');
                _search();
              }
            }),
            ListTile(leading: const Icon(Icons.block_rounded, color: AppColors.danger), title: Text(ctx.tr('admin.ban_perm')), onTap: () async {
              Navigator.pop(ctx);
              final reason = await _prompt(context, ctx.tr('admin.reason'));
              if (reason != null && context.mounted) {
                await _guard(context, () => fn.call(Fn.adminBanUser, {'uid': id, 'kind': 'permanent', 'reason': reason.isEmpty ? '-' : reason}), ok: 'common.done');
                _search();
              }
            }),
          ] else
            ListTile(leading: const Icon(Icons.lock_open_rounded, color: AppColors.success), title: Text(ctx.tr('admin.unban')), onTap: () async {
              Navigator.pop(ctx);
              await _guard(context, () => fn.call(Fn.adminUnbanUser, {'uid': id}), ok: 'common.done');
              _search();
            }),
          if (me?.role.isAdmin ?? false) ...[
            ListTile(leading: const Icon(Icons.badge_rounded), title: Text(ctx.tr('admin.set_role')), onTap: () async {
              Navigator.pop(ctx);
              final role = await showDialog<String>(
                context: context,
                builder: (d) => SimpleDialog(title: Text(d.tr('admin.set_role')), children: [
                  for (final r in Role.values) SimpleDialogOption(onPressed: () => Navigator.pop(d, r.wire), child: Text(r.wire)),
                ]),
              );
              if (role != null && context.mounted) {
                await _guard(context, () => fn.call(Fn.adminSetRole, {'uid': id, 'role': role}), ok: 'common.done');
                _search();
              }
            }),
            ListTile(leading: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.gold), title: Text(ctx.tr('admin.adjust_wallet')), onTap: () async {
              Navigator.pop(ctx);
              final coins = await _prompt(context, ctx.tr('admin.coins_delta'), type: const TextInputType.numberWithOptions(signed: true));
              if (coins == null || !context.mounted) return;
              final reason = await _prompt(context, ctx.tr('admin.reason'));
              if (reason == null || !context.mounted) return;
              await _guard(context, () => fn.call(Fn.adminAdjustWallet, {'uid': id, 'coins': int.tryParse(coins) ?? 0, 'diamonds': 0, 'reason': reason.isEmpty ? '-' : reason}), ok: 'common.done');
            }),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('admin.users'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            autofocus: true,
            onChanged: (v) {
              _q = v;
              _debounce.run(_search);
            },
            decoration: InputDecoration(hintText: context.tr('admin.search_username'), prefixIcon: const Icon(Icons.search_rounded)),
          ),
        ),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 4)
              : _users.isEmpty
                  ? EmptyState(message: context.tr('search.no_results'), icon: Icons.person_search_rounded)
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        return ListTile(
                          leading: UserAvatar(url: (u['avatarUrl'] ?? '') as String, name: (u['displayName'] ?? '') as String, size: 44),
                          title: Text((u['displayName'] ?? '') as String),
                          subtitle: Text('@${u['username']} · ${u['role']}${u['status'] == 'banned' ? ' · 🚫' : ''}'),
                          onTap: () => _actions(u),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- reports
final openReportsProvider = StreamProvider.autoDispose<List<QDoc>>((ref) => ref
    .watch(firestoreProvider)
    .collection(Col.reports)
    .where('status', isEqualTo: 'open')
    .orderBy('createdAt', descending: true)
    .limit(50)
    .snapshots()
    .map((s) => s.docs));

class AdminReportsScreen extends ConsumerWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fn = ref.read(functionsClientProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('admin.reports'))),
      body: AsyncBody<List<QDoc>>(
        value: ref.watch(openReportsProvider),
        isEmpty: (l) => l.isEmpty,
        emptyMessage: context.tr('admin.no_reports'),
        emptyIcon: Icons.verified_rounded,
        onRetry: () => ref.invalidate(openReportsProvider),
        data: (docs) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final type = asStr(d['targetType']);
            final target = asStr(d['targetId']);
            return GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Chip(label: Text(type), visualDensity: VisualDensity.compact),
                  const Spacer(),
                  if (tsToDate(d['createdAt']) != null) Text(Fmt.dateTime(tsToDate(d['createdAt'])!, context.isArabic ? 'ar' : 'en'), style: TextStyle(fontSize: 11, color: context.palette.textMuted)),
                ]),
                Text(asStr(d['reason'])),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  if (type == 'user') OutlinedButton(onPressed: () => context.push('/profile/$target'), child: Text(context.tr('room.view_profile'))),
                  if (type == 'room') OutlinedButton(onPressed: () => context.push('/room/$target'), child: Text(context.tr('room.enter'))),
                  OutlinedButton(onPressed: () => _guard(context, () => fn.call(Fn.adminResolveReport, {'reportId': docs[i].id, 'resolution': 'dismissed'})), child: Text(context.tr('admin.dismiss'))),
                  FilledButton(onPressed: () => _guard(context, () => fn.call(Fn.adminResolveReport, {'reportId': docs[i].id, 'resolution': 'actioned'})), child: Text(context.tr('admin.actioned'))),
                ]),
              ]),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- generic collection editor
Object? _jsonSafe(Object? v) {
  if (v is Timestamp) return v.toDate().toUtc().toIso8601String();
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), _jsonSafe(val)));
  if (v is List) return v.map(_jsonSafe).toList();
  return v;
}

class AdminCollectionScreen extends ConsumerWidget {
  const AdminCollectionScreen({super.key, required this.collection});
  final String collection;

  static const _allowed = ['gifts', 'vip_levels', 'games', 'events', 'banners', 'settings'];

  Future<void> _edit(BuildContext context, WidgetRef ref, {String? id, Map<String, dynamic>? data}) async {
    if (!_allowed.contains(collection)) return;
    final idCtl = TextEditingController(text: id ?? '');
    final json = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(_jsonSafe(data ?? {})));
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(id == null ? ctx.tr('admin.new_doc') : id),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (id == null) TextField(controller: idCtl, decoration: InputDecoration(hintText: ctx.tr('admin.doc_id'))),
            const SizedBox(height: 8),
            Flexible(child: TextField(controller: json, maxLines: 14, minLines: 8, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5), textDirection: TextDirection.ltr)),
          ]),
        ),
        actions: [
          if (id != null) TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text(ctx.tr('common.delete'), style: const TextStyle(color: AppColors.danger))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(ctx.tr('common.save'))),
        ],
      ),
    );
    if (res == null || !context.mounted) return;
    final fn = ref.read(functionsClientProvider);
    if (res == 'delete') {
      await _guard(context, () => fn.call(Fn.adminDelete, {'collection': collection, 'id': id}), ok: 'common.done');
      return;
    }
    await _guard(context, () async {
      final parsed = jsonDecode(json.text);
      if (parsed is! Map) throw const Failure('json', 'JSON غير صالح: يجب أن يكون كائناً');
      final clean = Map<String, dynamic>.from(parsed)..remove('updatedAt')..remove('createdAt');
      final docId = id ?? (idCtl.text.trim().isEmpty ? null : idCtl.text.trim());
      await fn.call(Fn.adminUpsert, {'collection': collection, if (docId != null) 'id': docId, 'data': clean});
    }, ok: 'common.done');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(firestoreProvider).collection(collection).limit(100).snapshots();
    return Scaffold(
      appBar: AppBar(title: Text(collection)),
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(context, ref), child: const Icon(Icons.add_rounded)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error!);
          if (!snap.hasData) return const SkeletonList();
          final docs = snap.data!.docs;
          if (docs.isEmpty) return EmptyState(message: context.tr('common.empty'));
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, i) {
              final d = docs[i];
              final name = d.data()['name'] ?? d.data()['title'];
              return ListTile(
                title: Text(d.id),
                subtitle: Text(name == null ? '' : localized(name, arabic: context.isArabic)),
                trailing: const Icon(Icons.edit_rounded, size: 18),
                onTap: () => _edit(context, ref, id: d.id, data: d.data()),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- agencies
class AdminAgenciesScreen extends ConsumerWidget {
  const AdminAgenciesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fn = ref.read(functionsClientProvider);
    final stream = ref.watch(firestoreProvider).collection(Col.agencies).orderBy('createdAt', descending: true).limit(100).snapshots();

    Future<void> create() async {
      final name = await _prompt(context, context.tr('agency.name'));
      if (name == null || name.isEmpty || !context.mounted) return;
      final username = await _prompt(context, context.tr('admin.owner_username'), hint: 'username');
      if (username == null || username.isEmpty || !context.mounted) return;
      final commission = await _prompt(context, context.tr('agency.commission'), hint: '10', type: TextInputType.number);
      if (commission == null || !context.mounted) return;
      await _guard(context, () async {
        final users = await ref.read(userRepositoryProvider).searchUsers(username);
        final owner = users.where((u) => u.username == username.toLowerCase().replaceFirst('@', '')).firstOrNull;
        if (owner == null) throw const Failure('not-found', 'المستخدم غير موجود');
        await fn.call(Fn.adminCreateAgency, {'name': name, 'ownerUid': owner.id, 'commissionPct': int.tryParse(commission) ?? 10});
      }, ok: 'common.done');
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('admin.agencies'))),
      floatingActionButton: FloatingActionButton(onPressed: create, child: const Icon(Icons.add_business_rounded)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error!);
          if (!snap.hasData) return const SkeletonList();
          final list = snap.data!.docs.map(Agency.fromDoc).toList();
          if (list.isEmpty) return EmptyState(message: context.tr('common.empty'), icon: Icons.business_rounded);
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final a = list[i];
              return ListTile(
                onTap: () => context.push('/agency/${a.id}'),
                leading: const CircleAvatar(child: Icon(Icons.business_rounded)),
                title: Text(a.name),
                subtitle: Text('${context.tr('agency.status_${a.status}')} · ${a.commissionPct}% · ${a.hostsCount} ${context.tr('agency.hosts')}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'commission') {
                      final c = await _prompt(context, context.tr('agency.commission'), type: TextInputType.number);
                      if (c == null || !context.mounted) return;
                      await _guard(context, () => fn.call(Fn.adminSetAgencyStatus, {'agencyId': a.id, 'status': a.status, 'commissionPct': int.tryParse(c) ?? a.commissionPct}), ok: 'common.done');
                    } else {
                      await _guard(context, () => fn.call(Fn.adminSetAgencyStatus, {'agencyId': a.id, 'status': v}), ok: 'common.done');
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'active', child: Text(context.tr('agency.status_active'))),
                    PopupMenuItem(value: 'suspended', child: Text(context.tr('agency.status_suspended'))),
                    PopupMenuItem(value: 'commission', child: Text(context.tr('agency.commission'))),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- audit log
class AdminAuditScreen extends ConsumerWidget {
  const AdminAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(firestoreProvider).collection(Col.auditLogs).orderBy('createdAt', descending: true).limit(80).snapshots();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('admin.audit'))),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(error: snap.error!);
          if (!snap.hasData) return const SkeletonList();
          final docs = snap.data!.docs;
          if (docs.isEmpty) return EmptyState(message: context.tr('common.empty'));
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, i) {
              final d = docs[i].data();
              final at = tsToDate(d['createdAt']);
              return ListTile(
                dense: true,
                title: Text('${d['action']}  →  ${d['targetId'] ?? ''}', textDirection: TextDirection.ltr),
                subtitle: Text('${d['actorId']}${at == null ? '' : '  ·  ${Fmt.dateTime(at, 'en')}'}', textDirection: TextDirection.ltr, style: TextStyle(color: context.palette.textMuted, fontSize: 11.5)),
              );
            },
          );
        },
      ),
    );
  }
}
