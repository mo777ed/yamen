import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Circular avatar with initial fallback and optional VIP frame.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.url, this.name = '', this.size = 44, this.vipLevel = 0, this.online});
  final String url;
  final String name;
  final double size;
  final int vipLevel;
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final fallback = Container(
      color: context.palette.surfaceHigh,
      alignment: Alignment.center,
      child: Text(initial, style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: context.palette.textMuted)),
    );
    final image = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: (size * 3).toInt(),
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
    Widget framed = image;
    if (vipLevel > 0) {
      framed = Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.goldGradient),
        child: image,
      );
    }
    if (online == null) return framed;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        framed,
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: Container(
            width: size * 0.26,
            height: size * 0.26,
            decoration: BoxDecoration(
              color: online! ? AppColors.success : context.palette.textMuted,
              shape: BoxShape.circle,
              border: Border.all(color: context.palette.bg, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
