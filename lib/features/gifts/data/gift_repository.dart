import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/providers.dart';
import '../../../shared/models/models.dart';

class GiftRepository {
  GiftRepository(this._db, this._fn);
  final FirebaseFirestore _db;
  final FunctionsClient _fn;
  static const _uuid = Uuid();

  Stream<List<Gift>> watchGifts() => _db.collection(Col.gifts).snapshots().map((s) {
        final list = s.docs.map(Gift.fromDoc).where((g) => g.enabled).toList();
        list.sort((a, b) => a.price.compareTo(b.price));
        return list;
      });

  /// [idempotencyKey] lets a retry after a network drop return the original result instead of charging twice.
  Future<Map<String, dynamic>> send({
    required String roomId,
    required String receiverId,
    required String giftId,
    int qty = 1,
    String? idempotencyKey,
  }) =>
      _fn.call(Fn.sendGift, {
        'roomId': roomId,
        'receiverId': receiverId,
        'giftId': giftId,
        'qty': qty,
        'idempotencyKey': idempotencyKey ?? _uuid.v4(),
      });

  Stream<List<QDoc>> watchReceivedGifts(String uid) => _db
      .collection(Col.giftTransactions)
      .where('receiverId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs);
}

final giftRepositoryProvider = Provider<GiftRepository>((ref) => GiftRepository(ref.watch(firestoreProvider), ref.watch(functionsClientProvider)));
final giftsProvider = StreamProvider<List<Gift>>((ref) => ref.watch(giftRepositoryProvider).watchGifts());
final receivedGiftsProvider = StreamProvider.family<List<QDoc>, String>((ref, uid) => ref.watch(giftRepositoryProvider).watchReceivedGifts(uid));
