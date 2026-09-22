import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../data/room_repository.dart';
import 'room_card.dart';

/// Full grid for "see all". [feedName] is popular | newest.
class RoomListScreen extends ConsumerWidget {
  const RoomListScreen({super.key, required this.feedName});
  final String feedName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = feedName == 'newest' ? RoomFeed.newest : RoomFeed.popular;
    final key = (feed: feed, arg: null as String?);
    final async = ref.watch(roomFeedProvider(key));
    final myUid = ref.watch(myUidProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr(feed == RoomFeed.newest ? 'home.new' : 'home.popular'))),
      body: AsyncBody<List<Room>>(
        value: async,
        loading: const SkeletonList(),
        isEmpty: (l) => l.isEmpty,
        emptyMessage: context.tr('home.no_rooms'),
        onRetry: () => ref.invalidate(roomFeedProvider(key)),
        data: (rooms) => GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82),
          itemCount: rooms.length,
          itemBuilder: (_, i) => RoomCard(room: rooms[i], width: double.infinity, height: double.infinity, onTap: () => openRoom(context, rooms[i], myUid: myUid)),
        ),
      ),
    );
  }
}
