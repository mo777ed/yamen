import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';

final notificationsProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) {
  final uid = ref.watch(myUidProvider);
  if (uid.isEmpty) return const Stream.empty();
  return ref
      .watch(firestoreProvider)
      .collection('${Col.notifications}/$uid/items')
      .orderBy('createdAt', descending: true)
      .limit(60)
      .snapshots()
      .map((s) => s.docs.map(AppNotification.fromDoc).toList());
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _icon(String t) {
    switch (t) {
      case 'friend_request':
      case 'friend_accepted':
        return Icons.person_add_alt_1_rounded;
      case 'gift_received':
        return Icons.card_giftcard_rounded;
      case 'room_invitation':
        return Icons.mic_external_on_rounded;
      case 'message':
        return Icons.chat_bubble_rounded;
      case 'mention':
        return Icons.alternate_email_rounded;
      case 'vip':
        return Icons.workspace_premium_rounded;
      case 'follow':
        return Icons.favorite_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  void _open(BuildContext context, AppNotification n) {
    final p = n.payload;
    switch (n.type) {
      case 'friend_request':
      case 'friend_accepted':
        context.push('/friends');
        break;
      case 'gift_received':
        context.push('/wallet');
        break;
      case 'room_invitation':
      case 'mention':
        if (p['roomId'] != null) context.push('/room/${p['roomId']}');
        break;
      case 'message':
        if (p['chatId'] != null) context.push('/messages/${p['chatId']}');
        break;
      case 'follow':
        if (p['from'] != null) context.push('/profile/${p['from']}');
        break;
      case 'vip':
        context.push('/vip');
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    final uid = ref.watch(myUidProvider);
    final db = ref.read(firestoreProvider);

    Future<void> markAll(List<AppNotification> list) async {
      final batch = db.batch();
      for (final n in list.where((n) => !n.read)) {
        batch.update(db.doc('${Col.notifications}/$uid/items/${n.id}'), {'read': true});
      }
      await batch.commit();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('notif.title')),
        actions: [
          if (items.valueOrNull?.any((n) => !n.read) ?? false)
            TextButton(onPressed: () => markAll(items.value!), child: Text(context.tr('notif.mark_all'))),
        ],
      ),
      body: AsyncBody<List<AppNotification>>(
        value: items,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: context.tr('notif.empty'),
        emptyIcon: Icons.notifications_off_outlined,
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (list) => ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (_, i) {
            final n = list[i];
            return ListTile(
              tileColor: n.read ? null : AppColors.primary.withOpacity(0.08),
              leading: CircleAvatar(backgroundColor: context.palette.surfaceHigh, child: Icon(_icon(n.type), color: AppColors.primary)),
              title: Text(context.tr('notif.${n.type}')),
              subtitle: n.createdAt == null ? null : Text(Fmt.dateTime(n.createdAt!, context.isArabic ? 'ar' : 'en'), style: TextStyle(fontSize: 12, color: context.palette.textMuted)),
              onTap: () {
                if (!n.read) db.doc('${Col.notifications}/$uid/items/${n.id}').update({'read': true});
                _open(context, n);
              },
            );
          },
        ),
      ),
    );
  }
}
