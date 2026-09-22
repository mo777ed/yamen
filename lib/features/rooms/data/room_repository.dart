import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/providers.dart';
import '../../../core/services/voice/livekit_voice_service.dart';
import '../../../shared/models/models.dart';
import '../../auth/data/auth_repository.dart';

enum RoomFeed { featured, popular, newest, recommended, category }

typedef RoomFeedKey = ({RoomFeed feed, String? arg});

class JoinResult {
  final String token;
  final String url;
  final String role;
  const JoinResult(this.token, this.url, this.role);
}

class RoomRepository {
  RoomRepository(this._db, this._fn, this._storage);
  final FirebaseFirestore _db;
  final FunctionsClient _fn;
  final FirebaseStorage _storage;

  final Map<String, JoinResult> _joinCache = {};

  Query<Map<String, dynamic>> _live() => _db.collection(Col.rooms).where('status', isEqualTo: 'live');

  Stream<List<Room>> watchFeed(RoomFeedKey key, {int limit = 12}) {
    Query<Map<String, dynamic>> q;
    switch (key.feed) {
      case RoomFeed.featured:
        q = _live().where('featured', isEqualTo: true).orderBy('memberCount', descending: true);
        break;
      case RoomFeed.popular:
        q = _live().orderBy('memberCount', descending: true);
        break;
      case RoomFeed.newest:
        q = _live().orderBy('createdAt', descending: true);
        break;
      case RoomFeed.recommended:
        q = key.arg == null || key.arg!.isEmpty
            ? _live().orderBy('memberCount', descending: true)
            : _live().where('country', isEqualTo: key.arg).orderBy('memberCount', descending: true);
        break;
      case RoomFeed.category:
        q = _live().where('category', isEqualTo: key.arg).orderBy('memberCount', descending: true);
        break;
    }
    return q.limit(limit).snapshots().map((s) => s.docs.map(Room.fromDoc).toList());
  }

  Stream<Room?> watchRoom(String id) =>
      _db.doc('${Col.rooms}/$id').snapshots().map((s) => s.exists ? Room.fromDoc(s) : null);

  Stream<List<Seat>> watchSeats(String roomId) => _db.collection('${Col.rooms}/$roomId/seats').snapshots().map((s) {
        final l = s.docs.map(Seat.fromDoc).toList();
        l.sort((a, b) => a.index.compareTo(b.index));
        return l;
      });

  Stream<List<RoomMember>> watchMembers(String roomId) => _db
      .collection('${Col.rooms}/$roomId/members')
      .where('left', isEqualTo: false)
      .limit(80)
      .snapshots()
      .map((s) => s.docs.map(RoomMember.fromDoc).toList());

  Stream<RoomMember?> watchMember(String roomId, String uid) =>
      _db.doc('${Col.rooms}/$roomId/members/$uid').snapshots().map((s) => s.exists ? RoomMember.fromDoc(s) : null);

  /// Newest first (the UI reverses it into a bottom-anchored list).
  Stream<List<RoomMessage>> watchMessages(String roomId) => _db
      .collection('${Col.rooms}/$roomId/messages')
      .orderBy('createdAt', descending: true)
      .limit(60)
      .snapshots()
      .map((s) => s.docs.map(RoomMessage.fromDoc).toList());

