import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../auth/data/auth_repository.dart';
import '../data/room_repository.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});
  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _password = TextEditingController();
  String _category = 'chat';
  bool _private = false;
  int _seats = 8;
  File? _cover;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickCover() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 80);
    if (x != null) setState(() => _cover = File(x.path));
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 2) return _toast(context.tr('room.name_short'));
    if (_private && _password.text.trim().length < 4) return _toast(context.tr('room.password_short'));
    setState(() => _busy = true);
    try {
      final repo = ref.read(roomRepositoryProvider);
      final uid = ref.read(myUidProvider);
      final cover = _cover == null ? '' : await repo.uploadCover(uid, _cover!);
      final id = await repo.create(
        name: _name.text.trim(),
        category: _category,
        isPrivate: _private,
        password: _private ? _password.text.trim() : null,
        seatCount: _seats,
        coverUrl: cover,
        description: _desc.text.trim(),
      );
      if (mounted) context.pushReplacement('/room/$id');
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('room.create'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GestureDetector(
              onTap: _pickCover,
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: context.palette.surface,
                  border: Border.all(color: context.palette.border),
                  image: _cover == null ? null : DecorationImage(image: FileImage(_cover!), fit: BoxFit.cover),
                ),
                child: _cover == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.add_photo_alternate_outlined, size: 36, color: AppColors.primary),
                        const SizedBox(height: 6),
                        Text(context.tr('room.add_cover'), style: TextStyle(color: context.palette.textMuted)),
                      ])
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            TextField(controller: _name, maxLength: 40, decoration: InputDecoration(hintText: context.tr('room.name'), counterText: '')),
            const SizedBox(height: 12),
            TextField(controller: _desc, maxLength: 200, maxLines: 2, decoration: InputDecoration(hintText: context.tr('room.description'), counterText: '')),
            const SizedBox(height: 16),
            Text(context.tr('room.category'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in RoomCategory.all)
                ChoiceChip(label: Text(context.tr('cat.$c')), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
            ]),
            const SizedBox(height: 16),
            Text(context.tr('room.seats'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [for (final n in [6, 8, 10, 12]) ButtonSegment(value: n, label: Text('$n'))],
              selected: {_seats},
              onSelectionChanged: (s) => setState(() => _seats = s.first),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('room.private')),
              subtitle: Text(context.tr('room.private_hint')),
              value: _private,
              onChanged: (v) => setState(() => _private = v),
            ),
            if (_private) TextField(controller: _password, obscureText: true, maxLength: 32, decoration: InputDecoration(hintText: context.tr('room.password'), counterText: '')),
            const SizedBox(height: 20),
            GradientButton(label: context.tr('room.create_action'), icon: Icons.mic_rounded, onPressed: _create, loading: _busy),
          ],
        ),
      ),
    );
  }
}
