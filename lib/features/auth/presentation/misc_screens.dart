import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../data/auth_repository.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(30)),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 52),
          ),
          const SizedBox(height: 20),
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
        ]),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _c = PageController();
  int _page = 0;
  static const _pages = [
    (Icons.mic_external_on_rounded, 'onb.1_title', 'onb.1_body'),
    (Icons.card_giftcard_rounded, 'onb.2_title', 'onb.2_body'),
    (Icons.groups_rounded, 'onb.3_title', 'onb.3_body'),
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: widget.onDone, child: Text(context.tr('onb.skip')))),
          Expanded(
            child: PageView.builder(
              controller: _c,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(44)),
                    child: Icon(_pages[i].$1, size: 70, color: Colors.white),
                  ),
                  const SizedBox(height: 32),
                  Text(context.tr(_pages[i].$2), textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  Text(context.tr(_pages[i].$3), textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted, height: 1.5)),
                ]),
              ),
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _pages.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                width: i == _page ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(color: i == _page ? AppColors.primary : context.palette.border, borderRadius: BorderRadius.circular(8)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: GradientButton(
              label: last ? context.tr('onb.start') : context.tr('common.next'),
              onPressed: () => last ? widget.onDone() : _c.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
            ),
          ),
        ]),
      ),
    );
  }
}

class BannedScreen extends ConsumerWidget {
  const BannedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.gpp_bad_rounded, size: 80, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(context.tr('banned.title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(context.tr('banned.body'), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: () => ref.read(authRepositoryProvider).signOut(), child: Text(context.tr('settings.logout'))),
          ]),
        ),
      ),
    );
  }
}
