import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/badges.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../../shared/widgets/states.dart';
import '../data/wallet_repository.dart';

class VipScreen extends ConsumerStatefulWidget {
  const VipScreen({super.key});
  @override
  ConsumerState<VipScreen> createState() => _VipScreenState();
}

class _VipScreenState extends ConsumerState<VipScreen> {
  int? _busyLevel;

  Future<void> _buy(VipLevel v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('vip.confirm_title', {'level': v.level})),
        content: Text(ctx.tr('vip.confirm_body', {'price': Fmt.number(v.price), 'days': v.durationDays})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('vip.activate'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyLevel = v.level);
    try {
      await ref.read(walletRepositoryProvider).purchaseVip(v.level);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('vip.activated'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busyLevel = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final levels = ref.watch(vipLevelsProvider);
    final mine = ref.watch(userVipProvider).valueOrNull ?? const UserVip();
    return Scaffold(
      appBar: AppBar(title: const Text('VIP')),
      body: AsyncBody<List<VipLevel>>(
        value: levels,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: context.tr('vip.none'),
        emptyIcon: Icons.workspace_premium_rounded,
        onRetry: () => ref.invalidate(vipLevelsProvider),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (mine.active)
              GlassCard(
                gradient: AppColors.goldGradient,
                child: Row(children: [
                  const Icon(Icons.workspace_premium_rounded, color: Color(0xFF3A2500), size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(context.tr('vip.current', {'level': mine.level, 'date': Fmt.date(mine.expiresAt!, context.isArabic ? 'ar' : 'en')}),
                        style: const TextStyle(color: Color(0xFF3A2500), fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            for (final v in list)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      VipBadge(level: v.level),
                      const Spacer(),
                      const Icon(Icons.monetization_on_rounded, size: 18, color: AppColors.gold),
                      const SizedBox(width: 4),
                      Text('${Fmt.number(v.price)} / ${v.durationDays}${context.tr('vip.days_short')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (v.giftDiscountPct > 0) _perk(context.tr('vip.perk_discount', {'p': v.giftDiscountPct})),
                      if (v.perks['frame'] == true) _perk(context.tr('vip.perk_frame')),
                      if (v.perks['entrance'] == true) _perk(context.tr('vip.perk_entrance')),
                      if (v.perks['nickname'] == true) _perk(context.tr('vip.perk_nickname')),
                      if (v.perks['rooms'] == true) _perk(context.tr('vip.perk_rooms')),
                    ]),
                    const SizedBox(height: 12),
                    GradientButton(
                      height: 44,
                      gradient: AppColors.goldGradient,
                      label: mine.level == v.level && mine.active ? context.tr('vip.extend') : context.tr('vip.activate'),
                      loading: _busyLevel == v.level,
                      onPressed: _busyLevel == null ? () => _buy(v) : null,
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _perk(String t) => Chip(label: Text(t, style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact, avatar: const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success));
}
