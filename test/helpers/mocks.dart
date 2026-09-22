import 'package:firebase_storage/firebase_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yemen_chat/core/network/functions_client.dart';

class MockFunctionsClient extends Mock implements FunctionsClient {}

class MockStorage extends Mock implements FirebaseStorage {}

/// A FunctionsClient mock that records calls and returns [result].
MockFunctionsClient fnMock([Map<String, dynamic> result = const {'ok': true}]) {
  registerFallbackValue(<String, dynamic>{});
  final m = MockFunctionsClient();
  when(() => m.call(any(), any())).thenAnswer((_) async => result);
  when(() => m.call(any())).thenAnswer((_) async => result);
  return m;
}
