import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_chat/core/constants/roles.dart';
import 'package:yemen_chat/shared/models/models.dart';

void main() {
  test('AppUser.fromMap applies safe defaults', () {
    final u = AppUser.fromMap('u1', {});
    expect(u.level, 1);
    expect(u.role, Role.user);
    expect(u.status, 'active');
    expect(u.profileComplete, isFalse);
    expect(u.handle, '');
  });

  test('AppUser.fromMap reads privacy and role', () {
    final u = AppUser.fromMap('u2', {
      'username': 'ali',
      'role': 'agency_manager',
      'status': 'banned',
      'profileComplete': true,
      'privacy': {'hideOnline': true, 'dmFriendsOnly': true},
      'level': 12,
    });
    expect(u.handle, '@ali');
    expect(u.role, Role.agencyManager);
    expect(u.isBanned, isTrue);
    expect(u.hideOnline, isTrue);
    expect(u.dmFriendsOnly, isTrue);
    expect(u.level, 12);
  });

  test('localized() picks the requested language and falls back', () {
    expect(localized({'ar': 'وردة', 'en': 'Rose'}, arabic: true), 'وردة');
    expect(localized({'ar': 'وردة', 'en': 'Rose'}, arabic: false), 'Rose');
    expect(localized({'en': 'Rose'}, arabic: true), 'Rose');
    expect(localized('plain', arabic: true), 'plain');
    expect(localized(null, arabic: true), '');
  });

  test('Seat/Gift/UserVip parsing from Firestore documents', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('rooms/r1/seats/3').set({'userId': 'u9', 'locked': false, 'micMuted': true});
    await db.doc('rooms/r1/seats/4').set({'userId': null, 'locked': true});
    await db.doc('gifts/rose').set({'name': {'ar': 'وردة', 'en': 'Rose'}, 'price': 10, 'tier': 'big'});

    final s3 = Seat.fromDoc(await db.doc('rooms/r1/seats/3').get());
    final s4 = Seat.fromDoc(await db.doc('rooms/r1/seats/4').get());
    expect(s3.index, 3);
    expect(s3.empty, isFalse);
    expect(s3.micMuted, isTrue);
    expect(s4.empty, isTrue);
    expect(s4.locked, isTrue);

    final g = Gift.fromDoc(await db.doc('gifts/rose').get());
    expect(g.name(false), 'Rose');
    expect(g.isBig, isTrue);
    expect(g.enabled, isTrue);

    expect(UserVip.fromMap({'level': 2, 'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)))}).active, isTrue);
    expect(UserVip.fromMap({'level': 2, 'expiresAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1)))}).active, isFalse);
    expect(const UserVip().active, isFalse);
  });

  test('ChatSummary.otherId and unread', () {
    const c = ChatSummary(id: 'a_b', participants: ['a', 'b'], unread: {'a': 2, 'b': 0});
    expect(c.otherId('a'), 'b');
    expect(c.unreadFor('a'), 2);
    expect(c.unreadFor('zzz'), 0);
  });
}
