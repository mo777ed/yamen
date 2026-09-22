import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/countries.dart';
import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/badges.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../gifts/data/gift_repository.dart';
import '../../messages/data/chat_repository.dart';
import '../data/user_repository.dart';

/// [uid] == null shows the signed-in user's own profile (bottom-nav tab).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.uid});
  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myUidProvider);
    final id = uid ?? me;
    final isMe = id == me;
    final user = ref.watch(userProvider(id));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(isMe ? 'nav.profile' : 'profile.title')),
        actions: [
          if (isMe) IconButton(icon: const Icon(Icons.settings_rounded), onPressed: () => context.push('/settings')),
          if (!isMe) _MoreMenu(targetId: id),
        ],
      ),
      body: user.when(
        loading: () => const SkeletonList(count: 4),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(userProvider(id))),
        data: (u) {
          if (u == null) return EmptyState(message: context.tr('profile.not_found'), icon: Icons.person_off_rounded);
          return DefaultTabController(
            length: 3,
            child: NestedScrollView(
              headerSliverBuilder: (_, __) => [
                SliverToBoxAdapter(child: _Header(user: u, isMe: isMe)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsDelegate(TabBar(tabs: [
                    Tab(text: context.tr('profile.posts')),
                    Tab(text: context.tr('profile.gifts')),
                    Tab(text: context.tr('profile.achievements')),
                  ]), context.palette.bg),
                ),
              ],
              body: TabBarView(children: [
                _PostsTab(user: u, isMe: isMe),
                _GiftsTab(uid: u.id),
                _AchievementsTab(user: u),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _TabsDelegate extends SliverPersistentHeaderDelegate {
  _TabsDelegate(this.bar, this.bg);
  final TabBar bar;
  final Color bg;
  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: bg, child: bar);
  @override
  bool shouldRebuild(covariant _TabsDelegate old) => old.bar != bar || old.bg != bg;
}

class _Header extends ConsumerStatefulWidget {
  const _Header({required this.user, required this.isMe});
  final AppUser user;
  final bool isMe;
  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() a) async {
    setState(() => _busy = true);
    try {
      await a();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final me = ref.watch(myUidProvider);
    final repo = ref.read(userRepositoryProvider);
    final country = u.country.isEmpty ? null : countryByCode(u.country);
    final following = ref.watch(isFollowingProvider(u.id)).valueOrNull ?? false;
    final blocked = ref.watch(isBlockedProvider(u.id)).valueOrNull ?? false;
    final friendState = widget.isMe ? null : ref.watch(friendStateProvider(u.id)).valueOrNull;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        UserAvatar(url: u.avatarUrl, name: u.displayName, size: 96, vipLevel: u.vipLevel, online: (u.hideOnline && !widget.isMe) ? null : u.online),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: Text(u.displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          LevelBadge(level: u.level),
          if (u.vipLevel > 0) ...[const SizedBox(width: 4), VipBadge(level: u.vipLevel)],
        ]),
        Text(u.handle, style: TextStyle(color: context.palette.textMuted)),
        if (country != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${country.flag} ${country.name(context.isArabic)}', style: TextStyle(color: context.palette.textMuted, fontSize: 13))),
        if (u.bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(u.bio, textAlign: TextAlign.center)),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            _stat(context, u.followersCount, 'profile.followers', () => context.push('/followers/${u.id}')),
            _stat(context, u.followingCount, 'profile.following', () => context.push('/following/${u.id}')),
            _stat(context, u.friendsCount, 'profile.friends', widget.isMe ? () => context.push('/friends') : null),
            _stat(context, u.giftsReceived, 'profile.gifts_received', null),
          ]),
        ),
        const SizedBox(height: 16),
        if (widget.isMe)
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/profile/edit'), icon: const Icon(Icons.edit_rounded), label: Text(context.tr('profile.edit')))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/levels'), icon: const Icon(Icons.bolt_rounded), label: Text(context.tr('levels.title')))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => context.push('/vip'), icon: const Icon(Icons.workspace_premium_rounded), label: const Text('VIP'))),
          ])
        else if (blocked)
          GradientButton(label: context.tr('profile.unblock'), onPressed: _busy ? null : () => _run(() => repo.unblock(me, u.id)), gradient: AppColors.dangerGradient)
        else
          Row(children: [
            Expanded(
              child: GradientButton(
                height: 46,
                label: context.tr(following ? 'profile.unfollow' : 'profile.follow'),
                gradient: following ? const LinearGradient(colors: [Color(0xFF3A3F55), Color(0xFF2A2E40)]) : AppColors.primaryGradient,
                onPressed: _busy ? null : () => _run(() => following ? repo.unfollow(me, u.id) : repo.follow(me, u.id)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                onPressed: _busy ? null : () => _run(() async {
                  final chatId = await ref.read(chatRepositoryProvider).openChat(me, u, friendState == FriendState.friends);
                  if (mounted) context.push('/messages/$chatId');
                }),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: Text(context.tr('profile.message')),
              ),
            ),
            const SizedBox(width: 8),
            _friendButton(friendState, me, u.id, repo),
          ]),
      ]),
    );
  }

  Widget _friendButton(FriendState? s, String me, String other, UserRepository repo) {
    IconData icon;
    String tip;
    VoidCallback? onTap;
    switch (s) {
      case FriendState.friends:
        icon = Icons.how_to_reg_rounded;
        tip = context.tr('friends.remove');
        onTap = () => _run(() async {
              await repo.removeFriend(other);
              ref.invalidate(friendStateProvider(other));
            });
        break;
      case FriendState.requestSent:
        icon = Icons.hourglass_top_rounded;
        tip = context.tr('friends.request_sent');
        onTap = null;
        break;
      case FriendState.requestReceived:
        icon = Icons.person_add_alt_1_rounded;
        tip = context.tr('friends.respond');
        onTap = () => context.push('/friends');
        break;
      default:
        icon = Icons.person_add_alt_rounded;
        tip = context.tr('friends.add');
        onTap = () => _run(() async {
              await repo.sendFriendRequest(me, other);
              ref.invalidate(friendStateProvider(other));
            });
    }
    return IconButton.filledTonal(onPressed: _busy ? null : onTap, icon: Icon(icon), tooltip: tip);
  }

  Widget _stat(BuildContext context, int n, String labelKey, VoidCallback? onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(children: [
            Text(Fmt.compact(n), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(context.tr(labelKey), style: TextStyle(fontSize: 11.5, color: context.palette.textMuted), textAlign: TextAlign.center),
          ]),
        ),
      );
}

