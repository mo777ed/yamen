import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/badges.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../gifts/presentation/gift_panel.dart';
import '../../rooms/data/room_repository.dart';

const kEmojis = [
  '😀', '😂', '🥹', '😍', '😎', '🤩', '😘', '🥳', '😇', '🤗', '🤔', '😴',
  '😢', '😭', '😡', '🤯', '👍', '👏', '🙏', '💪', '🔥', '💯', '❤️', '💔',
  '🎉', '🎶', '🎤', '🎧', '🌹', '👑', '💎', '🚀', '☕', '🍰', '🌙', '⭐',
];

class RoomChat extends ConsumerWidget {
  const RoomChat({super.key, required this.roomId, required this.onLongPress, required this.onTapUser});
  final String roomId;
  final void Function(RoomMessage) onLongPress;
  final void Function(String uid) onTapUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(roomMessagesProvider(roomId));
    return messages.when(
      loading: () => const SkeletonList(count: 4),
      error: (e, _) => Center(child: Text(context.tr('common.error_generic'))),
      data: (list) {
        if (list.isEmpty) return Center(child: Text(context.tr('room.chat_empty'), style: TextStyle(color: context.palette.textMuted)));
        return ListView.builder(
          reverse: true, // list is newest-first, so index 0 sits at the bottom
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: list.length,
          itemBuilder: (_, i) => _MessageRow(message: list[i], onLongPress: onLongPress, onTapUser: onTapUser),
        );
      },
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, required this.onLongPress, required this.onTapUser});
  final RoomMessage message;
  final void Function(RoomMessage) onLongPress;
  final void Function(String uid) onTapUser;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final p = context.palette;
    if (m.type == 'join') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Center(
          child: Text(context.tr('room.joined', {'name': m.text}), style: TextStyle(color: p.textMuted, fontSize: 12)),
        ),
      );
    }
    if (m.type == 'system') {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Center(child: Text(m.text, style: TextStyle(color: p.textMuted, fontSize: 12))));
    }
    if (m.isGift) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withOpacity(0.4)),
          ),
          child: Row(children: [
            GiftIcon(url: m.giftIcon, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('gift.chat_line', {'sender': m.senderName, 'receiver': m.receiverName, 'qty': m.qty, 'gift': m.giftName(context.isArabic)}),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onLongPress: () => onLongPress(m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(onTap: () => onTapUser(m.senderId), child: UserAvatar(url: m.senderAvatar, name: m.senderName, size: 32)),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(child: Text(m.senderName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.secondary))),
                      const SizedBox(width: 6),
                      LevelBadge(level: m.senderLevel),
                    ]),
                    const SizedBox(height: 2),
                    Text(m.text, style: const TextStyle(fontSize: 14)),
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

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({super.key, required this.controller, required this.onSend, required this.enabled, required this.disabledHint});
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  final String disabledHint;

  Future<void> _emoji(BuildContext context) async {
    final e = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [for (final e in kEmojis) InkWell(onTap: () => Navigator.pop(ctx, e), child: Center(child: Text(e, style: const TextStyle(fontSize: 28))))],
        ),
      ),
    );
    if (e != null) {
      final t = controller.text;
      controller.text = '$t$e';
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLength: AppLimits.roomChatMaxLength,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => onSend(),
      decoration: InputDecoration(
        counterText: '',
        hintText: enabled ? context.tr('room.say_something') : disabledHint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        prefixIcon: IconButton(icon: const Icon(Icons.emoji_emotions_outlined), onPressed: enabled ? () => _emoji(context) : null),
        suffixIcon: IconButton(icon: const Icon(Icons.send_rounded, color: AppColors.primary), onPressed: enabled ? onSend : null),
      ),
    );
  }
}
