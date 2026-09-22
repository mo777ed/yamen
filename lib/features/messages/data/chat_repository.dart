import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/providers.dart';
import '../../../shared/models/models.dart';

class ChatRepository {
  ChatRepository(this._db, this._rtdb, this._storage, this._fn);
  final FirebaseFirestore _db;
  final FirebaseDatabase _rtdb;
  final FirebaseStorage _storage;
  final FunctionsClient _fn;

  static String chatIdFor(String a, String b) => ([a, b]..sort()).join('_');

  /// Creates the chat document when needed and returns its id.
  Future<String> openChat(String me, AppUser other, bool areFriends) async {
    if (other.dmFriendsOnly && !areFriends) {
      throw const Failure('dm-friends-only', 'هذا المستخدم يستقبل الرسائل من أصدقائه فقط');
    }
    final id = chatIdFor(me, other.id);
    final ref = _db.doc('${Col.chats}/$id');
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'participants': [me, other.id]..sort(),
        'lastMessage': '',
        'lastAt': FieldValue.serverTimestamp(),
        'unread': {me: 0, other.id: 0},
      });
    }
    return id;
  }

  Stream<List<ChatSummary>> watchChats(String uid) => _db
      .collection(Col.chats)
      .where('participants', arrayContains: uid)
      .orderBy('lastAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(ChatSummary.fromDoc).where((c) => c.lastMessage.isNotEmpty).toList());

  Stream<List<ChatMessage>> watchMessages(String chatId) => _db
      .collection('${Col.chats}/$chatId/messages')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  Future<void> sendText(String chatId, String me, String text) => _db.collection('${Col.chats}/$chatId/messages').add({
        'senderId': me,
        'text': text,
        'readBy': [me],
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> sendImage(String chatId, String me, File file) async {
    final ref = _storage.ref('chat_images/$chatId/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await _db.collection('${Col.chats}/$chatId/messages').add({
      'senderId': me,
      'text': '',
      'imageUrl': url,
      'readBy': [me],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks the other user's recent messages as read and resets my unread counter.
  Future<void> markRead(String chatId, String me, List<ChatMessage> messages) async {
    final unread = messages.where((m) => m.senderId != me && !m.readBy.contains(me)).take(30).toList();
    if (unread.isEmpty) return;
    final batch = _db.batch();
    for (final m in unread) {
      batch.update(_db.doc('${Col.chats}/$chatId/messages/${m.id}'), {'readBy': FieldValue.arrayUnion([me])});
    }
    await batch.commit();
    await _fn.call(Fn.markChatRead, {'chatId': chatId});
  }

  // ---- typing indicator (Realtime Database, auto-cleared on disconnect) ----
  Future<void> setTyping(String chatId, String me, bool typing) async {
    final ref = _rtdb.ref('typing/$chatId/$me');
    if (typing) {
      await ref.onDisconnect().remove();
      await ref.set(true);
    } else {
      await ref.remove();
    }
  }

  Stream<bool> watchTyping(String chatId, String other) => _rtdb.ref('typing/$chatId/$other').onValue.map((e) => e.snapshot.value == true);
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) => ChatRepository(
      ref.watch(firestoreProvider),
      ref.watch(rtdbProvider),
      ref.watch(storageProvider),
      ref.watch(functionsClientProvider),
    ));

final chatsProvider = StreamProvider<List<ChatSummary>>((ref) {
  final uid = ref.watch(uidProvider).valueOrNull;
  if (uid == null) return const Stream.empty();
  return ref.watch(chatRepositoryProvider).watchChats(uid);
});

final chatMessagesProvider = StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, chatId) => ref.watch(chatRepositoryProvider).watchMessages(chatId));
final typingProvider = StreamProvider.autoDispose.family<bool, ({String chatId, String other})>((ref, k) => ref.watch(chatRepositoryProvider).watchTyping(k.chatId, k.other));