class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.targetId});
  final String targetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myUidProvider);
    final blocked = ref.watch(isBlockedProvider(targetId)).valueOrNull ?? false;
    return PopupMenuButton<String>(
      onSelected: (v) async {
        final repo = ref.read(userRepositoryProvider);
        if (v == 'report') context.push('/report/user/$targetId');
        if (v == 'block') await repo.block(me, targetId);
        if (v == 'unblock') await repo.unblock(me, targetId);
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'report', child: Text(context.tr('report.user'))),
        PopupMenuItem(value: blocked ? 'unblock' : 'block', child: Text(context.tr(blocked ? 'profile.unblock' : 'profile.block'))),
      ],
    );
  }
}

class _PostsTab extends ConsumerWidget {
  const _PostsTab({required this.user, required this.isMe});
  final AppUser user;
  final bool isMe;

  Future<void> _compose(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('profile.new_post')),
        content: TextField(controller: c, maxLength: 500, maxLines: 4, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ctx.tr('profile.publish'))),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    try {
      await ref.read(userRepositoryProvider).createPost(user, text);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(postsProvider(user.id));
    return Stack(children: [
      AsyncBody<List<Post>>(
        value: posts,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: context.tr('profile.no_posts'),
        emptyIcon: Icons.article_outlined,
        onRetry: () => ref.invalidate(postsProvider(user.id)),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(list[i].text),
              const SizedBox(height: 8),
              Row(children: [
                Text(list[i].createdAt == null ? '' : Fmt.dateTime(list[i].createdAt!, context.isArabic ? 'ar' : 'en'), style: TextStyle(fontSize: 11.5, color: context.palette.textMuted)),
                const Spacer(),
                if (isMe) InkWell(onTap: () => ref.read(userRepositoryProvider).deletePost(list[i].id), child: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger)),
              ]),
            ]),
          ),
        ),
      ),
      if (isMe) PositionedDirectional(end: 16, bottom: 16, child: FloatingActionButton(onPressed: () => _compose(context, ref), child: const Icon(Icons.edit_rounded))),
    ]);
  }
}

class _GiftsTab extends ConsumerWidget {
  const _GiftsTab({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gifts = ref.watch(receivedGiftsProvider(uid));
    return AsyncBody<List<QDoc>>(
      value: gifts,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: context.tr('profile.no_gifts'),
      emptyIcon: Icons.card_giftcard_rounded,
      onRetry: () => ref.invalidate(receivedGiftsProvider(uid)),
      data: (docs) => ListView.builder(
        itemCount: docs.length,
        itemBuilder: (_, i) {
          final d = docs[i].data();
          final name = localized(d['giftName'], arabic: context.isArabic);
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.card_giftcard_rounded, color: AppColors.gold)),
            title: Text('${d['qty'] ?? 1}× $name'),
            subtitle: Text(context.tr('gift.from', {'name': d['senderName'] ?? ''})),
          );
        },
      ),
    );
  }
}

class _AchievementsTab extends StatelessWidget {
  const _AchievementsTab({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    // Badges are derived from server-maintained counters, never written by the client.
    final items = <(String, IconData, bool)>[
      ('ach.level10', Icons.bolt_rounded, user.level >= 10),
      ('ach.level30', Icons.local_fire_department_rounded, user.level >= 30),
      ('ach.followers100', Icons.groups_rounded, user.followersCount >= 100),
      ('ach.gifts100', Icons.card_giftcard_rounded, user.giftsReceived >= 100),
      ('ach.friends10', Icons.diversity_1_rounded, user.friendsCount >= 10),
      ('ach.vip', Icons.workspace_premium_rounded, user.vipLevel > 0),
    ];
    return GridView.count(
      crossAxisCount: 3,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        for (final it in items)
          GlassCard(
            padding: const EdgeInsets.all(8),
            child: Opacity(
              opacity: it.$3 ? 1 : 0.35,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(it.$2, size: 34, color: it.$3 ? AppColors.gold : context.palette.textMuted),
                const SizedBox(height: 6),
                Text(context.tr(it.$1), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ],
    );
  }
}
