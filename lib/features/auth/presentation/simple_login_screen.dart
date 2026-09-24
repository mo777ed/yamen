import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/errors/failures.dart';
import '../../../core/storage/local_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../data/auth_repository.dart';

/// Simple login:
/// Name + phone number only.
/// No SMS, no OTP, no password.
///
/// Firebase Anonymous Authentication is used only to create
/// a real Firebase session. The phone number is stored as
/// profile metadata and is NOT verified.
class SimpleLoginScreen extends ConsumerStatefulWidget {
  const SimpleLoginScreen({super.key});

  @override
  ConsumerState<SimpleLoginScreen> createState() =>
      _SimpleLoginScreenState();
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
    final n = DateTime.now().microsecondsSinceEpoch % 10000;
    return n.toString().padLeft(4, '0');
  }

  String _usernameFromPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    final tail = digits.length > 8
        ? digits.substring(digits.length - 8)
        : digits.padLeft(8, '0');

    return 'u$tail${_randomSuffix()}';
  }

  Future<void> _submit() async {
    if (_busy) return;

    final name = _name.text.trim();
    final phone = _phone.text.trim();

    // -----------------------------
    // Validate name
    // -----------------------------
    if (name.length < 2) {
      setState(() {
        _error = 'اكتب اسمك (حرفين على الأقل)';
      });
      return;
    }

    // -----------------------------
    // Validate phone
    // -----------------------------
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length < 6) {
      setState(() {
        _error = 'اكتب رقم هاتف صحيح';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final repo = ref.read(authRepositoryProvider);

    try {
      // =====================================================
      // 1. Create Firebase Anonymous session
      // =====================================================
      //
      // IMPORTANT:
      // We DO NOT wait for the users/{uid} Firestore document.
      //
      // The old code waited for that document before calling
      // completeProfile(), which caused an infinite loading loop.
      //
      User user;

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null) {
        user = currentUser;
      } else {
        final credential =
            await FirebaseAuth.instance.signInAnonymously();

        user = credential.user!;

        if (user.uid.isEmpty) {
          throw const Failure(
            'auth-failed',
            'تعذر إنشاء جلسة الدخول',
          );
        }
      }

      // =====================================================
      // 2. Create profile immediately
      // =====================================================
      //
      // No OTP
      // No SMS
      // No phone verification
      // No waiting for Cloud Function to create a base user
      //
      var username = _usernameFromPhone(phone);

      var completed = false;

      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          await repo.completeProfile(
            username: username,
            displayName: name,
            country: 'YE',
            lang: ref.read(localeProvider).languageCode,
            dob: '2000-01-01',
            phone: phone,
          );

          completed = true;
          break;
        } on Failure catch (f) {
          if (f.code == 'already-exists' && attempt < 4) {
            username = _usernameFromPhone(phone);
            continue;
          }

          rethrow;
        }
      }

      if (!completed) {
        throw const Failure(
          'profile-failed',
          'تعذر إنشاء الحساب، حاول مرة أخرى',
        );
      }

      // =====================================================
      // 3. Wait only for the profile to become active
      // =====================================================
      //
      // This is NOT required for login itself.
      // It only gives the router a moment to receive the
      // Firestore profile update.
      //
      // We do not block forever.
      try {
        await repo
            .sessionStream()
            .firstWhere(
              (session) =>
                  session.status == SessionStatus.active ||
                  session.status == SessionStatus.banned ||
                  session.status == SessionStatus.signedOut,
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Do not show an error here.
        //
        // The Firebase session and profile creation already
        // succeeded. The router/session provider will update
        // automatically when Firestore emits the document.
      }

      if (!mounted) return;

      // The router should automatically move to /home
      // when session becomes active.
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = friendlyError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),

                  // Logo
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        color: Colors.white,
                        size: 46,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'يمن شات',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'أدخل اسمك ورقم هاتفك للمتابعة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.palette.textMuted,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Name
                  TextField(
                    controller: _name,
                    maxLength: 40,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'الاسم',
                      counterText: '',
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Phone
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9 +]'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'رقم الهاتف',
                    ),
                  ),

                  // Error
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.danger,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Login button
                  GradientButton(
                    label: 'دخول',
                    onPressed: _submit,
                    loading: _busy,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
