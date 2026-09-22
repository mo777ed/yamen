import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yemen_chat/features/rooms/data/room_repository.dart';
import 'package:yemen_chat/shared/models/models.dart';

import '../helpers/mocks.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFunctionsClient fn;
  late RoomRepository repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    fn = fnMock({'roomId': 'new1', 'token': 't', 'url': 'wss://x', 'role': 'listener'});
    repo = RoomRepository(db, fn, MockStorage());
    Future<void> room(String id, int members, {String status = 'live', String category = 'chat', bool featured = false, String country = 'YE', int minute = 0}) =>
        db.doc('rooms/$id').set({
          'name': 'Room $id',
          'status': status,
          'memberCount': members,
          'category': category,
          'featured': featured,
          'country': country,
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1).add(Duration(minutes: minute))),
        });
    await room('a', 5, minute: 1);
    await room('b', 50, category: 'music', featured: true, minute: 2);
    await room('c', 20, country: 'SA', minute: 3);
    await room('closed', 999, status: 'closed', minute: 4);
  });

  test('popular feed hides closed rooms and sorts by members', () async {
    final rooms = await repo.watchFeed((feed: RoomFeed.popular, arg: null)).first;
    expect(rooms.map((r) => r.id), ['b', 'c', 'a']);
  });

  test('newest, featured, category and recommended feeds', () async {
    expect((await repo.watchFeed((feed: RoomFeed.newest, arg: null)).first).map((r) => r.id), ['c', 'b', 'a']);
    expect((await repo.watchFeed((feed: RoomFeed.featured, arg: null)).first).map((r) => r.id), ['b']);
    expect((await repo.watchFeed((feed: RoomFeed.category, arg: 'music')).first).map((r) => r.id), ['b']);
    expect((await repo.watchFeed((feed: RoomFeed.recommended, arg: 'SA')).first).map((r) => r.id), ['c']);
  });

  test('seats are ordered numerically', () async {
    for (final i in [10, 2, 1, 3]) {
      await db.doc('rooms/a/seats/$i').set({'userId': null, 'locked': false, 'micMuted': false});
    }
    final seats = await repo.watchSeats('a').first;
    expect(seats.map((s) => s.index), [1, 2, 3, 10]);
  });

  test('chat message payload matches what firestore.rules allow', () async {
    await repo.sendMessage('a', const AppUser(id: 'u1', displayName: 'Ali', level: 4), 'hello @sara_1');
    final snap = await db.collection('rooms/a/messages').get();
    final m = snap.docs.single.data();
    // Must be a subset of the rules' hasOnly([...]) list.
    const allowed = {'senderId', 'senderName', 'senderAvatar', 'senderLevel', 'text', 'type', 'mentions', 'createdAt'};
    expect(m.keys.toSet().difference(allowed), isEmpty);
    expect(m['type'], 'text');
    expect(m['senderId'], 'u1');
    expect(m['mentions'], ['sara_1']);
  });

  test('join caches credentials for the voice layer', () async {
    final j = await repo.join('a', password: 'pw');
    expect(j.token, 't');
    verify(() => fn.call('joinRoom', {'roomId': 'a', 'password': 'pw'})).called(1);
    final creds = await repo.credentialsFor('a');
    expect(creds.url, 'wss://x');
    verifyNever(() => fn.call('joinRoom', {'roomId': 'a'}));
  });

  test('seat and moderation actions are server calls with exact payloads', () async {
    await repo.manageSeat('a', 'take', seat: 3);
    verify(() => fn.call('manageSeat', {'roomId': 'a', 'action': 'take', 'seat': 3})).called(1);
    await repo.manageSeat('a', 'invite', seat: 2, targetUid: 'u9');
    verify(() => fn.call('manageSeat', {'roomId': 'a', 'action': 'invite', 'seat': 2, 'targetUid': 'u9'})).called(1);
    await repo.moderate('a', 'ban', targetUid: 'u9', minutes: 60);
    verify(() => fn.call('roomModeration', {'roomId': 'a', 'action': 'ban', 'targetUid': 'u9', 'minutes': 60})).called(1);
  });

  test('create room sends password only for private rooms', () async {
    final id = await repo.create(name: 'X', category: 'chat', isPrivate: false, password: 'ignored');
    expect(id, 'new1');
    final captured = verify(() => fn.call('createRoom', captureAny())).captured.single as Map<String, dynamic>;
    expect(captured.containsKey('password'), isFalse);
    expect(captured['type'], 'public');
  });

  test('room search matches by lower-case prefix and skips closed rooms', () async {
    await db.doc('rooms/a').update({'nameLower': 'room a'});
    await db.doc('rooms/closed').update({'nameLower': 'room closed'});
    final res = await repo.searchRooms('Room');
    expect(res.map((r) => r.id), ['a']);
    expect(await repo.searchRooms('r'), isEmpty);
  });
}
