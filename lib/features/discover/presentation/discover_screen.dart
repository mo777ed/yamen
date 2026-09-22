import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_tile.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/user_repository.dart';
import '../../rooms/data/room_repository.dart';
import '../../rooms/presentation/room_card.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  String? _category; // null = trending

  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(myUidProvider);
    final RoomFeedKey feed = _category == null ? (feed: RoomFeed.popular, arg: null) : (feed: RoomFeed.category, arg: _category);
    final rooms = ref.watch(roomFeedProvider(feed));

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('nav.discover'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () => context.push('/discover/search'),
              child: AbsorbPointer(child: TextField(decoration: InputDecoration(hintText: context.tr('search.hint'), prefixIcon: const Icon(Icons.search_rounded)))),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip(context.tr('discover.trending'), _category == null, () => setState(() => _category = null)),
                for (final c in RoomCategory.all) _chip(context.tr('cat.$c'), _category == c, () => setState(() => _category = c)),
              ],
            ),
          ),
          SectionHeader(title: _category == null ? context.tr('discover.trending_rooms') : context.tr('cat.$_category')),
          rooms.when(
            loading: () => const SkeletonCards(),
            error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(context.tr('common.error_generic'))),
            data: (list) => list.isEmpty
                ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(context.tr('home.no_rooms'), style: TextStyle(color: context.palette.textMuted)))
                : RoomCarousel(rooms: list, myUid: myUid),
          ),
          _usersRow(context.tr('discover.popular_users'), ref.watch(popularUsersProvider)),
          SectionHeader(title: context.tr('discover.popular_hosts')),
          ref.watch(popularHostsProvider).when(
                loading: () => const SizedBox(height: 92),
                error: (_, __) => const SizedBox.shrink(),
                data: (hosts) => hosts.isEmpty
                    ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(context.tr('common.empty'), style: TextStyle(color: context.palette.textMuted)))
                    : _bubbles([for (final h in hosts) UserBubble(id: h.uid, name: h.displayName, avatar: h.avatarUrl)]),
              ),
          _usersRow(context.tr('discover.new_users'), ref.watch(newUsersProvider)),
          _usersRow(context.tr('discover.vip_users'), ref.watch(vipUsersProvider)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: AppColors.primary.withOpacity(0.25),
          side: BorderSide(color: selected ? AppColors.primary : context.palette.border),
        ),
      );

  Widget _bubbles(List<Widget> items) => SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => items[i],
        ),
      );

  Widget _usersRow(String title, AsyncValue<List<AppUser>> value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title: title),
      value.when(
        loading: () => const SizedBox(height: 92),
        error: (_, __) => const SizedBox.shrink(),
        data: (list) => list.isEmpty
            ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(context.tr('common.empty'), style: TextStyle(color: context.palette.textMuted)))
            : _bubbles([for (final u in list) UserBubble(id: u.id, name: u.displayName, avatar: u.avatarUrl, vipLevel: u.vipLevel)]),
      ),
    ]);
  }
}
