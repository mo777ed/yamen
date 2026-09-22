import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yemen_chat/features/profile/data/user_repository.dart';

import '../helpers/mocks.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFunctionsClient fn;
  late UserRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    fn = fnMock();
    repo = UserRepository(db, fn);
  });

  test('follow/unfollow use the deterministic doc id required by the rules', () async {
    await repo.follow('a', 'b');
    final doc = await db.doc('follows/a_b').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['followerId'], 'a');
    expect(doc.data()!['followeeId'], 'b');
    expect(await repo.watchIsFollowing('a', 'b').first, isTrue);
    await repo.unfollow('a', 'b');
    expect(await repo.watchIsFollowing('a', 'b').first, isFalse);
  });

  test('blocking also removes an existing follow', () async {
    await repo.follow('a', 'b');
    await repo.block('a', 'b');
    expect(await repo.watchIsBlocked('a', 'b').first, isTrue);
    expect((await db.doc('follows/a_b').get()).exists, isFalse);
    expect(await repo.blockedIds('a'), ['b']);
    await repo.unblock('a', 'b');
    expect(await repo.blockedIds('a'), isEmpty);
  });

  test('friend state machine', () async {
    expect(await repo.friendState('a', 'b'), FriendState.none);
    await repo.sendFriendRequest('a', 'b');
    expect(await repo.friendState('a', 'b'), FriendState.requestSent);
    expect(await repo.friendState('b', 'a'), FriendState.requestReceived);
    await db.doc('friends/a/list/b').set({'displayName': 'B'});
    expect(await repo.friendState('a', 'b'), FriendState.friends);
  });

  test('friend request is created as pending (the only status rules allow)', () async {
    await repo.sendFriendRequest('a', 'b');
    final d = (await db.collection('friend_requests').get()).docs.single.data();
    expect(d['status'], 'pending');
    expect(d['from'], 'a');
    expect(d['to'], 'b');
  });

  test('respond and remove go through Cloud Functions', () async {
    await repo.respondToRequest('req1', true);
    verify(() => fn.call('respondFriendRequest', {'requestId': 'req1', 'accept': true})).called(1);
    await repo.removeFriend('b');
    verify(() => fn.call('removeFriend', {'uid': 'b'})).called(1);
  });

  test('user search is a case-insensitive username prefix search over completed profiles', () async {
    await db.doc('users/1').set({'usernameLower': 'ali_khan', 'profileComplete': true, 'status': 'active', 'displayName': 'Ali'});
    await db.doc('users/2').set({'usernameLower': 'alia', 'profileComplete': true, 'status': 'active'});
    await db.doc('users/3').set({'usernameLower': 'ali_banned', 'profileComplete': true, 'status': 'banned'});
    await db.doc('users/4').set({'usernameLower': 'bob', 'profileComplete': true, 'status': 'active'});
    final res = await repo.searchUsers('@ALI');
    expect(res.map((u) => u.id).toSet(), {'1', '2'});
    expect(await repo.searchUsers('a'), isEmpty);
  });

  test('fetchUsersByIds keeps the requested order and chunks > 30 ids', () async {
    final ids = <String>[];
    for (var i = 0; i < 65; i++) {
      ids.add('u$i');
      await db.doc('users/u$i').set({'displayName': 'U$i'});
    }
    final shuffled = ids.reversed.toList();
    final users = await repo.fetchUsersByIds(shuffled);
    expect(users.length, 65);
    expect(users.map((u) => u.id).toList(), shuffled);
  });

  test('report payload is what the rules require', () async {
    await repo.report(reporterId: 'a', targetType: 'user', targetId: 'b', reason: 'spam');
    final d = (await db.collection('reports').get()).docs.single.data();
    expect(d['status'], 'open');
    expect(d['reporterId'], 'a');
    expect(['user', 'room', 'message'], contains(d['targetType']));
  });

  test('profile update only touches fields the rules allow', () async {
    await db.doc('users/a').set({'displayName': 'Old', 'role': 'user'});
    await repo.updateProfile('a', displayName: 'New', bio: 'hi', country: 'SA');
    final d = (await db.doc('users/a').get()).data()!;
    expect(d['displayName'], 'New');
    expect(d['role'], 'user');
    const allowed = {'displayName', 'bio', 'avatarUrl', 'country', 'gender', 'lastSeen', 'privacy', 'role'};
    expect(d.keys.toSet().difference(allowed), isEmpty);
  });
}
