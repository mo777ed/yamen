import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/badges.dart';
import '../../../shared/components/speaking_ring.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../rooms/data/room_repository.dart';
import 'voice_providers.dart';

class SeatGrid extends ConsumerWidget {
  const SeatGrid({super.key, required this.roomId, required this.members, required this.onSeatTap});
  final String roomId;
  final Map<String, RoomMember> members;
  final void Function(Seat seat, RoomMember? occupant) onSeatTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seats = ref.watch(roomSeatsProvider(roomId));
    final speaking = ref.watch(speakingProvider).valueOrNull ?? const <String>{};
    return seats.when(
      loading: () => GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        childAspectRatio: 0.8,
        children: List.generate(8, (_) => const Center(child: Skeleton(height: 56, circle: true))),
      ),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text(context.tr('common.error_generic'))),
      data: (list) => RepaintBoundary(
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 0.78, mainAxisSpacing: 4),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final seat = list[i];
            final occupant = seat.empty ? null : members[seat.userId];
            return SeatTile(
              seat: seat,
              occupant: occupant,
              occupantId: seat.userId,
              speaking: !seat.empty && !seat.micMuted && speaking.contains(seat.userId),
              onTap: () => onSeatTap(seat, occupant),
            );
          },
        ),
      ),
    );
  }
}

class SeatTile extends StatelessWidget {
  const SeatTile({super.key, required this.seat, required this.occupant, required this.occupantId, required this.speaking, required this.onTap});
  final Seat seat;
  final RoomMember? occupant;
  final String? occupantId;
  final bool speaking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: seat.empty ? context.tr('seat.empty', {'n': seat.index}) : (occupant?.displayName ?? ''),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SpeakingRing(
              speaking: speaking,
              size: 56,
              child: seat.empty
                  ? Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: p.surface, border: Border.all(color: p.border)),
                      child: Icon(seat.locked ? Icons.lock_rounded : Icons.add_rounded, color: seat.locked ? AppColors.danger : p.textMuted),
                    )
                  : Stack(clipBehavior: Clip.none, children: [
                      UserAvatar(url: occupant?.avatarUrl ?? '', name: occupant?.displayName ?? '', size: 56, vipLevel: occupant?.vipLevel ?? 0),
                      if (seat.micMuted)
                        PositionedDirectional(
                          end: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                            child: const Icon(Icons.mic_off_rounded, size: 12, color: Colors.white),
                          ),
                        ),
                    ]),
            ),
            const SizedBox(height: 4),
            if (seat.empty)
              Text('${seat.index}', style: TextStyle(fontSize: 11, color: p.textMuted))
            else ...[
              Text(occupant?.displayName ?? '…', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                LevelBadge(level: occupant?.level ?? 1),
                if ((occupant?.vipLevel ?? 0) > 0) ...[const SizedBox(width: 3), VipBadge(level: occupant!.vipLevel)],
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
