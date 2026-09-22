import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final color = level >= 50 ? AppColors.gold : level >= 20 ? AppColors.secondary : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.6))),
      child: Text('Lv.$level', style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
    );
  }
}

class VipBadge extends StatelessWidget {
  const VipBadge({super.key, required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    if (level <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(gradient: AppColors.goldGradient, borderRadius: BorderRadius.circular(999)),
      child: Text('VIP$level', style: const TextStyle(color: Color(0xFF3A2500), fontSize: 10.5, fontWeight: FontWeight.w900)),
    );
  }
}

class CoinChip extends StatelessWidget {
  const CoinChip({super.key, required this.amount, this.onTap, this.icon = Icons.monetization_on_rounded, this.color = AppColors.gold});
  final String amount;
  final VoidCallback? onTap;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: context.palette.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ]),
      ),
    );
  }
}
