import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/roles.dart';
import '../../../core/errors/failures.dart';
import '../../../core/providers.dart';
import '../../../core/storage/local_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_tile.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/user_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final locale = ref.watch(localeProvider);
    final mode = ref.watch(themeModeProvider);
    Widget section(String key) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 6), child: Text(context.tr(key), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)));

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings.title'))),
      body: ListView(children: [
        section('settings.account'),
        ListTile(leading: const Icon(Icons.edit_rounded), title: Text(context.tr('profile.edit')), onTap: () => context.push('/profile/edit')),
        ListTile(leading: const Icon(Icons.account_balance_wallet_rounded), title: Text(context.tr('wallet.title')), onTap: () => context.push('/wallet')),
        ListTile(leading: const Icon(Icons.emoji_events_rounded), title: Text(context.tr('rank.title')), onTap: () => context.push('/rankings')),
        ListTile(leading: const Icon(Icons.celebration_rounded), title: Text(context.tr('events.title')), onTap: () => context.push('/events')),
        if (me?.role.atLeast(Role.host) ?? false) ListTile(leading: const Icon(Icons.mic_rounded), title: Text(context.tr('host.title')), onTap: () => context.push('/host/dashboard')),
        if (me?.role.isStaff ?? false) ListTile(leading: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.gold), title: Text(context.tr('admin.title')), onTap: () => context.push('/admin')),
        section('settings.appearance'),
        ListTile(
          leading: const Icon(Icons.language_rounded),
          title: Text(context.tr('settings.language')),
          trailing: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'ar', label: Text('العربية')), ButtonSegment(value: 'en', label: Text('English'))],
            selected: {locale.languageCode},
            onSelectionChanged: (s) => ref.read(localeProvider.notifier).set(s.first),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dark_mode_rounded),
          title: Text(context.tr('settings.theme')),
          trailing: DropdownButton<ThemeMode>(
            value: mode,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(value: ThemeMode.dark, child: Text(context.tr('settings.theme_dark'))),
              DropdownMenuItem(value: ThemeMode.light, child: Text(context.tr('settings.theme_light'))),
              DropdownMenuItem(value: ThemeMode.system, child: Text(context.tr('settings.theme_system'))),
            ],
            onChanged: (m) => ref.read(themeModeProvider.notifier).set(m ?? ThemeMode.dark),
          ),
        ),
        section('settings.more'),
        ListTile(leading: const Icon(Icons.lock_rounded), title: Text(context.tr('settings.privacy')), onTap: () => context.push('/settings/privacy')),
        ListTile(leading: const Icon(Icons.security_rounded), title: Text(context.tr('settings.security')), onTap: () => context.push('/settings/security')),
        ListTile(leading: const Icon(Icons.block_rounded), title: Text(context.tr('settings.blocked')), onTap: () => context.push('/settings/blocked')),
        ListTile(leading: const Icon(Icons.info_outline_rounded), title: Text(context.tr('settings.about')), onTap: () => context.push('/settings/about')),
        const Divider(),
        ListTile(leading: const Icon(Icons.logout_rounded, color: AppColors.danger), title: Text(context.tr('settings.logout'), style: const TextStyle(color: AppColors.danger)), onTap: () => ref.read(authRepositoryProvider).signOut()),
      ]),
    );
  }
}

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    if (me == null) return const Scaffold();
    Future<void> save({bool? hide, bool? dm}) async {
      try {
        await ref.read(userRepositoryProvider).updatePrivacy(me.id, hideOnline: hide ?? me.hideOnline, dmFriendsOnly: dm ?? me.dmFriendsOnly);
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings.privacy'))),
      body: ListView(children: [
        SwitchListTile(title: Text(context.tr('privacy.hide_online')), subtitle: Text(context.tr('privacy.hide_online_hint')), value: me.hideOnline, onChanged: (v) => save(hide: v)),
        SwitchListTile(title: Text(context.tr('privacy.dm_friends')), subtitle: Text(context.tr('privacy.dm_friends_hint')), value: me.dmFriendsOnly, onChanged: (v) => save(dm: v)),
      ]),
    );
  }
}

class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  Future<String?> _ask(BuildContext context, String titleKey, {TextInputType? type, bool obscure = false}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(titleKey)),
        content: TextField(controller: c, autofocus: true, keyboardType: type, obscureText: obscure, textDirection: TextDirection.ltr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ctx.tr('common.continue'))),
        ],
      ),
    );
  }

  Future<void> _guard(BuildContext context, Future<void> Function() a, {String? success}) async {
    try {
      await a();
      if (success != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(success))));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(authRepositoryProvider);
    final user = ref.watch(firebaseAuthProvider).currentUser;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings.security'))),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.alternate_email_rounded),
          title: Text(context.tr('security.change_email')),
          subtitle: Text(user?.email ?? '—', textDirection: TextDirection.ltr),
          onTap: () async {
            final email = await _ask(context, 'security.new_email', type: TextInputType.emailAddress);
            if (email == null || !context.mounted) return;
            if (!Validators.email(email)) return _guard(context, () async => throw Failure('email', context.tr('auth.email_invalid')));
            await _guard(context, () => repo.changeEmail(email), success: 'security.email_link_sent');
          },
        ),
        ListTile(
          leading: const Icon(Icons.phone_iphone_rounded),
          title: Text(context.tr('security.change_phone')),
          subtitle: Text(user?.phoneNumber ?? '—', textDirection: TextDirection.ltr),
          onTap: () async {
            final phone = await _ask(context, 'security.new_phone', type: TextInputType.phone);
            if (phone == null || !context.mounted) return;
            if (!Validators.phoneE164(phone)) return _guard(context, () async => throw Failure('phone', context.tr('auth.phone_invalid')));
            await _guard(context, () async {
              final sent = await repo.startPhoneChange(phone);
              if (sent == null) return;
              if (!context.mounted) return;
              final code = await _ask(context, 'auth.verify', type: TextInputType.number);
              if (code == null) return;
              await repo.confirmPhoneChange(sent.verificationId, code);
            }, success: 'security.phone_changed');
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
          title: Text(context.tr('security.delete_account'), style: const TextStyle(color: AppColors.danger)),
          subtitle: Text(context.tr('security.delete_hint')),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(ctx.tr('security.delete_account')),
                content: Text(ctx.tr('security.delete_confirm')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel'))),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('security.delete_account'))),
                ],
              ),
            );
            if (ok == true && context.mounted) await _guard(context, repo.deleteAccount);
          },
        ),
      ]),
    );
  }
}

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myUidProvider);
    final blocked = ref.watch(blockedUsersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings.blocked'))),
      body: AsyncBody<List<AppUser>>(
        value: blocked,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: context.tr('blocked.empty'),
        emptyIcon: Icons.block_rounded,
        onRetry: () => ref.invalidate(blockedUsersProvider),
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => UserTile(
            user: list[i],
            trailing: TextButton(
              onPressed: () async {
                await ref.read(userRepositoryProvider).unblock(me, list[i].id);
                ref.invalidate(blockedUsersProvider);
              },
              child: Text(context.tr('profile.unblock')),
            ),
          ),
        ),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings.about'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(26)),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 44),
          ),
        ),
        const SizedBox(height: 16),
        Center(child: Text(context.tr('app.name'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
        const Center(child: Text('Yemen Chat · v1.0.0')),
        const SizedBox(height: 24),
        Text(context.tr('about.body'), textAlign: TextAlign.center, style: TextStyle(color: context.palette.textMuted, height: 1.6)),
      ]),
    );
  }
}
