import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/providers.dart';
import '../../../shared/models/models.dart';
import '../../auth/data/auth_repository.dart';

enum FriendState { none, friends, requestSent, requestReceived }

class UserRepository {
  UserRepository(this._db, this._fn);
  final FirebaseFirestore _db;
  final FunctionsClient _fn;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection(Col.users);

  Stream<AppUser?> watchUser(String id) => _users.doc(id).snapshots().map((s) => s.exists ? AppUser.fromDoc(s) : null);

  List<AppUser> _list(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs.map(AppUser.fromDoc).where((u) => u.profileComplete && u.status == 'active').toList();

  Stream<List<AppUser>> activeUsers() =>
      _users.where('online', isEqualTo: true).limit(30).snapshots().map((s) => _list(s).where((u) => !u.hideOnline).toList());

  Stream<List<AppUser>> popularUsers() => _users.orderBy('followersCount', descending: true).limit(15).snapshots().map(_list);
  Stream<List<AppUser>> newUsers() => _users.orderBy('createdAt', descending: true).limit(15).snapshots().map(_list);
  Stream<List<AppUser>> vipUsers() =>
      _users.where('vipLevel', isGreaterThan: 0).orderBy('vipLevel', descending: true).limit(15).snapshots().map(_list);
  Stream<List<Host>> popularHosts() =>
      _db.collection(Col.hosts).orderBy('giftsReceived', descending: true).limit(15).snapshots().map((s) => s.docs.map(Host.fromDoc).toList());

  Future<List<AppUser>> searchUsers(String q) async {
    final t = q.trim().toLowerCase().replaceFirst('@', '');
    if (t.length < 2) return [];
    final s = await _users.where('usernameLower', isGreaterThanOrEqualTo: t).where('usernameLower', isLessThan: '$t\uf8ff').limit(20).get();
    return _list(s);
  }

  Future<List<Host>> searchHosts(String q) async {
    final t = q.trim();
    if (t.length < 2) return [];
    final s = await _db.collection(Col.hosts).where('displayName', isGreaterThanOrEqualTo: t).where('displayName', isLessThan: '$t\uf8ff').limit(20).get();
    return s.docs.map(Host.fromDoc).toList();
  }

  Future<List<Agency>> searchAgencies(String q) async {
    final t = q.trim();
    if (t.length < 2) return [];
    final s = await _db.collection(Col.agencies).where('name', isGreaterThanOrEqualTo: t).where('name', isLessThan: '$t\uf8ff').limit(20).get();
    return s.docs.map(Agency.fromDoc).where((a) => a.status == 'active').toList();
  }

  /// Firestore `whereIn` accepts 30 ids max, so fetch in chunks.
  Future<List<AppUser>> fetchUsersByIds(List<String> ids) async {
    final out = <AppUser>[];
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final s = await _users.where(FieldPath.documentId, whereIn: chunk).get();
      out.addAll(s.docs.map(AppUser.fromDoc));
    }
    final order = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    out.sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
    return out;
  }

  Future<void> updateProfile(String uid, {required String displayName, String bio = '', String? avatarUrl, String? country, String? gender}) {
    return _users.doc(uid).update({
      'displayName': displayName,
      'bio': bio,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (country != null) 'country': country,
      if (gender != null) 'gender': gender,
    });
  }

  Future<void> updatePrivacy(String uid, {required bool hideOnline, required bool dmFriendsOnly}) =>
      _users.doc(uid).update({'privacy': {'hideOnline': hideOnline, 'dmFriendsOnly': dmFriendsOnly}});

  // ---- follow ----
  Stream<bool> watchIsFollowing(String me, String other) =>
      _db.doc('${Col.follows}/${me}_$other').snapshots().map((s) => s.exists);

