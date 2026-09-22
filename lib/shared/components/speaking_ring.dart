import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Animated ring around an avatar while the user is speaking.
class SpeakingRing extends StatefulWidget {
  const SpeakingRing({super.key, required this.speaking, required this.child, this.size = 64});
  final bool speaking;
  final Widget child;
  final double size;

  @override
  State<SpeakingRing> createState() => _SpeakingRingState();
}

class _SpeakingRingState extends State<SpeakingRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SpeakingRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (widget.speaking && !reduce) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.size * 0.14;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = widget.speaking ? (MediaQuery.of(context).disableAnimations ? 1.0 : _c.value) : 0.0;
          return Container(
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: widget.speaking ? AppColors.success.withOpacity(0.5 + 0.5 * t) : Colors.transparent, width: 2.5),
              boxShadow: widget.speaking ? [BoxShadow(color: AppColors.success.withOpacity(0.35 * t), blurRadius: 14 * t, spreadRadius: 2 * t)] : null,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
