import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../models/models.dart';
import 'badges.dart';
import 'user_avatar.dart';

class UserTile extends StatelessWidget {
  const UserTile({super.key, required this.user, this.trailing, this.onTap, this.showLevel = true, this.subtitle});
  final AppUser user;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showLevel;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      onTap: onTap ?? () => context.push('/profile/${user.id}'),
      leading: UserAvatar(url: user.avatarUrl, name: user.displayName, size: 48, vipLevel: user.vipLevel),
      title: Row(children: [
        Flexible(child: Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        if (showLevel && user.username.isNotEmpty) ...[const SizedBox(width: 6), LevelBadge(level: user.level)],
        if (user.vipLevel > 0) ...[const SizedBox(width: 4), VipBadge(level: user.vipLevel)],
      ]),
      subtitle: (subtitle ?? user.handle).isEmpty ? null : Text(subtitle ?? user.handle, style: TextStyle(color: context.palette.textMuted, fontSize: 12.5)),
      trailing: trailing,
    );
  }
}

/// Compact avatar + name for horizontal lists.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.id, required this.name, required this.avatar, this.vipLevel = 0, this.online});
  final String id;
  final String name;
  final String avatar;
  final int vipLevel;
  final bool? online;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/profile/$id'),
      child: SizedBox(
        width: 68,
        child: Column(children: [
          UserAvatar(url: avatar, name: name, size: 58, vipLevel: vipLevel, online: online),
          const SizedBox(height: 6),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
