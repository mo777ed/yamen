import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// A user-presentable failure. [message] is always Arabic-friendly text.
class Failure implements Exception {
  final String code;
  final String message;
  const Failure(this.code, this.message);

  @override
  String toString() => 'Failure($code): $message';
}

/// Converts any thrown object into a message a normal user can understand.
String friendlyError(Object error) {
  if (error is Failure) return error.message;
  if (error is FirebaseFunctionsException) {
    final m = error.message;
    if (m != null && m.isNotEmpty && error.code != 'internal' && error.code != 'unknown') {
      return m; // Cloud Functions already return Arabic messages.
    }
    return _byCode(error.code);
  }
  if (error is FirebaseAuthException) return _authMessage(error.code);
  if (error is FirebaseException) return _byCode(error.code);
  return 'حدث خطأ غير متوقع، حاول مرة أخرى';
}

String _byCode(String code) {
  switch (code) {
    case 'unavailable':
    case 'network-request-failed':
    case 'deadline-exceeded':
      return 'تعذّر الاتصال بالإنترنت، تحقق من الشبكة';
    case 'permission-denied':
      return 'ليست لديك صلاحية لهذا الإجراء';
    case 'unauthenticated':
      return 'انتهت الجلسة، سجّل الدخول مجدداً';
    case 'not-found':
      return 'العنصر غير موجود';
    case 'resource-exhausted':
      return 'محاولات كثيرة، حاول لاحقاً';
    default:
      return 'حدث خطأ غير متوقع، حاول مرة أخرى';
  }
}

String _authMessage(String code) {
  switch (code) {
    case 'invalid-phone-number':
      return 'رقم الهاتف غير صحيح، أدخله بالصيغة الدولية';
    case 'invalid-verification-code':
      return 'رمز التحقق غير صحيح';
    case 'session-expired':
    case 'code-expired':
      return 'انتهت صلاحية الرمز، اطلب رمزاً جديداً';
    case 'too-many-requests':
      return 'محاولات كثيرة، انتظر قليلاً ثم حاول';
    case 'wrong-password':
    case 'invalid-credential':
    case 'user-not-found':
      return 'بيانات الدخول غير صحيحة';
    case 'email-already-in-use':
      return 'البريد الإلكتروني مستخدم بالفعل';
    case 'weak-password':
      return 'كلمة السر ضعيفة (6 أحرف على الأقل)';
    case 'invalid-email':
      return 'البريد الإلكتروني غير صالح';
    case 'requires-recent-login':
      return 'لأمانك، سجّل الدخول مجدداً ثم أعد المحاولة';
    case 'network-request-failed':
      return 'تعذّر الاتصال بالإنترنت، تحقق من الشبكة';
    case 'user-disabled':
      return 'تم إيقاف هذا الحساب';
    case 'canceled':
    case 'web-context-canceled':
      return 'تم إلغاء العملية';
    default:
      return 'تعذّر تسجيل الدخول، حاول مرة أخرى';
  }
}

/// True when the error simply means "you are offline".
bool isOfflineError(Object e) {
  if (e is FirebaseException) {
    return e.code == 'unavailable' || e.code == 'network-request-failed';
  }
  return false;
}
