import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/routing/app_router.dart';
import 'core/services/presence_service.dart';
import 'core/services/push_service.dart';
import 'core/storage/local_prefs.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'l10n/app_strings.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

final presenceServiceProvider = Provider<PresenceService>((ref) => PresenceService(FirebaseDatabase.instance));
final pushServiceProvider = Provider<PushService>((ref) => PushService(FirebaseMessaging.instance, ref.watch(firestoreProvider)));

class YemenChatApp extends ConsumerWidget {
  const YemenChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    final mode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Yemen Chat',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      locale: locale,
      supportedLocales: AppStrings.supported,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) => SessionEffects(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Starts/stops presence and push registration as the user signs in and out.
class SessionEffects extends ConsumerStatefulWidget {
  const SessionEffects({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SessionEffects> createState() => _SessionEffectsState();
}

class _SessionEffectsState extends ConsumerState<SessionEffects> with WidgetsBindingObserver {
  String? _activeUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_activeUid == null) return;
    final presence = ref.read(presenceServiceProvider);
    if (state == AppLifecycleState.resumed) presence.setOnline(true);
    if (state == AppLifecycleState.paused) presence.setOnline(false);
  }

  Future<void> _onSession(Session? s) async {
    final uid = s?.status == SessionStatus.active ? s!.user!.id : null;
    if (uid == _activeUid) return;
    final previous = _activeUid;
    _activeUid = uid;
    final presence = ref.read(presenceServiceProvider);
    final push = ref.read(pushServiceProvider);
    if (uid == null) {
      await presence.stop();
      if (previous != null) await push.unregister(previous);
      await push.stop();
      return;
    }
    presence.start(uid);
    await push.start(
      uid,
      onForeground: (title, body) {
        scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(content: Text([title, body].whereType<String>().where((e) => e.isNotEmpty).join(' — '))));
      },
      onOpen: (data) => ref.read(routerProvider).push(PushService.routeFor(data)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<Session>>(sessionProvider, (_, next) => _onSession(next.valueOrNull));
    return widget.child;
  }
}
