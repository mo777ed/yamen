import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/countries.dart';
import '../../../core/errors/failures.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../auth/data/auth_repository.dart';
import '../data/user_repository.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _bio;
  late Country _country;
  String? _gender;
  File? _avatar;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final u = ref.read(currentUserProvider);
    _name = TextEditingController(text: u?.displayName ?? '');
    _bio = TextEditingController(text: u?.bio ?? '');
    _country = countryByCode(u?.country ?? 'YE');
    _gender = u?.gender;
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return;
    setState(() => _busy = true);
    try {
      final uid = ref.read(myUidProvider);
      final url = _avatar == null ? null : await ref.read(authRepositoryProvider).uploadAvatar(_avatar!);
      await ref.read(userRepositoryProvider).updateProfile(uid, displayName: _name.text.trim(), bio: _bio.text.trim(), avatarUrl: url, country: _country.code, gender: _gender);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('profile.edit'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
          child: GestureDetector(
            onTap: () async {
              final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
              if (x != null) setState(() => _avatar = File(x.path));
            },
            child: _avatar != null ? ClipOval(child: Image.file(_avatar!, width: 104, height: 104, fit: BoxFit.cover)) : UserAvatar(url: u?.avatarUrl ?? '', name: u?.displayName ?? '', size: 104),
          ),
        ),
        const SizedBox(height: 20),
        TextField(controller: _name, maxLength: 40, decoration: InputDecoration(hintText: context.tr('profile.display_name'), counterText: '')),
        const SizedBox(height: 12),
        DropdownButtonFormField<Country>(
          value: _country,
          isExpanded: true,
          items: [for (final c in kCountries) DropdownMenuItem(value: c, child: Text('${c.flag}  ${c.name(context.isArabic)}'))],
          onChanged: (c) => setState(() => _country = c ?? _country),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String?>(
          emptySelectionAllowed: true,
          segments: [ButtonSegment(value: 'male', label: Text(context.tr('profile.male'))), ButtonSegment(value: 'female', label: Text(context.tr('profile.female')))],
          selected: {if (_gender != null) _gender},
          onSelectionChanged: (s) => setState(() => _gender = s.isEmpty ? null : s.first),
        ),
        const SizedBox(height: 12),
        TextField(controller: _bio, maxLength: 160, maxLines: 3, decoration: InputDecoration(hintText: context.tr('profile.bio'))),
        const SizedBox(height: 16),
        GradientButton(label: context.tr('common.save'), onPressed: _save, loading: _busy),
      ]),
    );
  }
}
