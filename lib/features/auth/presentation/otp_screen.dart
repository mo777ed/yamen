import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../data/auth_repository.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  int _cooldown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cooldown <= 1) {
        t.cancel();
      }
      if (mounted) setState(() => _cooldown = (_cooldown - 1).clamp(0, 999));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _confirm() async {
    final pending = ref.read(pendingPhoneProvider);
    if (pending == null) {
      context.go('/auth/login');
      return;
    }
    if (_code.text.trim().length != 6) {
      _toast(context.tr('auth.code_invalid'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).confirmOtp(pending.verificationId, _code.text);
      // Router redirect moves the user forward once the session updates.
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final pending = ref.read(pendingPhoneProvider);
    if (pending == null) return;
    try {
      final res = await ref.read(authRepositoryProvider).verifyPhone(pending.phone, resendToken: pending.resendToken);
      if (res != null) {
        ref.read(pendingPhoneProvider.notifier).state = PendingPhone(pending.phone, res.verificationId, res.resendToken);
      }
      _startCooldown();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingPhoneProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('auth.verify'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('auth.code_sent_to', {'phone': pending?.phone ?? ''}), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                maxLength: 6,
                style: const TextStyle(fontSize: 30, letterSpacing: 10, fontWeight: FontWeight.w800),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  if (v.length == 6 && !_busy) _confirm();
                },
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 16),
              GradientButton(label: context.tr('auth.confirm'), onPressed: _confirm, loading: _busy),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _cooldown == 0 ? _resend : null,
                child: Text(_cooldown == 0 ? context.tr('auth.resend') : context.tr('auth.resend_in', {'s': _cooldown}),
                    style: TextStyle(color: _cooldown == 0 ? AppColors.primary : context.palette.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
