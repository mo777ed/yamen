import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yemen_chat/features/wallet/data/wallet_repository.dart';

import '../helpers/mocks.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFunctionsClient fn;
  late WalletRepository repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    fn = fnMock();
    repo = WalletRepository(db, fn);
    // 45 transactions, newest = index 44.
    for (var i = 0; i < 45; i++) {
      await db.collection('wallets/u1/transactions').add({
        'type': i.isEven ? 'gift' : 'purchase',
        'currency': 'coins',
        'amount': i,
        'balanceAfter': i * 10,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1).add(Duration(minutes: i))),
      });
    }
  });

  test('wallet stream maps coins and diamonds (defaults to 0)', () async {
    expect((await repo.watchWallet('nobody').first).coins, 0);
    await db.doc('wallets/u1').set({'coins': 120, 'diamonds': 7});
    final w = await repo.watchWallet('u1').first;
    expect(w.coins, 120);
    expect(w.diamonds, 7);
  });

  test('transactions are paged newest-first with a cursor', () async {
    final p1 = await repo.fetchTransactions('u1');
    expect(p1.items.length, 20);
    expect(p1.items.first.amount, 44);
    final p2 = await repo.fetchTransactions('u1', after: p1.cursor);
    expect(p2.items.length, 20);
    expect(p2.items.first.amount, 24);
    final p3 = await repo.fetchTransactions('u1', after: p2.cursor);
    expect(p3.items.length, 5);
    expect(p3.items.last.amount, 0);
  });

  test('transactions can be filtered by type', () async {
    final page = await repo.fetchTransactions('u1', type: 'purchase');
    expect(page.items.every((t) => t.type == 'purchase'), isTrue);
  });

  test('client never credits coins: purchases go through the verifyPurchase function', () async {
    await repo.verifyPurchase(platform: 'android', productId: 'coins_100', proof: 'token');
    verify(() => fn.call('verifyPurchase', {'platform': 'android', 'productId': 'coins_100', 'proof': 'token'})).called(1);
    // and the wallet document was not touched by the client
    expect((await db.doc('wallets/u1').get()).exists, isFalse);
  });

  test('VIP levels are sorted and disabled ones hidden', () async {
    await db.doc('vip_levels/2').set({'price': 200, 'durationDays': 30});
    await db.doc('vip_levels/1').set({'price': 100, 'durationDays': 30});
    await db.doc('vip_levels/3').set({'price': 300, 'enabled': false});
    final levels = await repo.watchVipLevels().first;
    expect(levels.map((l) => l.level), [1, 2]);
  });

  test('coin packages parse from settings', () async {
    await db.doc('settings/coin_packages').set({
      'packages': [
        {'productId': 'coins_100', 'coins': 100, 'bonus': 10, 'priceUsd': 0.99},
      ],
    });
    final list = await repo.loadPackages();
    expect(list.single.coins, 100);
    expect(list.single.bonus, 10);
    expect(list.single.priceUsd, 0.99);
  });
}
