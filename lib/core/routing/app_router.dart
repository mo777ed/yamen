import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_screens.dart';
import '../../features/agencies/presentation/agency_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/misc_screens.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/discover/presentation/search_screen.dart';
import '../../features/events/presentation/events_screen.dart';
import '../../features/friends/presentation/friends_screen.dart';
import '../../features/games/presentation/games_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/hosts/presentation/host_dashboard_screen.dart';
import '../../features/messages/presentation/messages_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/rankings/presentation/rankings_screen.dart';
import '../../features/reports/presentation/report_screen.dart';
import '../../features/rooms/presentation/create_room_screen.dart';
import '../../features/rooms/presentation/room_list_screen.dart';
import '../../features/settings/presentation/settings_screens.dart';
import '../../features/voice_room/presentation/room_screen.dart';
import '../../features/wallet/presentation/levels_screen.dart';
import '../../features/wallet/presentation/vip_screen.dart';
import '../../features/wallet/presentation/wallet_screen.dart';
import '../storage/local_prefs.dart';
import 'main_shell.dart';

// ---------------------------------------------------------------------
// TEMPORARY PREVIEW BYPASS - set to false (or delete this block) once
// login/Cloud Functions are confirmed working. While true, the app skips
// the entire auth gate and opens straight to /home, so you can browse the
// UI without signing in. Screens that need real data (rooms, profile,
// wallet...) will show a connection/permission error instead of data,
// since you are not actually authenticated with Firebase - that is
// expected and not a bug.
// ---------------------------------------------------------------------
const bool kSkipAuthForPreview = true;

/// Pure redirect decision, kept separate so it can be unit-tested.
String? decideRedirect({required Session? session, required String location, required bool onboarded}) {
  if (kSkipAuthForPreview) {
    if (location == '/splash' || location == '/onboarding' || location.startsWith('/auth') || location == '/banned') {
      return '/home';
    }
    return null;
  }
  final status = session?.status ?? SessionStatus.loading;
  final user = session?.user;
  bool isAuthRoute() => location.startsWith('/auth') || location == '/onboarding';

  switch (status) {
    case SessionStatus.loading:
      return location == '/splash' ? null : '/splash';
    case SessionStatus.signedOut:
      if (isAuthRoute()) return null;
      return onboarded ? '/auth/login' : '/onboarding';
    case SessionStatus.needsProfile:
      return location == '/auth/register' ? null : '/auth/register';
    case SessionStatus.banned:
      return location == '/banned' ? null : '/banned';
    case SessionStatus.active:
      if (isAuthRoute() || location == '/splash' || location == '/banned') return '/home';
      // ---- role guards (the server enforces the same rules; this only hides screens) ----
      final role = user?.role;
      if (location.startsWith('/admin')) {
        if (role == null || !role.isStaff) return '/home';
        final adminOnly = location.startsWith('/admin/collection') || location.startsWith('/admin/agencies') || location.startsWith('/admin/audit');
        if (adminOnly && !role.isAdmin) return '/admin';
      }
      return null;
  }
}

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AsyncValue<Session>>(sessionProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final session = _ref.read(sessionProvider).valueOrNull;
    final onboarded = _ref.read(sharedPrefsProvider).getBool('onboarded') ?? false;
    return decideRedirect(session: session, location: state.matchedLocation, onboarded: onboarded);
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (context, __) => OnboardingScreen(onDone: () async {
          await ref.read(sharedPrefsProvider).setBool('onboarded', true);
          if (context.mounted) context.go('/auth/login');
        }),
      ),
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/auth/otp', builder: (_, __) => const OtpScreen()),
      GoRoute(path: '/auth/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/banned', builder: (_, __) => const BannedScreen()),

      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/discover', builder: (_, __) => const DiscoverScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/messages', builder: (_, __) => const MessagesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/me', builder: (_, __) => const ProfileScreen())]),
        ],
      ),

      GoRoute(path: '/discover/search', builder: (_, __) => const SearchScreen()),
      GoRoute(path: '/messages/:chatId', builder: (_, s) => ChatScreen(chatId: s.pathParameters['chatId']!)),
      GoRoute(path: '/rooms/create', builder: (_, __) => const CreateRoomScreen()),
      GoRoute(path: '/rooms', builder: (_, s) => RoomListScreen(feedName: s.uri.queryParameters['feed'] ?? 'popular')),
      GoRoute(path: '/room/:id', builder: (_, s) => RoomScreen(roomId: s.pathParameters['id']!, password: s.extra as String?)),

      GoRoute(path: '/profile/edit', builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: '/profile/:uid', builder: (_, s) => ProfileScreen(uid: s.pathParameters['uid'])),
      GoRoute(path: '/friends', builder: (_, __) => const FriendsScreen()),
      GoRoute(path: '/followers/:uid', builder: (_, s) => UserListScreen(uid: s.pathParameters['uid']!, followers: true)),
      GoRoute(path: '/following/:uid', builder: (_, s) => UserListScreen(uid: s.pathParameters['uid']!, followers: false)),

      GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen()),
      GoRoute(path: '/wallet/transactions', builder: (_, __) => const TransactionsScreen()),
      GoRoute(path: '/vip', builder: (_, __) => const VipScreen()),
      GoRoute(path: '/levels', builder: (_, __) => const LevelsScreen()),

      GoRoute(path: '/games', builder: (_, __) => const GamesScreen()),
      GoRoute(path: '/games/:id', builder: (_, s) => GameRoomScreen(gameId: s.pathParameters['id']!)),

      GoRoute(path: '/agency/:id', builder: (_, s) => AgencyScreen(agencyId: s.pathParameters['id']!)),
      GoRoute(path: '/host/dashboard', builder: (_, __) => const HostDashboardScreen()),
      GoRoute(path: '/rankings', builder: (_, __) => const RankingsScreen()),
      GoRoute(path: '/events', builder: (_, __) => const EventsScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),

      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/settings/privacy', builder: (_, __) => const PrivacyScreen()),
      GoRoute(path: '/settings/security', builder: (_, __) => const SecurityScreen()),
      GoRoute(path: '/settings/blocked', builder: (_, __) => const BlockedUsersScreen()),
      GoRoute(path: '/settings/about', builder: (_, __) => const AboutScreen()),

      GoRoute(path: '/report/:type/:id', builder: (_, s) => ReportScreen(type: s.pathParameters['type']!, targetId: Uri.decodeComponent(s.pathParameters['id']!))),

      GoRoute(path: '/admin', builder: (_, __) => const AdminHomeScreen()),
      GoRoute(path: '/admin/users', builder: (_, __) => const AdminUsersScreen()),
      GoRoute(path: '/admin/reports', builder: (_, __) => const AdminReportsScreen()),
      GoRoute(path: '/admin/collection/:name', builder: (_, s) => AdminCollectionScreen(collection: s.pathParameters['name']!)),
      GoRoute(path: '/admin/agencies', builder: (_, __) => const AdminAgenciesScreen()),
      GoRoute(path: '/admin/audit', builder: (_, __) => const AdminAuditScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(body: Center(child: Text(state.error?.toString() ?? '404'))),
  );
  ref.onDispose(router.dispose);
  return router;
});