  Future<void> follow(String me, String other) => _db.doc('${Col.follows}/${me}_$other').set({
        'followerId': me,
        'followeeId': other,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> unfollow(String me, String other) => _db.doc('${Col.follows}/${me}_$other').delete();

  Future<List<String>> followerIds(String uid) async {
    final s = await _db.collection(Col.follows).where('followeeId', isEqualTo: uid).orderBy('createdAt', descending: true).limit(100).get();
    return s.docs.map((d) => d.data()['followerId'] as String).toList();
  }

  Future<List<String>> followingIds(String uid) async {
    final s = await _db.collection(Col.follows).where('followerId', isEqualTo: uid).orderBy('createdAt', descending: true).limit(100).get();
    return s.docs.map((d) => d.data()['followeeId'] as String).toList();
  }

  // ---- block ----
  Stream<bool> watchIsBlocked(String me, String other) => _db.doc('${Col.blocks}/${me}_$other').snapshots().map((s) => s.exists);

  Future<void> block(String me, String other) async {
    await _db.doc('${Col.blocks}/${me}_$other').set({'blockerId': me, 'blockedId': other, 'createdAt': FieldValue.serverTimestamp()});
    await _db.doc('${Col.follows}/${me}_$other').delete().catchError((_) {});
  }

  Future<void> unblock(String me, String other) => _db.doc('${Col.blocks}/${me}_$other').delete();

  Future<List<String>> blockedIds(String me) async {
    final s = await _db.collection(Col.blocks).where('blockerId', isEqualTo: me).get();
    return s.docs.map((d) => d.data()['blockedId'] as String).toList();
  }

  // ---- friends ----
  Stream<List<AppUser>> watchFriends(String uid) => _db.collection('${Col.friends}/$uid/list').snapshots().map((s) => s.docs
      .map((d) => AppUser.fromMap(d.id, {'displayName': d.data()['displayName'], 'avatarUrl': d.data()['avatarUrl']}))
      .toList());

  Stream<List<FriendRequest>> watchIncomingRequests(String uid) => _db
      .collection(Col.friendRequests)
      .where('to', isEqualTo: uid)
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(FriendRequest.fromDoc).toList());

  Future<FriendState> friendState(String me, String other) async {
    final f = await _db.doc('${Col.friends}/$me/list/$other').get();
    if (f.exists) return FriendState.friends;
    final sent = await _db.collection(Col.friendRequests).where('from', isEqualTo: me).where('to', isEqualTo: other).where('status', isEqualTo: 'pending').limit(1).get();
    if (sent.docs.isNotEmpty) return FriendState.requestSent;
    final got = await _db.collection(Col.friendRequests).where('from', isEqualTo: other).where('to', isEqualTo: me).where('status', isEqualTo: 'pending').limit(1).get();
    if (got.docs.isNotEmpty) return FriendState.requestReceived;
    return FriendState.none;
  }

  Future<void> sendFriendRequest(String me, String other) =>
      _db.collection(Col.friendRequests).add({'from': me, 'to': other, 'status': 'pending', 'createdAt': FieldValue.serverTimestamp()});

  Future<void> respondToRequest(String requestId, bool accept) => _fn.call(Fn.respondFriendRequest, {'requestId': requestId, 'accept': accept});
  Future<void> removeFriend(String other) => _fn.call(Fn.removeFriend, {'uid': other});

  // ---- posts ----
  Stream<List<Post>> watchPosts(String uid) =>
      _db.collection(Col.posts).where('authorId', isEqualTo: uid).orderBy('createdAt', descending: true).limit(30).snapshots().map((s) => s.docs.map(Post.fromDoc).toList());

  Future<void> createPost(AppUser me, String text) => _db.collection(Col.posts).add({
        'authorId': me.id,
        'authorName': me.displayName,
        'authorAvatar': me.avatarUrl,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> deletePost(String id) => _db.doc('${Col.posts}/$id').delete();

  // ---- reports ----
  Future<void> report({required String reporterId, required String targetType, required String targetId, required String reason, String? context}) =>
      _db.collection(Col.reports).add({
        'reporterId': reporterId,
        'targetType': targetType,
        'targetId': targetId,
        'reason': reason,
        if (context != null) 'context': context,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
}

final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository(ref.watch(firestoreProvider), ref.watch(functionsClientProvider)));

final userProvider = StreamProvider.family<AppUser?, String>((ref, id) => ref.watch(userRepositoryProvider).watchUser(id));
final activeUsersProvider = StreamProvider<List<AppUser>>((ref) => ref.watch(userRepositoryProvider).activeUsers());
final popularUsersProvider = StreamProvider<List<AppUser>>((ref) => ref.watch(userRepositoryProvider).popularUsers());
final newUsersProvider = StreamProvider<List<AppUser>>((ref) => ref.watch(userRepositoryProvider).newUsers());
final vipUsersProvider = StreamProvider<List<AppUser>>((ref) => ref.watch(userRepositoryProvider).vipUsers());
final popularHostsProvider = StreamProvider<List<Host>>((ref) => ref.watch(userRepositoryProvider).popularHosts());
final postsProvider = StreamProvider.family<List<Post>, String>((ref, uid) => ref.watch(userRepositoryProvider).watchPosts(uid));
final friendsProvider = StreamProvider<List<AppUser>>((ref) => ref.watch(userRepositoryProvider).watchFriends(ref.watch(myUidProvider)));
final incomingRequestsProvider = StreamProvider<List<FriendRequest>>((ref) => ref.watch(userRepositoryProvider).watchIncomingRequests(ref.watch(myUidProvider)));
final isFollowingProvider = StreamProvider.family<bool, String>((ref, other) => ref.watch(userRepositoryProvider).watchIsFollowing(ref.watch(myUidProvider), other));
final isBlockedProvider = StreamProvider.family<bool, String>((ref, other) => ref.watch(userRepositoryProvider).watchIsBlocked(ref.watch(myUidProvider), other));
final friendStateProvider = FutureProvider.autoDispose.family<FriendState, String>((ref, other) => ref.watch(userRepositoryProvider).friendState(ref.watch(myUidProvider), other));
final followersProvider = FutureProvider.autoDispose.family<List<AppUser>, String>((ref, uid) async {
  final repo = ref.watch(userRepositoryProvider);
  return repo.fetchUsersByIds(await repo.followerIds(uid));
});
final followingProvider = FutureProvider.autoDispose.family<List<AppUser>, String>((ref, uid) async {
  final repo = ref.watch(userRepositoryProvider);
  return repo.fetchUsersByIds(await repo.followingIds(uid));
});
final blockedUsersProvider = FutureProvider.autoDispose<List<AppUser>>((ref) async {
  final repo = ref.watch(userRepositoryProvider);
  return repo.fetchUsersByIds(await repo.blockedIds(ref.watch(myUidProvider)));
});
