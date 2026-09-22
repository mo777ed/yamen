import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/messages/data/chat_repository.dart';
import '../../l10n/app_strings.dart';
import '../theme/app_colors.dart';

/// Home · Discover · [Create room] · Messages · Profile
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myUidProvider);
    final unread = (ref.watch(chatsProvider).valueOrNull ?? const []).fold<int>(0, (a, c) => a + c.unreadFor(me));
    final p = context.palette;

    Widget item(IconData icon, IconData active, String label, int branch, {int badge = 0}) {
      final selected = shell.currentIndex == branch;
      return Expanded(
        child: InkWell(
          onTap: () => shell.goBranch(branch, initialLocation: branch == shell.currentIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text(badge > 99 ? '99+' : '$badge'),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(selected ? active : icon, key: ValueKey(selected), color: selected ? AppColors.primary : p.textMuted, size: 26),
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, color: selected ? AppColors.primary : p.textMuted)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(children: [
              item(Icons.home_outlined, Icons.home_rounded, context.tr('nav.home'), 0),
              item(Icons.explore_outlined, Icons.explore_rounded, context.tr('nav.discover'), 1),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () => context.push('/rooms/create'),
                    child: Semantics(
                      button: true,
                      label: context.tr('room.create'),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 5))],
                        ),
                        child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ),
              ),
              item(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, context.tr('nav.messages'), 2, badge: unread),
              item(Icons.person_outline_rounded, Icons.person_rounded, context.tr('nav.profile'), 3),
            ]),
          ),
        ),
      ),
    );
  }
}
