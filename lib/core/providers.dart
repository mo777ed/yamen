import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/functions_client.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final rtdbProvider = Provider<FirebaseDatabase>((ref) => FirebaseDatabase.instance);
final storageProvider = Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);

final functionsClientProvider = Provider<FunctionsClient>((ref) {
  final region = dotenv.maybeGet('FUNCTIONS_REGION') ?? 'europe-west1';
  final fn = FirebaseFunctions.instanceFor(region: region);
  if (dotenv.maybeGet('USE_FIREBASE_EMULATOR') == 'true') {
    fn.useFunctionsEmulator(dotenv.maybeGet('EMULATOR_HOST') ?? '10.0.2.2', 5001);
  }
  return FunctionsClient(fn);
});

/// Firebase uid of the signed-in user (null when signed out).
final uidProvider = StreamProvider<String?>((ref) => ref.watch(firebaseAuthProvider).authStateChanges().map((u) => u?.uid));

/// Helper for repositories: current uid or throws.
String requireUid(FirebaseAuth auth) {
  final u = auth.currentUser;
  if (u == null) throw StateError('not signed in');
  return u.uid;
}
