import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_chat/core/constants/roles.dart';

void main() {
  test('parse/wire round trip', () {
    for (final r in Role.values) {
      expect(Role.parse(r.wire), r);
    }
    expect(Role.parse(null), Role.user);
    expect(Role.parse('nonsense'), Role.user);
  });

  test('ranking matches server (user < host < agency_manager < moderator < admin < super_admin)', () {
    final ranks = [Role.user, Role.host, Role.agencyManager, Role.moderator, Role.admin, Role.superAdmin].map((r) => r.rank).toList();
    expect(ranks, [0, 1, 2, 3, 4, 5]);
  });

  test('staff and admin checks', () {
    expect(Role.user.isStaff, isFalse);
    expect(Role.host.isStaff, isFalse);
    expect(Role.moderator.isStaff, isTrue);
    expect(Role.moderator.isAdmin, isFalse);
    expect(Role.admin.isAdmin, isTrue);
    expect(Role.superAdmin.isAdmin, isTrue);
  });

  test('room roles', () {
    expect(RoomRole.parse('mod'), RoomRole.mod);
    expect(RoomRole.parse('x'), RoomRole.listener);
    expect(RoomRole.listener.canManage, isFalse);
    expect(RoomRole.speaker.canManage, isFalse);
    expect(RoomRole.mod.canManage, isTrue);
    expect(RoomRole.owner.atLeast(RoomRole.admin), isTrue);
  });
}
