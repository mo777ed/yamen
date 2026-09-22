import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/countries.dart';
import '../../../core/errors/failures.dart';
import '../../../core/storage/local_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../data/auth_repository.dart';

/// Shown once after the first sign-in to finish the profile.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  Country _country = kCountries.first;
  DateTime? _dob;
  String? _gender;
  File? _avatar;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final u = ref.read(currentUserProvider);
    if (u != null) _name.text = u.displayName;
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickAvatar() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
    if (x != null) setState(() => _avatar = File(x.path));
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20, 1, 1),
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (d != null) setState(() => _dob = d);
  }

  Future<void> _submit() async {
    final username = _username.text.trim().toLowerCase();
    if (_name.text.trim().length < 2) return _toast(context.tr('profile.name_short'));
    if (!Validators.username(username)) return _toast(context.tr('profile.username_invalid'));
    if (_dob == null) return _toast(context.tr('profile.dob_required'));
    if (!Validators.oldEnough(_dob!)) return _toast(context.tr('profile.too_young'));
    setState(() => _busy = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      final avatarUrl = _avatar == null ? null : await repo.uploadAvatar(_avatar!);
      await repo.completeProfile(
        username: username,
        displayName: _name.text.trim(),
        country: _country.code,
        lang: ref.read(localeProvider).languageCode,
        dob: Fmt.utcDay(_dob!),
        gender: _gender,
        bio: _bio.text.trim(),
        avatarUrl: avatarUrl,
      );
      // Session stream flips to "active" and the router moves to /home.
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.isArabic;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile.complete_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    _avatar != null
                        ? ClipOval(child: Image.file(_avatar!, width: 104, height: 104, fit: BoxFit.cover))
                        : UserAvatar(url: '', name: _name.text, size: 104),
                    PositionedDirectional(
                      end: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.primaryGradient),
                        child: const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(controller: _name, maxLength: 40, decoration: InputDecoration(hintText: context.tr('profile.display_name'), counterText: '')),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              maxLength: 20,
              textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]'))],
              decoration: InputDecoration(hintText: context.tr('profile.username'), prefixText: '@', counterText: ''),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Country>(
              value: _country,
              isExpanded: true,
              items: [for (final c in kCountries) DropdownMenuItem(value: c, child: Text('${c.flag}  ${c.name(ar)}'))],
              onChanged: (c) => setState(() => _country = c ?? _country),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDob,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(),
                child: Row(children: [
                  const Icon(Icons.cake_outlined, size: 20),
                  const SizedBox(width: 10),
                  Text(_dob == null ? context.tr('profile.dob') : Fmt.date(_dob!, ar ? 'ar' : 'en')),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String?>(
              emptySelectionAllowed: true,
              segments: [
                ButtonSegment(value: 'male', label: Text(context.tr('profile.male'))),
                ButtonSegment(value: 'female', label: Text(context.tr('profile.female'))),
              ],
              selected: {if (_gender != null) _gender},
              onSelectionChanged: (s) => setState(() => _gender = s.isEmpty ? null : s.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: _bio, maxLength: 160, maxLines: 3, decoration: InputDecoration(hintText: context.tr('profile.bio'))),
            const SizedBox(height: 20),
            GradientButton(label: context.tr('common.continue'), onPressed: _submit, loading: _busy),
            TextButton(onPressed: () => ref.read(authRepositoryProvider).signOut(), child: Text(context.tr('settings.logout'))),
          ],
        ),
      ),
    );
  }
}
