import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/providers.dart';
import '../../../shared/models/models.dart';
import '../../auth/data/auth_repository.dart';

class WalletRepository {
  WalletRepository(this._db, this._fn);
  final FirebaseFirestore _db;
  final FunctionsClient _fn;

  Stream<WalletData> watchWallet(String uid) =>
      _db.doc('${Col.wallets}/$uid').snapshots().map((s) => WalletData.fromMap(s.data()));

  Stream<UserLevel> watchLevel(String uid) =>
      _db.doc('${Col.userLevels}/$uid').snapshots().map((s) => UserLevel.fromMap(s.data()));

  Stream<UserVip> watchVip(String uid) =>
      _db.doc('${Col.userVip}/$uid').snapshots().map((s) => UserVip.fromMap(s.data()));

  /// Cursor-based page of transactions (newest first).
  Future<({List<WalletTx> items, QDoc? cursor})> fetchTransactions(String uid, {QDoc? after, String? type}) async {
    Query<Map<String, dynamic>> q = _db.collection('${Col.wallets}/$uid/transactions');
    if (type != null) q = q.where('type', isEqualTo: type);
    q = q.orderBy('createdAt', descending: true).limit(20);
    if (after != null) q = q.startAfterDocument(after);
    final snap = await q.get();
    return (items: snap.docs.map(WalletTx.fromDoc).toList(), cursor: snap.docs.isEmpty ? null : snap.docs.last);
  }

  Future<List<CoinPackage>> loadPackages() async {
    final s = await _db.doc('${Col.settings}/coin_packages').get();
    final list = (s.data()?['packages'] as List?) ?? const [];
    return list.map((e) => CoinPackage.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Map<String, dynamic>> verifyPurchase({required String platform, required String productId, required String proof}) =>
      _fn.call(Fn.verifyPurchase, {'platform': platform, 'productId': productId, 'proof': proof});

  Stream<List<VipLevel>> watchVipLevels() => _db.collection(Col.vipLevels).snapshots().map((s) {
        final l = s.docs.map(VipLevel.fromDoc).where((v) => v.enabled).toList();
        l.sort((a, b) => a.level.compareTo(b.level));
        return l;
      });

  Future<void> purchaseVip(int level) => _fn.call(Fn.purchaseVip, {'level': level});
}

final walletRepositoryProvider = Provider<WalletRepository>((ref) => WalletRepository(ref.watch(firestoreProvider), ref.watch(functionsClientProvider)));

final walletProvider = StreamProvider<WalletData>((ref) {
  final uid = ref.watch(uidProvider).valueOrNull;
  if (uid == null) return const Stream.empty();
  return ref.watch(walletRepositoryProvider).watchWallet(uid);
});

final userLevelProvider = StreamProvider<UserLevel>((ref) {
  final uid = ref.watch(uidProvider).valueOrNull;
  if (uid == null) return const Stream.empty();
  return ref.watch(walletRepositoryProvider).watchLevel(uid);
});

final userVipProvider = StreamProvider<UserVip>((ref) {
  final uid = ref.watch(uidProvider).valueOrNull;
  if (uid == null) return const Stream.empty();
  return ref.watch(walletRepositoryProvider).watchVip(uid);
});

final vipLevelsProvider = StreamProvider<List<VipLevel>>((ref) => ref.watch(walletRepositoryProvider).watchVipLevels());
final coinPackagesProvider = FutureProvider<List<CoinPackage>>((ref) => ref.watch(walletRepositoryProvider).loadPackages());

// ---------------------------------------------------------------------------
// Store purchases. The client NEVER credits coins: it forwards the store proof
// to the `verifyPurchase` function, which validates and credits server-side.
// ---------------------------------------------------------------------------
enum PurchaseUiState { idle, pending, verifying, success, error }

class PurchaseController extends StateNotifier<({PurchaseUiState state, String? message})> {
  PurchaseController(this._repo, this._iap) : super((state: PurchaseUiState.idle, message: null)) {
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      state = (state: PurchaseUiState.error, message: friendlyError(e));
    });
  }

  final WalletRepository _repo;
  final InAppPurchase _iap;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  Future<bool> available() => _iap.isAvailable();

  Future<Map<String, ProductDetails>> products(Set<String> ids) async {
    final res = await _iap.queryProductDetails(ids);
    return {for (final p in res.productDetails) p.id: p};
  }

  Future<void> buy(ProductDetails product) async {
    state = (state: PurchaseUiState.pending, message: null);
    try {
      await _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: product), autoConsume: false);
    } catch (e) {
      state = (state: PurchaseUiState.error, message: friendlyError(e));
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          state = (state: PurchaseUiState.pending, message: null);
          break;
        case PurchaseStatus.error:
          state = (state: PurchaseUiState.error, message: 'تعذّرت عملية الشراء');
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          break;
        case PurchaseStatus.canceled:
          state = (state: PurchaseUiState.idle, message: null);
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndComplete(p);
          break;
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails p) async {
    state = (state: PurchaseUiState.verifying, message: null);
    try {
      await _repo.verifyPurchase(
        platform: Platform.isIOS ? 'ios' : 'android',
        productId: p.productID,
        proof: p.verificationData.serverVerificationData,
      );
      if (Platform.isAndroid && p is GooglePlayPurchaseDetails) {
        final add = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        await add.consumePurchase(p);
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      state = (state: PurchaseUiState.success, message: null);
    } catch (e) {
      // Not completed on purpose: the store re-delivers it next launch so a paid purchase is never lost.
      state = (state: PurchaseUiState.error, message: friendlyError(e));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final purchaseControllerProvider = StateNotifierProvider<PurchaseController, ({PurchaseUiState state, String? message})>(
  (ref) => PurchaseController(ref.watch(walletRepositoryProvider), InAppPurchase.instance),
);
