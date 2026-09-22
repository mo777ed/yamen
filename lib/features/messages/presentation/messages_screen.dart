import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/user_repository.dart';
import '../data/chat_repository.dart';

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider);
    final me = ref.watch(myUidProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('nav.messages')),
        actions: [IconButton(icon: const Icon(Icons.people_alt_rounded), onPressed: () => context.push('/friends'))],
      ),
      body: AsyncBody<List<ChatSummary>>(
        value: chats,
        isEmpty: (l) => l.isEmpty,
        emptyMessage: context.tr('messages.empty'),
        emptyIcon: Icons.chat_bubble_outline_rounded,
        onRetry: () => ref.invalidate(chatsProvider),
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final c = list[i];
            final other = ref.watch(userProvider(c.otherId(me))).valueOrNull;
            final unread = c.unreadFor(me);
            return ListTile(
              onTap: () => context.push('/messages/${c.id}'),
              leading: UserAvatar(url: other?.avatarUrl ?? '', name: other?.displayName ?? '', size: 50, online: other == null || other.hideOnline ? null : other.online),
              title: Text(other?.displayName ?? '…', style: TextStyle(fontWeight: unread > 0 ? FontWeight.w900 : FontWeight.w700)),
              subtitle: Text(c.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread > 0 ? null : context.palette.textMuted)),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (c.lastAt != null) Text(Fmt.time(c.lastAt!), style: TextStyle(fontSize: 11, color: context.palette.textMuted)),
                if (unread > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(999)),
                    child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId});
  final String chatId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  late final ChatRepository _repo;
  late final String _me;
  late final String _other;
  bool _typing = false;
  Timer? _typingTimer;
  bool _sendingImage = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(chatRepositoryProvider);
    _me = ref.read(myUidProvider);
    _other = widget.chatId.split('_').firstWhere((p) => p != _me, orElse: () => '');
    _text.addListener(_onTyping);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    if (_typing) _repo.setTyping(widget.chatId, _me, false);
    _text.dispose();
    super.dispose();
  }

  void _onTyping() {
    if (_text.text.isNotEmpty && !_typing) {
      _typing = true;
      _repo.setTyping(widget.chatId, _me, true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      if (_typing) {
        _typing = false;
        _repo.setTyping(widget.chatId, _me, false);
      }
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    try {
      await _repo.sendText(widget.chatId, _me, t);
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  Future<void> _sendImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 80);
    if (x == null) return;
    setState(() => _sendingImage = true);
    try {
      await _repo.sendImage(widget.chatId, _me, File(x.path));
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = ref.watch(userProvider(_other)).valueOrNull;
    final messages = ref.watch(chatMessagesProvider(widget.chatId));
    final typing = ref.watch(typingProvider((chatId: widget.chatId, other: _other))).valueOrNull ?? false;
    final blocked = ref.watch(isBlockedProvider(_other)).valueOrNull ?? false;

    ref.listen<AsyncValue<List<ChatMessage>>>(chatMessagesProvider(widget.chatId), (_, next) {
      next.whenData((list) => _repo.markRead(widget.chatId, _me, list).catchError((_) {}));
    });

    final statusText = typing
        ? context.tr('chat.typing')
        : (other == null || other.hideOnline)
            ? ''
            : other.online
                ? context.tr('chat.online')
                : other.lastSeen == null
                    ? ''
                    : context.tr('chat.last_seen', {'t': Fmt.time(other.lastSeen!)});

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => context.push('/profile/$_other'),
          child: Row(children: [
            UserAvatar(url: other?.avatarUrl ?? '', name: other?.displayName ?? '', size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(other?.displayName ?? '…', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                if (statusText.isNotEmpty) Text(statusText, style: TextStyle(fontSize: 11.5, color: typing ? AppColors.success : context.palette.textMuted)),
              ]),
            ),
          ]),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: AsyncBody<List<ChatMessage>>(
            value: messages,
            isEmpty: (l) => l.isEmpty,
            emptyMessage: context.tr('chat.say_hi'),
            emptyIcon: Icons.waving_hand_rounded,
            onRetry: () => ref.invalidate(chatMessagesProvider(widget.chatId)),
            data: (list) => ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (_, i) => _Bubble(message: list[i], mine: list[i].senderId == _me, otherId: _other),
            ),
          ),
        ),
        if (_sendingImage) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          top: false,
          child: blocked
              ? Padding(padding: const EdgeInsets.all(16), child: Text(context.tr('chat.blocked')))
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Row(children: [
                    IconButton(icon: const Icon(Icons.image_outlined), onPressed: _sendingImage ? null : _sendImage),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(hintText: context.tr('chat.hint'), counterText: '', isDense: true),
                      ),
                    ),
                    IconButton.filled(icon: const Icon(Icons.send_rounded), onPressed: _send),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.otherId});
  final ChatMessage message;
  final bool mine;
  final String otherId;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final seen = mine && m.readBy.contains(otherId);
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: m.imageUrl.isNotEmpty ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: mine ? AppColors.primaryGradient : null,
          color: mine ? null : context.palette.surface,
          border: mine ? null : Border.all(color: context.palette.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          if (m.imageUrl.isNotEmpty)
            ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: m.imageUrl, width: 220, fit: BoxFit.cover, memCacheWidth: 660))
          else
            Align(alignment: AlignmentDirectional.centerStart, child: Text(m.text, style: TextStyle(color: mine ? Colors.white : null))),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (m.createdAt != null) Text(Fmt.time(m.createdAt!), style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : context.palette.textMuted)),
            if (mine) ...[const SizedBox(width: 4), Icon(seen ? Icons.done_all_rounded : Icons.done_rounded, size: 14, color: seen ? Colors.lightBlueAccent : Colors.white70)],
          ]),
        ]),
      ),
    );
  }
}
