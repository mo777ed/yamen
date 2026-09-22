import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

/// Writes online/offline state to Realtime Database (auto-set to offline by the server on disconnect).
/// A Cloud Function mirrors it into users/{uid}.online for "active users" lists.
class PresenceService {
  PresenceService(this._db);
  final FirebaseDatabase _db;
  StreamSubscription<DatabaseEvent>? _sub;
  DatabaseReference? _ref;

  void start(String uid) {
    stop();
    final ref = _db.ref('presence/$uid');
    _ref = ref;
    _sub = _db.ref('.info/connected').onValue.listen((e) async {
      if (e.snapshot.value != true) return;
      await ref.onDisconnect().set({'online': false, 'lastSeen': ServerValue.timestamp});
      await ref.set({'online': true, 'lastSeen': ServerValue.timestamp});
    });
  }

  Future<void> setOnline(bool online) async {
    await _ref?.set({'online': online, 'lastSeen': ServerValue.timestamp});
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await setOnline(false).catchError((_) {});
    _ref = null;
  }
}
