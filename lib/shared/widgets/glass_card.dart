import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Rounded card. Blur is opt-in because BackdropFilter is expensive in long lists.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.blur = false,
    this.radius = AppRadius.card,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool blur;
  final double radius;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = BorderRadius.circular(radius);
    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? p.surface.withOpacity(blur ? 0.6 : 1) : null,
        gradient: gradient,
        borderRadius: r,
        border: Border.all(color: p.border),
      ),
      child: child,
    );
    if (blur) {
      body = ClipRRect(borderRadius: r, child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: body));
    }
    if (onTap == null) return body;
    return InkWell(borderRadius: r, onTap: onTap, child: body);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!, style: const TextStyle(color: AppColors.primary))),
        ],
      ),
    );
  }
}
