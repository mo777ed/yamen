import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/models/models.dart';
import '../../rooms/data/room_repository.dart';
import 'gift_panel.dart';

/// Watches room messages and plays gift effects one at a time:
/// small/medium gifts -> a banner, big gifts -> a full-screen Lottie.
/// Only ONE effect is on screen at any moment so it can never hurt frame rate.
class GiftOverlay extends ConsumerStatefulWidget {
  const GiftOverlay({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<GiftOverlay> createState() => _GiftOverlayState();
}

class _GiftOverlayState extends ConsumerState<GiftOverlay> {
  final _seen = <String>{};
  final _queue = <RoomMessage>[];
  RoomMessage? _current;
  bool _primed = false;

  void _onMessages(List<RoomMessage> list) {
    if (!_primed) {
      // Ignore the history that is already in the room when we join.
      _seen.addAll(list.map((m) => m.id));
      _primed = true;
      return;
    }
    for (final m in list.reversed) {
      if (_seen.add(m.id) && m.isGift) {
        final age = m.createdAt == null ? Duration.zero : DateTime.now().difference(m.createdAt!);
        if (age.inSeconds < 20) _queue.add(m);
      }
    }
    if (_queue.length > 8) _queue.removeRange(0, _queue.length - 8); // drop backlog under burst
    _next();
  }

  void _next() {
    if (_current != null || _queue.isEmpty || !mounted) return;
    setState(() => _current = _queue.removeAt(0));
  }

  void _done() {
    if (!mounted) return;
    setState(() => _current = null);
    _next();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<RoomMessage>>>(roomMessagesProvider(widget.roomId), (_, next) => next.whenData(_onMessages));
    final m = _current;
    if (m == null) return const SizedBox.shrink();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (m.giftTier == 'big' && m.giftAnimation.isNotEmpty && !reduce) {
      return _FullScreenGift(key: ValueKey(m.id), message: m, onDone: _done);
    }
    return _GiftBanner(key: ValueKey(m.id), message: m, onDone: _done);
  }
}

class _GiftBanner extends StatefulWidget {
  const _GiftBanner({super.key, required this.message, required this.onDone});
  final RoomMessage message;
  final VoidCallback onDone;
  @override
  State<_GiftBanner> createState() => _GiftBannerState();
}

class _GiftBannerState extends State<_GiftBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _t = Timer(const Duration(milliseconds: 2600), () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final ar = context.isArabic;
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: const Alignment(0, -0.55),
          child: SlideTransition(
            position: Tween(begin: const Offset(0.6, 0), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
            child: FadeTransition(
              opacity: _c,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xCC7C5CFF), Color(0xCC3D8BFF)]),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.gold.withOpacity(0.7)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(
                      context.tr('gift.banner', {'sender': m.senderName, 'receiver': m.receiverName}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GiftIcon(url: m.giftIcon, size: 30),
                  const SizedBox(width: 4),
                  Text('×${m.qty}', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(width: 4),
                  Text(m.giftName(ar), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullScreenGift extends StatefulWidget {
  const _FullScreenGift({super.key, required this.message, required this.onDone});
  final RoomMessage message;
  final VoidCallback onDone;
  @override
  State<_FullScreenGift> createState() => _FullScreenGiftState();
}

class _FullScreenGiftState extends State<_FullScreenGift> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Timer? _failsafe;

  @override
  void initState() {
    super.initState();
    // If the animation cannot load, never leave the screen blocked.
    _failsafe = Timer(const Duration(seconds: 8), widget.onDone);
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Stack(alignment: Alignment.center, children: [
            Lottie.network(
              m.giftAnimation,
              controller: _c,
              fit: BoxFit.contain,
              onLoaded: (comp) {
                _failsafe?.cancel();
                _c.duration = comp.duration > const Duration(seconds: 6) ? const Duration(seconds: 6) : comp.duration;
                _c.forward().whenComplete(widget.onDone);
              },
              errorBuilder: (_, __, ___) {
                WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
                return const SizedBox.shrink();
              },
            ),
            Positioned(
              bottom: 150,
              child: Text(
                context.tr('gift.banner', {'sender': m.senderName, 'receiver': m.receiverName}),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
