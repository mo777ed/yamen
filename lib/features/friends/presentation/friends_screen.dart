import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/components/user_tile.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../messages/data/chat_repository.dart';
import '../../profile/data/user_repository.dart';

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(incomingRequestsProvider);
    final count = requests.valueOrNull?.length ?? 0;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('friends.title')),
          bottom: TabBar(tabs: [
            Tab(text: context.tr('profile.friends')),
            Tab(text: count == 0 ? context.tr('friends.requests') : '${context.tr('friends.requests')} ($count)'),
          ]),
        ),
        body: TabBarView(children: [_FriendsList(), _Requests()]),
      ),
    );
  }
}

class _FriendsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);
    final me = ref.watch(myUidProvider);
    return AsyncBody<List<AppUser>>(
      value: friends,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: context.tr('friends.empty'),
      emptyIcon: Icons.people_outline_rounded,
      onRetry: () => ref.invalidate(friendsProvider),
      data: (list) => ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) {
          final u = list[i];
          return UserTile(
            user: u,
            showLevel: false,
            trailing: IconButton(
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              onPressed: () async {
                final id = await ref.read(chatRepositoryProvider).openChat(me, u, true);
                if (context.mounted) context.push('/messages/$id');
              },
            ),
          );
        },
      ),
    );
  }
}

class _Requests extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(incomingRequestsProvider);
    Future<void> respond(String id, bool accept) async {
      try {
        await ref.read(userRepositoryProvider).respondToRequest(id, accept);
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }

    return AsyncBody<List<FriendRequest>>(
      value: requests,
      isEmpty: (l) => l.isEmpty,
      emptyMessage: context.tr('friends.no_requests'),
      emptyIcon: Icons.mark_email_unread_outlined,
      onRetry: () => ref.invalidate(incomingRequestsProvider),
      data: (list) => ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) {
          final r = list[i];
          return ListTile(
            onTap: () => context.push('/profile/${r.from}'),
            leading: UserAvatar(url: r.fromAvatar, name: r.fromName, size: 46),
            title: Text(r.fromName.isEmpty ? context.tr('friends.someone') : r.fromName),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => respond(r.id, false)),
              IconButton.filled(icon: const Icon(Icons.check_rounded), onPressed: () => respond(r.id, true)),
            ]),
          );
        },
      ),
    );
  }
}

/// Followers / following lists.
class UserListScreen extends ConsumerWidget {
  const UserListScreen({super.key, required this.uid, required this.followers});
  final String uid;
  final bool followers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = followers ? followersProvider(uid) : followingProvider(uid);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(followers ? 'profile.followers' : 'profile.following'))),
      body: AsyncBody<List<AppUser>>(
        value: ref.watch(provider),
        isEmpty: (l) => l.isEmpty,
        emptyMessage: context.tr('common.empty'),
        onRetry: () => ref.invalidate(provider),
        data: (list) => ListView.builder(itemCount: list.length, itemBuilder: (_, i) => UserTile(user: list[i])),
      ),
    );
  }
}
