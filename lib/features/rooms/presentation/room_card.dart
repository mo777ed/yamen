import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/models/models.dart';

/// Opens a room, asking for the password first when the room is private.
Future<void> openRoom(BuildContext context, Room room, {required String myUid}) async {
  String? password;
  if (room.isPrivate && room.ownerId != myUid) {
    password = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(ctx.tr('room.private_title')),
          content: TextField(controller: c, obscureText: true, autofocus: true, decoration: InputDecoration(hintText: ctx.tr('room.password'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ctx.tr('room.enter'))),
          ],
        );
      },
    );
    if (password == null || password.isEmpty) return;
  }
  if (context.mounted) context.push('/room/${room.id}', extra: password);
}

class RoomCard extends StatelessWidget {
  const RoomCard({super.key, required this.room, required this.onTap, this.width = 156, this.height = 190});
  final Room room;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              room.coverUrl.isEmpty
                  ? Container(decoration: const BoxDecoration(gradient: AppColors.primaryGradient), child: const Icon(Icons.mic_rounded, color: Colors.white38, size: 44))
                  : CachedNetworkImage(imageUrl: room.coverUrl, fit: BoxFit.cover, memCacheWidth: 480, errorWidget: (_, __, ___) => Container(color: context.palette.surfaceHigh)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xE6000000)], stops: [0.4, 1]),
                ),
              ),
              PositionedDirectional(
                top: 8,
                start: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.graphic_eq_rounded, size: 13, color: AppColors.success),
                    const SizedBox(width: 3),
                    Text(Fmt.compact(room.memberCount), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              if (room.isPrivate)
                const PositionedDirectional(top: 8, end: 8, child: Icon(Icons.lock_rounded, size: 18, color: AppColors.gold)),
              PositionedDirectional(
                start: 10,
                end: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 4),
                    Row(children: [
                      UserAvatar(url: room.ownerAvatar, name: room.ownerName, size: 18),
                      const SizedBox(width: 5),
                      Expanded(child: Text(room.ownerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                    ]),
                    const SizedBox(height: 4),
                    Text(context.tr('cat.${room.category}'), style: const TextStyle(color: AppColors.gold, fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal carousel used on Home and Discover.
class RoomCarousel extends StatelessWidget {
  const RoomCarousel({super.key, required this.rooms, required this.myUid});
  final List<Room> rooms;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => RoomCard(room: rooms[i], onTap: () => openRoom(context, rooms[i], myUid: myUid)),
      ),
    );
  }
}
