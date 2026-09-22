import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_chat/core/constants/roles.dart';
import 'package:yemen_chat/core/routing/app_router.dart';
import 'package:yemen_chat/features/auth/data/auth_repository.dart';
import 'package:yemen_chat/shared/models/models.dart';

Session active(Role role) => Session(SessionStatus.active, AppUser(id: 'u1', role: role, profileComplete: true));

void main() {
  group('auth guard', () {
    test('loading -> splash', () {
      expect(decideRedirect(session: const Session(SessionStatus.loading), location: '/home', onboarded: true), '/splash');
      expect(decideRedirect(session: const Session(SessionStatus.loading), location: '/splash', onboarded: true), isNull);
    });
    test('signed out goes to onboarding first, then login', () {
      const s = Session(SessionStatus.signedOut);
      expect(decideRedirect(session: s, location: '/home', onboarded: false), '/onboarding');
      expect(decideRedirect(session: s, location: '/home', onboarded: true), '/auth/login');
      expect(decideRedirect(session: s, location: '/auth/otp', onboarded: true), isNull);
    });
    test('incomplete profile is forced to register', () {
      const s = Session(SessionStatus.needsProfile);
      expect(decideRedirect(session: s, location: '/home', onboarded: true), '/auth/register');
      expect(decideRedirect(session: s, location: '/auth/register', onboarded: true), isNull);
    });
    test('banned users can only see the banned screen', () {
      const s = Session(SessionStatus.banned);
      expect(decideRedirect(session: s, location: '/room/abc', onboarded: true), '/banned');
    });
    test('signed-in user is moved away from auth screens', () {
      expect(decideRedirect(session: active(Role.user), location: '/auth/login', onboarded: true), '/home');
      expect(decideRedirect(session: active(Role.user), location: '/splash', onboarded: true), '/home');
      expect(decideRedirect(session: active(Role.user), location: '/wallet', onboarded: true), isNull);
    });
  });

  group('role guard', () {
    test('normal users cannot open /admin', () {
      expect(decideRedirect(session: active(Role.user), location: '/admin', onboarded: true), '/home');
      expect(decideRedirect(session: active(Role.host), location: '/admin/users', onboarded: true), '/home');
    });
    test('moderators can open reports/users but not config editors', () {
      expect(decideRedirect(session: active(Role.moderator), location: '/admin/reports', onboarded: true), isNull);
      expect(decideRedirect(session: active(Role.moderator), location: '/admin/users', onboarded: true), isNull);
      expect(decideRedirect(session: active(Role.moderator), location: '/admin/collection/gifts', onboarded: true), '/admin');
      expect(decideRedirect(session: active(Role.moderator), location: '/admin/agencies', onboarded: true), '/admin');
      expect(decideRedirect(session: active(Role.moderator), location: '/admin/audit', onboarded: true), '/admin');
    });
    test('admins can open everything', () {
      for (final p in ['/admin', '/admin/collection/gifts', '/admin/agencies', '/admin/audit']) {
        expect(decideRedirect(session: active(Role.admin), location: p, onboarded: true), isNull);
      }
    });
  });
}
