import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Registers the FCM token under users/{uid}/devices/{token} and routes notification taps.
class PushService {
  PushService(this._messaging, this._db);
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _db;
  final _subs = <StreamSubscription<dynamic>>[];

  Future<void> start(
    String uid, {
    required void Function(String? title, String? body) onForeground,
    required void Function(Map<String, dynamic> data) onOpen,
  }) async {
    await stop();
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    Future<void> save(String token) => _db.doc('users/$uid/devices/$token').set({
          'platform': Platform.isIOS ? 'ios' : 'android',
          'updatedAt': FieldValue.serverTimestamp(),
        });

    final token = await _messaging.getToken();
    if (token != null) await save(token);
    _subs.add(_messaging.onTokenRefresh.listen(save));
    _subs.add(FirebaseMessaging.onMessage.listen((m) => onForeground(m.notification?.title, m.notification?.body)));
    _subs.add(FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen(m.data.cast<String, dynamic>())));
    final initial = await _messaging.getInitialMessage();
    if (initial != null) onOpen(initial.data.cast<String, dynamic>());
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  /// Removes this device's token (call on sign-out so the next user does not get pushes).
  Future<void> unregister(String uid) async {
    final token = await _messaging.getToken();
    if (token != null) await _db.doc('users/$uid/devices/$token').delete().catchError((_) {});
  }

  /// Maps a push payload to an in-app route.
  static String routeFor(Map<String, dynamic> d) {
    if (d['chatId'] != null) return '/messages/${d['chatId']}';
    if (d['roomId'] != null) return '/room/${d['roomId']}';
    if (d['type'] == 'friend_request' || d['type'] == 'friend_accepted') return '/friends';
    if (d['type'] == 'follow' && d['from'] != null) return '/profile/${d['from']}';
    return '/notifications';
  }
}
