import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/badges.dart';
import '../../../shared/components/user_tile.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/user_repository.dart';
import '../../rooms/data/room_repository.dart';
import '../../rooms/presentation/room_card.dart';
import '../../wallet/data/wallet_repository.dart';

final bannersProvider = StreamProvider<List<BannerItem>>((ref) => ref
    .watch(firestoreProvider)
    .collection(Col.banners)
    .where('active', isEqualTo: true)
    .limit(8)
    .snapshots()
    .map((s) => s.docs.map(BannerItem.fromDoc).toList()));

final unreadNotificationsProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(myUidProvider);
  if (uid.isEmpty) return const Stream.empty();
  return ref
      .watch(firestoreProvider)
      .collection('${Col.notifications}/$uid/items')
      .where('read', isEqualTo: false)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isNotEmpty);
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _claimDaily());
  }

  Future<void> _claimDaily() async {
    try {
      final res = await ref.read(functionsClientProvider).call(Fn.claimDailyLogin);
      if (res['claimed'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('home.daily_reward', {'coins': res['coins'] ?? 0}))));
      }
    } catch (_) {/* daily reward is best-effort */}
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final myUid = ref.watch(myUidProvider);
    final wallet = ref.watch(walletProvider).valueOrNull;
    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? false;
    final online = ref.watch(isOnlineOrTrue);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (!online) const OfflineBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (r) => AppColors.primaryGradient.createShader(r),
                    child: Text(context.tr('app.name'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                  const Spacer(),
                  IconButton(onPressed: () => context.push('/discover/search'), icon: const Icon(Icons.search_rounded)),
                  Stack(children: [
                    IconButton(onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_none_rounded)),
                    if (unread)
                      const PositionedDirectional(top: 10, end: 10, child: CircleAvatar(radius: 4.5, backgroundColor: AppColors.danger)),
                  ]),
                  CoinChip(amount: Fmt.compact(wallet?.coins ?? 0), onTap: () => context.push('/wallet')),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(roomFeedProvider);
                  ref.invalidate(activeUsersProvider);
                  await Future<void>.delayed(const Duration(milliseconds: 500));
                },
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    const _BannerCarousel(),
                    _RoomSection(titleKey: 'home.featured', feed: (feed: RoomFeed.featured, arg: null), myUid: myUid, hideWhenEmpty: true),
                    _RoomSection(titleKey: 'home.popular', feed: (feed: RoomFeed.popular, arg: null), myUid: myUid, seeAll: 'popular'),
                    _RoomSection(titleKey: 'home.new', feed: (feed: RoomFeed.newest, arg: null), myUid: myUid, seeAll: 'newest'),
                    _RoomSection(
                      titleKey: 'home.recommended',
                      feed: (feed: RoomFeed.recommended, arg: me?.country),
                      myUid: myUid,
                      hideWhenEmpty: true,
                    ),
                    SectionHeader(title: context.tr('home.active_users')),
                    const _ActiveUsers(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Online state as a plain bool for widgets (defaults to true while loading).
final isOnlineOrTrue = Provider<bool>((ref) => ref.watch(isOnlineProvider).valueOrNull ?? true);

class _RoomSection extends ConsumerWidget {
  const _RoomSection({required this.titleKey, required this.feed, required this.myUid, this.seeAll, this.hideWhenEmpty = false});
  final String titleKey;
  final RoomFeedKey feed;
  final String myUid;
  final String? seeAll;
  final bool hideWhenEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomFeedProvider(feed));
    return rooms.when(
      loading: () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SectionHeader(title: context.tr(titleKey)), const SkeletonCards()]),
      error: (e, _) => hideWhenEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.all(16), child: ErrorState(error: e, onRetry: () => ref.invalidate(roomFeedProvider(feed)))),
      data: (list) {
        if (list.isEmpty) {
          if (hideWhenEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(title: context.tr(titleKey)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(context.tr('home.no_rooms'), style: TextStyle(color: context.palette.textMuted))),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionHeader(
            title: context.tr(titleKey),
            actionLabel: seeAll == null ? null : context.tr('common.see_all'),
            onAction: seeAll == null ? null : () => context.push('/rooms?feed=$seeAll'),
          ),
          RoomCarousel(rooms: list, myUid: myUid),
        ]);
      },
    );
  }
}

class _ActiveUsers extends ConsumerWidget {
  const _ActiveUsers();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(activeUsersProvider);
    return users.when(
      loading: () => const SizedBox(height: 88),
      error: (e, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(context.tr('home.no_active'), style: TextStyle(color: context.palette.textMuted)));
        }
        return SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => UserBubble(id: list[i].id, name: list[i].displayName, avatar: list[i].avatarUrl, vipLevel: list[i].vipLevel, online: true),
          ),
        );
      },
    );
  }
}

class _BannerCarousel extends ConsumerWidget {
  const _BannerCarousel();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(bannersProvider).valueOrNull ?? const [];
    if (banners.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 128,
        child: PageView.builder(
          controller: PageController(viewportFraction: 0.92),
          itemCount: banners.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(imageUrl: banners[i].imageUrl, fit: BoxFit.cover, errorWidget: (_, __, ___) => GlassCard(child: const SizedBox.expand())),
            ),
          ),
        ),
      ),
    );
  }
}
