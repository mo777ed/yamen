import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yemen_chat/features/gifts/data/gift_repository.dart';

import '../helpers/mocks.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFunctionsClient fn;
  late GiftRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    fn = fnMock({'ok': true, 'cost': 10, 'balance': 90});
    repo = GiftRepository(db, fn);
  });

  test('gifts list only enabled gifts, cheapest first', () async {
    await db.doc('gifts/crown').set({'name': {'ar': 'تاج', 'en': 'Crown'}, 'price': 500});
    await db.doc('gifts/rose').set({'name': {'ar': 'وردة', 'en': 'Rose'}, 'price': 10});
    await db.doc('gifts/off').set({'name': {'en': 'Off'}, 'price': 1, 'enabled': false});
    final list = await repo.watchGifts().first;
    expect(list.map((g) => g.id), ['rose', 'crown']);
  });

  test('send never touches balances locally and always sends an idempotency key', () async {
    await repo.send(roomId: 'r', receiverId: 'u2', giftId: 'rose', qty: 3);
    final args = verify(() => fn.call('sendGift', captureAny())).captured.single as Map<String, dynamic>;
    expect(args['roomId'], 'r');
    expect(args['receiverId'], 'u2');
    expect(args['giftId'], 'rose');
    expect(args['qty'], 3);
    expect((args['idempotencyKey'] as String).length, greaterThanOrEqualTo(8));
    expect((await db.collection('wallets').get()).docs, isEmpty);
  });

  test('a retry can reuse the same idempotency key', () async {
    await repo.send(roomId: 'r', receiverId: 'u2', giftId: 'rose', idempotencyKey: 'fixed-key-123');
    await repo.send(roomId: 'r', receiverId: 'u2', giftId: 'rose', idempotencyKey: 'fixed-key-123');
    verify(() => fn.call('sendGift', any(that: containsPair('idempotencyKey', 'fixed-key-123')))).called(2);
  });

  test('different sends get different keys', () async {
    await repo.send(roomId: 'r', receiverId: 'u2', giftId: 'rose');
    await repo.send(roomId: 'r', receiverId: 'u2', giftId: 'rose');
    final keys = verify(() => fn.call('sendGift', captureAny())).captured.map((m) => (m as Map)['idempotencyKey']).toSet();
    expect(keys.length, 2);
  });
}
