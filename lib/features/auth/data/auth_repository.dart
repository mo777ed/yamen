import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/providers.dart';
import '../../../shared/models/models.dart';

enum SessionStatus { loading, signedOut, needsProfile, active, banned }

class Session {
  final SessionStatus status;
  final AppUser? user;
  const Session(this.status, [this.user]);
  bool get isSignedIn => status != SessionStatus.signedOut && status != SessionStatus.loading;
}

class PhoneCodeSent {
  final String verificationId;
  final int? resendToken;
  const PhoneCodeSent(this.verificationId, this.resendToken);
}

class AuthRepository {
  AuthRepository(this._auth, this._db, this._fn, this._storage);
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FunctionsClient _fn;
  final FirebaseStorage _storage;

  /// Combined auth + profile stream that drives navigation guards.
  Stream<Session> sessionStream() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(const Session(SessionStatus.signedOut));
      return _db.doc('${Col.users}/${user.uid}').snapshots().map((snap) {
        // The users doc is created by a Cloud Function right after sign-up.
        if (!snap.exists) return const Session(SessionStatus.loading);
        final u = AppUser.fromMap(snap.id, snap.data() ?? {});
        if (u.isBanned) return Session(SessionStatus.banned, u);
        if (u.status == 'deleted') return const Session(SessionStatus.signedOut);
        if (!u.profileComplete) return Session(SessionStatus.needsProfile, u);
        return Session(SessionStatus.active, u);
      });
    });
  }

  // ---------- phone ----------
  /// Starts phone verification. Completes with the verificationId (or signs in
  /// directly on Android when the SMS is auto-retrieved, returning null).
  Future<PhoneCodeSent?> verifyPhone(String phone, {int? resendToken}) {
    final c = Completer<PhoneCodeSent?>();
    _auth.verifyPhoneNumber(
      phoneNumber: phone,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (cred) async {
        try {
          await _auth.signInWithCredential(cred);
          if (!c.isCompleted) c.complete(null);
        } catch (e) {
          if (!c.isCompleted) c.completeError(e);
        }
      },
      verificationFailed: (e) {
        if (!c.isCompleted) c.completeError(e);
      },
      codeSent: (id, token) {
        if (!c.isCompleted) c.complete(PhoneCodeSent(id, token));
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return c.future;
  }

  Future<void> confirmOtp(String verificationId, String code) async {
    final cred = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code.trim());
    await _auth.signInWithCredential(cred);
  }

  // ---------- social ----------
  Future<void> signInWithGoogle() async {
    await _auth.signInWithProvider(GoogleAuthProvider());
  }

  Future<void> signInWithApple() async {
    final provider = AppleAuthProvider()..addScope('email')..addScope('name');
    await _auth.signInWithProvider(provider);
  }

  // ---------- email ----------
  Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> registerWithEmail(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> sendPasswordReset(String email) => _auth.sendPasswordResetEmail(email: email.trim());

  // ---------- account management ----------
  Future<void> signOut() => _auth.signOut();

  Future<void> deleteAccount() async {
    await _fn.call(Fn.deleteAccount);
    await _auth.signOut();
  }

  /// Sends a verification link to the new address; the change applies once confirmed.
  Future<void> changeEmail(String newEmail) async {
    final u = _auth.currentUser;
    if (u == null) throw const Failure('no-user', 'سجّل الدخول أولاً');
    await u.verifyBeforeUpdateEmail(newEmail.trim());
  }

  /// Step 1 of a phone change: send the SMS. Step 2: [confirmPhoneChange].
  Future<PhoneCodeSent?> startPhoneChange(String phone) => verifyPhone(phone);

  Future<void> confirmPhoneChange(String verificationId, String code) async {
    final u = _auth.currentUser;
    if (u == null) throw const Failure('no-user', 'سجّل الدخول أولاً');
    final cred = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code.trim());
    await u.updatePhoneNumber(cred);
  }

  // ---------- profile ----------
  Future<String> uploadAvatar(File file) async {
    final uid = requireUid(_auth);
    final ref = _storage.ref('avatars/$uid/avatar.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> completeProfile({
    required String username,
    required String displayName,
    required String country,
    required String lang,
    required String dob,
    String? gender,
    String bio = '',
    String? avatarUrl,
    String? phone,
  }) async {
    await _fn.call(Fn.completeProfile, {
      'username': username,
      'displayName': displayName,
      'country': country,
      'lang': lang,
      'dob': dob,
      'gender': gender,
      'bio': bio,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (phone != null) 'phone': phone,
    });
  }

  Future<void> claimDailyLogin() => _fn.call(Fn.claimDailyLogin);
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(
      ref.watch(firebaseAuthProvider),
      ref.watch(firestoreProvider),
      ref.watch(functionsClientProvider),
      ref.watch(storageProvider),
    ));

final sessionProvider = StreamProvider<Session>((ref) => ref.watch(authRepositoryProvider).sessionStream());

/// Current user's profile (null until the session is active).
final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(sessionProvider).valueOrNull?.user);

/// Non-null uid for screens that are only reachable when signed in.
final myUidProvider = Provider<String>((ref) => ref.watch(firebaseAuthProvider).currentUser?.uid ?? '');

/// verificationId handed from the login screen to the OTP screen.
class PendingPhone {
  final String phone;
  final String verificationId;
  final int? resendToken;
  const PendingPhone(this.phone, this.verificationId, this.resendToken);
}

final pendingPhoneProvider = StateProvider<PendingPhone?>((ref) => null);
