import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/countries.dart';
import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _emailMode = false;
  bool _registerMode = false;
  bool _busy = false;
  Country _country = kCountries.first;
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
        var digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.startsWith('0')) digits = digits.substring(1);
        final full = '${_country.dial}$digits';
        if (!Validators.phoneE164(full)) throw Failure('phone', context.tr('auth.phone_invalid'));
        final res = await ref.read(authRepositoryProvider).verifyPhone(full);
        if (res == null) return; // auto-verified on Android, router takes over
        ref.read(pendingPhoneProvider.notifier).state = PendingPhone(full, res.verificationId, res.resendToken);
        if (mounted) context.push('/auth/otp');
      });

  Future<void> _emailSubmit() => _run(() async {
        if (!Validators.email(_email.text)) throw Failure('email', context.tr('auth.email_invalid'));
        if (!Validators.password(_password.text)) throw Failure('pw', context.tr('auth.password_short'));
        final repo = ref.read(authRepositoryProvider);
        if (_registerMode) {
          await repo.registerWithEmail(_email.text, _password.text);
        } else {
          await repo.signInWithEmail(_email.text, _password.text);
        }
      });

  Future<void> _forgot() => _run(() async {
        if (!Validators.email(_email.text)) throw Failure('email', context.tr('auth.email_invalid'));
        await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
        if (mounted) _toast(context.tr('auth.reset_sent'));
      });

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(authRepositoryProvider);
    final showApple = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(28)),
                      child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 46),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(context.tr('app.name'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(context.tr('auth.tagline'), textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted)),
                  const SizedBox(height: 28),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(context.tr('auth.phone')), icon: const Icon(Icons.phone_iphone_rounded)),
                      ButtonSegment(value: true, label: Text(context.tr('auth.email')), icon: const Icon(Icons.alternate_email_rounded)),
                    ],
                    selected: {_emailMode},
                    onSelectionChanged: (s) => setState(() => _emailMode = s.first),
                  ),
                  const SizedBox(height: 20),
                  if (!_emailMode) ..._phoneForm() else ..._emailForm(),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(context.tr('auth.or'), style: TextStyle(color: context.palette.textMuted))),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(repo.signInWithGoogle),
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
                    label: Text(context.tr('auth.google')),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  ),
                  if (showApple) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(repo.signInWithApple),
                      icon: const Icon(Icons.apple_rounded),
                      label: Text(context.tr('auth.apple')),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(context.tr('auth.terms'), textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneForm() {
    final ar = context.isArabic;
    return [
      Row(
        textDirection: TextDirection.ltr,
        children: [
          SizedBox(
            width: 128,
            child: DropdownButtonFormField<Country>(
              value: _country,
              isExpanded: true,
              items: [
                for (final c in kCountries)
                  DropdownMenuItem(value: c, child: Text('${c.flag} ${c.dial}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (c) => setState(() => _country = c ?? _country),
              selectedItemBuilder: (_) => [for (final c in kCountries) Text('${c.flag} ${c.dial}')],
              decoration: const InputDecoration(),
              menuMaxHeight: 320,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
              decoration: InputDecoration(hintText: ar ? '7X XXX XXXX' : 'Phone number'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      GradientButton(label: context.tr('auth.send_code'), onPressed: _sendCode, loading: _busy),
    ];
  }

  List<Widget> _emailForm() {
    return [
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        textDirection: TextDirection.ltr,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(hintText: context.tr('auth.email')),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        decoration: InputDecoration(hintText: context.tr('auth.password')),
      ),
      const SizedBox(height: 16),
      GradientButton(
        label: context.tr(_registerMode ? 'auth.create_account' : 'auth.login'),
        onPressed: _emailSubmit,
        loading: _busy,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(onPressed: () => setState(() => _registerMode = !_registerMode), child: Text(context.tr(_registerMode ? 'auth.have_account' : 'auth.no_account'))),
          if (!_registerMode) TextButton(onPressed: _busy ? null : _forgot, child: Text(context.tr('auth.forgot'))),
        ],
      ),
    ];
  }
}