  Future<void> sendMessage(String roomId, AppUser me, String text) async {
    final mentions = RegExp(r'@([a-z0-9_]{3,20})').allMatches(text).map((m) => m.group(1)!).toSet().toList();
    await _db.collection('${Col.rooms}/$roomId/messages').add({
      'senderId': me.id,
      'senderName': me.displayName,
      'senderAvatar': me.avatarUrl,
      'senderLevel': me.level,
      'text': text,
      'type': 'text',
      'mentions': mentions,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> uploadCover(String uid, File file) async {
    final ref = _storage.ref('room_covers/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<String> create({
    required String name,
    required String category,
    required bool isPrivate,
    String? password,
    int seatCount = 8,
    String coverUrl = '',
    String description = '',
  }) async {
    final res = await _fn.call(Fn.createRoom, {
      'name': name,
      'category': category,
      'type': isPrivate ? 'private' : 'public',
      if (isPrivate) 'password': password,
      'seatCount': seatCount,
      'coverUrl': coverUrl,
      'description': description,
    });
    return res['roomId'] as String;
  }

  Future<JoinResult> join(String roomId, {String? password}) async {
    final res = await _fn.call(Fn.joinRoom, {'roomId': roomId, if (password != null) 'password': password});
    final r = JoinResult(res['token'] as String, res['url'] as String, res['role'] as String);
    _joinCache[roomId] = r;
    return r;
  }

  /// Used by the voice layer. Reuses the token from [join]; re-joins if it is gone.
  Future<VoiceCredentials> credentialsFor(String roomId) async {
    final cached = _joinCache[roomId] ?? await join(roomId);
    return VoiceCredentials(cached.url, cached.token);
  }

  Future<void> leave(String roomId) async {
    _joinCache.remove(roomId);
    await _fn.call(Fn.leaveRoom, {'roomId': roomId});
  }

  Future<void> manageSeat(String roomId, String action, {int? seat, String? targetUid, int? toSeat}) => _fn.call(Fn.manageSeat, {
        'roomId': roomId,
        'action': action,
        if (seat != null) 'seat': seat,
        if (targetUid != null) 'targetUid': targetUid,
        if (toSeat != null) 'toSeat': toSeat,
      });

  Future<void> moderate(String roomId, String action, {String? targetUid, String? messageId, int? minutes, String? role}) =>
      _fn.call(Fn.roomModeration, {
        'roomId': roomId,
        'action': action,
        if (targetUid != null) 'targetUid': targetUid,
        if (messageId != null) 'messageId': messageId,
        if (minutes != null) 'minutes': minutes,
        if (role != null) 'role': role,
      });

  Future<void> setPassword(String roomId, String? password) =>
      _fn.call(Fn.setRoomPassword, {'roomId': roomId, if (password != null) 'password': password});

  Future<void> close(String roomId) => _fn.call(Fn.closeRoom, {'roomId': roomId});

  Future<void> updateRoom(String roomId, {String? name, String? description, String? coverUrl, String? category}) {
    final data = <String, dynamic>{
      if (name != null) 'name': name,
      if (name != null) 'nameLower': name.toLowerCase(),
      if (description != null) 'description': description,
      if (coverUrl != null) 'coverUrl': coverUrl,
      if (category != null) 'category': category,
    };
    return _db.doc('${Col.rooms}/$roomId').update(data);
  }

  // ---- search ----
  Future<List<Room>> searchRooms(String q) async {
    final t = q.trim().toLowerCase();
    if (t.length < 2) return [];
    final s = await _db
        .collection(Col.rooms)
        .where('nameLower', isGreaterThanOrEqualTo: t)
        .where('nameLower', isLessThan: '$t\uf8ff')
        .limit(20)
        .get();
    return s.docs.map(Room.fromDoc).where((r) => r.isLive).toList();
  }
}

final roomRepositoryProvider = Provider<RoomRepository>((ref) => RoomRepository(
      ref.watch(firestoreProvider),
      ref.watch(functionsClientProvider),
      ref.watch(storageProvider),
    ));

final roomFeedProvider = StreamProvider.family<List<Room>, RoomFeedKey>((ref, key) {
  ref.watch(uidProvider); // restart the stream after sign-in/out
  return ref.watch(roomRepositoryProvider).watchFeed(key);
});

final roomProvider = StreamProvider.family<Room?, String>((ref, id) => ref.watch(roomRepositoryProvider).watchRoom(id));
final roomSeatsProvider = StreamProvider.family<List<Seat>, String>((ref, id) => ref.watch(roomRepositoryProvider).watchSeats(id));
final roomMembersProvider = StreamProvider.family<List<RoomMember>, String>((ref, id) => ref.watch(roomRepositoryProvider).watchMembers(id));
final roomMessagesProvider = StreamProvider.family<List<RoomMessage>, String>((ref, id) => ref.watch(roomRepositoryProvider).watchMessages(id));
final myRoomMemberProvider = StreamProvider.family<RoomMember?, String>((ref, roomId) {
  final uid = ref.watch(myUidProvider);
  return ref.watch(roomRepositoryProvider).watchMember(roomId, uid);
});
