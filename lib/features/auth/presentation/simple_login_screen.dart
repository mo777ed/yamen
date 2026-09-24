import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/errors/failures.dart';
import '../../../core/storage/local_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../data/auth_repository.dart';

/// Simplified login: just a name and a phone number, no verification code.
/// Uses Firebase Anonymous sign-in under the hood (a real, secure Firebase
/// session) so no SMS, no SHA-1 fingerprints, and no OTP screen are needed.
/// The phone number is stored as private profile metadata only.
class SimpleLoginScreen extends ConsumerStatefulWidget {
  const SimpleLoginScreen({super.key});
  @override
  ConsumerState<SimpleLoginScreen> createState() => _SimpleLoginScreenState();
}

class _SimpleLoginScreenState extends ConsumerState<SimpleLoginScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  String _randomSuffix() {
    final n = DateTime.now().microsecondsSinceEpoch % 100;
    return n.toString().padLeft(2, '0');
  }

  String _usernameFromPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final tail = digits.length > 8 ? digits.substring(digits.length - 8) : digits.padLeft(6, '0');
    return 'u$tail${_randomSuffix()}';
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'اكتب اسمك (حرفين على الأقل)');
      return;
    }
    if (phone.replaceAll(RegExp(r'[^0-9]'), '').length < 6) {
      setState(() => _error = 'اكتب رقم هاتف صحيح');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final repo = ref.read(authRepositoryProvider);
    try {
      // 1) Real, secure Firebase session - no SMS, no OTP.
      await FirebaseAuth.instance.signInAnonymously();

      // 2) Wait for the server (onUserCreated Cloud Function) to create the
      //    base user/wallet/level documents. Usually takes 1-3 seconds.
      final session = await repo
          .sessionStream()
          .firstWhere((s) => s.status != SessionStatus.loading)
          .timeout(const Duration(seconds: 20));

      if (session.status == SessionStatus.needsProfile) {
        // 3) Finish the profile automatically with just the name + phone.
        //    Username, country, language and date of birth are filled with
        //    safe defaults so the person never has to type them.
        var username = _usernameFromPhone(phone);
        for (var attempt = 0; attempt < 4; attempt++) {
          try {
            await repo.completeProfile(
              username: username,
              displayName: name,
              country: 'YE',
              lang: ref.read(localeProvider).languageCode,
              dob: '2000-01-01',
              phone: phone,
            );
            break;
          } on Failure catch (f) {
            if (f.code == 'already-exists' && attempt < 3) {
              username = _usernameFromPhone(phone); // retry with a new random suffix
              continue;
            }
            rethrow;
          }
        }
      }
      // Router redirect moves to /home automatically once the session is active.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(28)),
                      child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 46),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('يمن شات', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('أدخل اسمك ورقم هاتفك للمتابعة', textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _name,
                    maxLength: 40,
                    decoration: const InputDecoration(hintText: 'الاسم', counterText: ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
                    decoration: const InputDecoration(hintText: 'رقم الهاتف'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 20),
                  GradientButton(label: 'دخول', onPressed: _submit, loading: _busy),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
