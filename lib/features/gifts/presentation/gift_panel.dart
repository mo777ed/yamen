import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../../shared/widgets/states.dart';
import '../../wallet/data/wallet_repository.dart';
import '../data/gift_repository.dart';

/// Recipient candidates shown at the top of the panel.
class GiftReceiver {
  final String uid;
  final String name;
  final String avatar;
  const GiftReceiver(this.uid, this.name, this.avatar);
}

Future<void> showGiftPanel(BuildContext context, {required String roomId, required List<GiftReceiver> receivers, String? initialReceiverId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GiftPanel(roomId: roomId, receivers: receivers, initialReceiverId: initialReceiverId),
  );
}

class GiftPanel extends ConsumerStatefulWidget {
  const GiftPanel({super.key, required this.roomId, required this.receivers, this.initialReceiverId});
  final String roomId;
  final List<GiftReceiver> receivers;
  final String? initialReceiverId;

  @override
  ConsumerState<GiftPanel> createState() => _GiftPanelState();
}

class _GiftPanelState extends ConsumerState<GiftPanel> {
  String? _receiver;
  Gift? _gift;
  int _qty = 1;
  bool _busy = false;
  String? _key;
  static const _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    _receiver = widget.initialReceiverId ?? (widget.receivers.isNotEmpty ? widget.receivers.first.uid : null);
  }

  void _selectionChanged() => _key = null; // new selection => new idempotency key

  Future<void> _send() async {
    final gift = _gift;
    final receiver = _receiver;
    if (gift == null || receiver == null) return;
    setState(() => _busy = true);
    _key ??= _uuid.v4();
    try {
      await ref.read(giftRepositoryProvider).send(roomId: widget.roomId, receiverId: receiver, giftId: gift.id, qty: _qty, idempotencyKey: _key);
      _key = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('gift.sent'))));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gifts = ref.watch(giftsProvider);
    final wallet = ref.watch(walletProvider).valueOrNull;
    final ar = context.isArabic;
    final total = (_gift?.price ?? 0) * _qty;
    final canAfford = (wallet?.coins ?? 0) >= total;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(
          children: [
            if (widget.receivers.isNotEmpty)
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: widget.receivers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final r = widget.receivers[i];
                    final sel = r.uid == _receiver;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _receiver = r.uid;
                        _selectionChanged();
                      }),
                      child: SizedBox(
                        width: 62,
                        child: Column(children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: sel ? AppColors.primary : Colors.transparent, width: 2)),
                            child: UserAvatar(url: r.avatar, name: r.name, size: 42),
                          ),
                          const SizedBox(height: 4),
                          Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: sel ? AppColors.primary : null)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            Expanded(
              child: AsyncBody<List<Gift>>(
                value: gifts,
                isEmpty: (l) => l.isEmpty,
                emptyMessage: context.tr('gift.none'),
                emptyIcon: Icons.card_giftcard_rounded,
                onRetry: () => ref.invalidate(giftsProvider),
                data: (list) => GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.78),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final g = list[i];
                    final sel = _gift?.id == g.id;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _gift = g;
                        _selectionChanged();
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary.withOpacity(0.16) : context.palette.surfaceHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: sel ? AppColors.primary : Colors.transparent, width: 1.5),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Expanded(child: GiftIcon(url: g.iconUrl, size: 44)),
                          Text(g.name(ar), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.monetization_on_rounded, size: 12, color: AppColors.gold),
                            const SizedBox(width: 2),
                            Text(Fmt.compact(g.price), style: const TextStyle(fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700)),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/wallet');
                    },
                    child: Row(children: [
                      const Icon(Icons.monetization_on_rounded, color: AppColors.gold, size: 20),
                      const SizedBox(width: 4),
                      Text(Fmt.number(wallet?.coins ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const Icon(Icons.chevron_right_rounded, size: 20),
                    ]),
                  ),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _qty,
                    underline: const SizedBox.shrink(),
                    items: [for (final q in [1, 5, 10, 20, 50, 100]) DropdownMenuItem(value: q, child: Text('×$q'))],
                    onChanged: (v) => setState(() {
                      _qty = v ?? 1;
                      _selectionChanged();
                    }),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 132,
                    child: GradientButton(
                      height: 44,
                      label: canAfford ? context.tr('gift.send') : context.tr('gift.recharge'),
                      gradient: AppColors.goldGradient,
                      loading: _busy,
                      onPressed: _gift == null || _receiver == null
                          ? null
                          : canAfford
                              ? _send
                              : () {
                                  Navigator.of(context).pop();
                                  context.push('/wallet');
                                },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Network gift icon with a graceful fallback.
class GiftIcon extends StatelessWidget {
  const GiftIcon({super.key, required this.url, this.size = 44});
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return Icon(Icons.card_giftcard_rounded, size: size * 0.8, color: AppColors.gold);
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      memCacheWidth: (size * 3).toInt(),
      errorWidget: (_, __, ___) => Icon(Icons.card_giftcard_rounded, size: size * 0.8, color: AppColors.gold),
    );
  }
}
