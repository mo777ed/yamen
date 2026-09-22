import 'package:cloud_functions/cloud_functions.dart';

/// Thin wrapper around callable functions: consistent typing + one place to add
/// logging, retries or App Check later.
class FunctionsClient {
  FunctionsClient(this._functions);
  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic> data = const {}]) async {
    final res = await _functions.httpsCallable(name).call<dynamic>(data);
    final out = res.data;
    if (out is Map) return Map<String, dynamic>.from(out);
    return <String, dynamic>{};
  }
}
