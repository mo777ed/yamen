import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/roles.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/voice/voice_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/components/badges.dart';
import '../../../shared/components/user_avatar.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/states.dart';
import '../../auth/data/auth_repository.dart';
import '../../gifts/presentation/gift_overlay.dart';
import '../../gifts/presentation/gift_panel.dart';
import '../../rooms/data/room_repository.dart';
import 'chat_widgets.dart';
import 'seat_grid.dart';
import 'voice_providers.dart';

class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key, required this.roomId, this.password});
  final String roomId;
  final String? password;

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  late final RoomRepository _repo;
  late final VoiceService _voice;
  final _chat = TextEditingController();
  StreamSubscription<String>? _handSub;
  bool _joining = true;
  bool _joined = false;
  bool _voiceFailed = false;
  bool _micBusy = false;
  Object? _error;

  String get roomId => widget.roomId;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(roomRepositoryProvider);
    _voice = ref.read(voiceServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _join(widget.password));
  }

  @override
  void dispose() {
    _handSub?.cancel();
    _chat.dispose();
    if (_joined) {
      // Voice engine is disposed by its autoDispose provider; this frees the seat and member slot.
      unawaited(_repo.leave(roomId).catchError((_) {}));
    }
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _join(String? password) async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await _repo.join(roomId, password: password);
      _joined = true;
      await _connectVoice();
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _connectVoice() async {
    try {
      await _voice.joinRoom(roomId);
      _handSub?.cancel();
      _handSub = _voice.handRaises.listen(_onHand);
      _voiceFailed = false;
    } catch (_) {
      _voiceFailed = true; // chat still works without audio
    }
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _toast(friendlyError(e));
    }
  }

  // -------- mic handling --------
  Future<void> _setMic(bool on) async {
    if (_micBusy) return;
    _micBusy = true;
    try {
      if (on) {
        try {
          await _voice.unmute();
        } on Failure catch (f) {
          if (f.code == 'mic-denied') {
            // Server-side publish permission can lag the seat write by a moment.
            await Future<void>.delayed(const Duration(milliseconds: 900));
            await _voice.unmute();
          } else {
            rethrow;
          }
        }
      } else {
        await _voice.mute();
      }
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      _micBusy = false;
      if (mounted) setState(() {});
    }
  }

  void _syncMic(List<Seat> seats, String myUid) {
    Seat? mine;
    for (final s in seats) {
      if (s.userId == myUid) mine = s;
    }
    final shouldSpeak = mine != null && !mine.micMuted;
    if (shouldSpeak && _voice.isMuted) _setMic(true);
    if (!shouldSpeak && !_voice.isMuted) _setMic(false);
  }

  void _onHand(String uid) {
    final me = ref.read(myRoomMemberProvider(roomId)).valueOrNull;
    if (me == null || !me.role.canManage) return;
    final member = ref.read(roomMembersProvider(roomId)).valueOrNull?.where((m) => m.uid == uid).firstOrNull;
    final seats = ref.read(roomSeatsProvider(roomId)).valueOrNull ?? const [];
    final free = seats.where((s) => s.empty && !s.locked).firstOrNull;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('room.hand_raised', {'name': member?.displayName ?? ''})),
      action: free == null ? null : SnackBarAction(label: context.tr('room.invite'), onPressed: () => _run(() => _repo.manageSeat(roomId, 'invite', seat: free.index, targetUid: uid))),
    ));
  }

  // -------- actions --------
  Future<void> _sendMessage() async {
    final text = _chat.text.trim();
    final me = ref.read(currentUserProvider);
    if (text.isEmpty || me == null) return;
    _chat.clear();
    await _run(() => _repo.sendMessage(roomId, me, text));
  }

  void _openGifts({String? receiverId}) {
    final room = ref.read(roomProvider(roomId)).valueOrNull;
    final members = ref.read(roomMembersProvider(roomId)).valueOrNull ?? const [];
    final seats = ref.read(roomSeatsProvider(roomId)).valueOrNull ?? const [];
    final myUid = ref.read(myUidProvider);
    final map = {for (final m in members) m.uid: m};
    final receivers = <GiftReceiver>[];
    void add(String uid, String name, String avatar) {
      if (uid == myUid || receivers.any((r) => r.uid == uid)) return;
      receivers.add(GiftReceiver(uid, name, avatar));
    }

    if (room != null) add(room.ownerId, room.ownerName, room.ownerAvatar);
    for (final s in seats) {
      if (!s.empty) add(s.userId!, map[s.userId]?.displayName ?? '', map[s.userId]?.avatarUrl ?? '');
    }
    if (receivers.isEmpty) {
      _toast(context.tr('gift.no_receiver'));
      return;
    }
    showGiftPanel(context, roomId: roomId, receivers: receivers, initialReceiverId: receiverId);
  }

  void _openGames() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final g in const ['dice', 'wheel', 'rps', 'guess'])
            ListTile(
              leading: const Icon(Icons.casino_rounded, color: AppColors.gold),
              title: Text(ctx.tr('game.$g')),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/games/$g');
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _share() async {
    final domain = dotenv.maybeGet('APP_DOMAIN') ?? 'yemenchat.app';
    final room = ref.read(roomProvider(roomId)).valueOrNull;
    await Share.share('${room?.name ?? ''} — https://$domain/room/$roomId');
  }

  void _onSeatTap(Seat seat, RoomMember? occupant) {
    final myUid = ref.read(myUidProvider);
    final myRole = ref.read(myRoomMemberProvider(roomId)).valueOrNull?.role ?? RoomRole.listener;
    final seats = ref.read(roomSeatsProvider(roomId)).valueOrNull ?? const [];
    final iAmSeated = seats.any((s) => s.userId == myUid);

    if (seat.empty) {
      if (myRole.canManage) {
        _sheet([
          if (!iAmSeated && !seat.locked) _Action(Icons.mic_rounded, context.tr('seat.take'), () => _repo.manageSeat(roomId, 'take', seat: seat.index)),
          _Action(seat.locked ? Icons.lock_open_rounded : Icons.lock_rounded, context.tr(seat.locked ? 'seat.unlock' : 'seat.lock'), () => _repo.manageSeat(roomId, seat.locked ? 'unlock' : 'lock', seat: seat.index)),
          if (!seat.locked) _Action(Icons.person_add_alt_1_rounded, context.tr('seat.invite'), () async => _pickListener((uid) => _repo.manageSeat(roomId, 'invite', seat: seat.index, targetUid: uid))),
        ]);
      } else if (seat.locked) {
        _toast(context.tr('seat.locked'));
      } else if (iAmSeated) {
        _toast(context.tr('seat.already'));
      } else {
        _run(() => _repo.manageSeat(roomId, 'take', seat: seat.index));
      }
      return;
    }
    if (occupant == null) return;
    if (occupant.uid == myUid) {
      _sheet([
        _Action(_voice.isMuted ? Icons.mic_rounded : Icons.mic_off_rounded, context.tr(_voice.isMuted ? 'room.unmute' : 'room.mute'), () => _setMic(_voice.isMuted)),
        _Action(Icons.logout_rounded, context.tr('seat.leave'), () => _repo.manageSeat(roomId, 'leave')),
      ]);
      return;
    }
    _showUserActions(occupant, seat: seat);
  }

  Future<void> _pickListener(Future<void> Function(String uid) onPick) async {
    final members = (ref.read(roomMembersProvider(roomId)).valueOrNull ?? const [])
        .where((m) => m.role == RoomRole.listener || m.role == RoomRole.speaker)
        .where((m) => !(ref.read(roomSeatsProvider(roomId)).valueOrNull ?? const []).any((s) => s.userId == m.uid))
        .toList();
    if (!mounted) return;
    final uid = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: members.isEmpty
            ? SizedBox(height: 160, child: EmptyState(message: ctx.tr('room.no_listeners')))
            : ListView(shrinkWrap: true, children: [
                for (final m in members)
                  ListTile(leading: UserAvatar(url: m.avatarUrl, name: m.displayName, size: 40), title: Text(m.displayName), onTap: () => Navigator.pop(ctx, m.uid)),
              ]),
      ),
    );
    if (uid != null) await _run(() => onPick(uid));
  }

  void _sheet(List<_Action> actions, {Widget? header}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (header != null) header,
            for (final a in actions)
              ListTile(
                leading: Icon(a.icon, color: a.danger ? AppColors.danger : null),
                title: Text(a.label, style: TextStyle(color: a.danger ? AppColors.danger : null)),
                onTap: () {
                  Navigator.pop(ctx);
                  _run(() async => await a.run());
                },
              ),
          ]),
        ),
      ),
    );
  }

  void _showUserActions(RoomMember target, {Seat? seat}) {
    final myUid = ref.read(myUidProvider);
    final myRole = ref.read(myRoomMemberProvider(roomId)).valueOrNull?.role ?? RoomRole.listener;
    final accountStaff = ref.read(currentUserProvider)?.role.isStaff ?? false;
    final canManage = (myRole.canManage && target.role.index < myRole.index) || accountStaff;
    final isSelf = target.uid == myUid;
    final free = (ref.read(roomSeatsProvider(roomId)).valueOrNull ?? const []).where((s) => s.empty && !s.locked).firstOrNull;

    _sheet([
      _Action(Icons.person_rounded, context.tr('room.view_profile'), () async => context.push('/profile/${target.uid}')),
      if (!isSelf) _Action(Icons.card_giftcard_rounded, context.tr('gift.send_to'), () async => _openGifts(receiverId: target.uid)),
      if (target.username.isNotEmpty) _Action(Icons.alternate_email_rounded, context.tr('room.mention'), () async {
            _chat.text = '${_chat.text}@${target.username} ';
            _chat.selection = TextSelection.collapsed(offset: _chat.text.length);
          }),
      if (canManage && !isSelf) ...[
        if (seat != null) ...[
          _Action(seat.micMuted ? Icons.mic_rounded : Icons.mic_off_rounded, context.tr(seat.micMuted ? 'seat.unmute_user' : 'seat.mute_user'), () => _repo.manageSeat(roomId, seat.micMuted ? 'unmute' : 'mute', seat: seat.index)),
          _Action(Icons.event_seat_rounded, context.tr('seat.remove'), () => _repo.manageSeat(roomId, 'remove', seat: seat.index)),
          _Action(Icons.swap_horiz_rounded, context.tr('seat.move'), () async => _moveSeat(seat)),
        ] else if (free != null)
          _Action(Icons.mic_external_on_rounded, context.tr('seat.invite'), () => _repo.manageSeat(roomId, 'invite', seat: free.index, targetUid: target.uid)),
        _Action(target.chatMuted ? Icons.chat_rounded : Icons.comments_disabled_rounded, context.tr(target.chatMuted ? 'room.unmute_chat' : 'room.mute_chat'), () => _repo.moderate(roomId, target.chatMuted ? 'unmuteChat' : 'muteChat', targetUid: target.uid, minutes: 10)),
        if (myRole == RoomRole.owner || accountStaff) ...[
          _Action(Icons.shield_rounded, context.tr(target.role == RoomRole.mod ? 'room.remove_mod' : 'room.make_mod'), () => _repo.moderate(roomId, 'setRole', targetUid: target.uid, role: target.role == RoomRole.mod ? 'listener' : 'mod')),
        ],
        _Action(Icons.exit_to_app_rounded, context.tr('room.kick'), () => _repo.moderate(roomId, 'kick', targetUid: target.uid), danger: true),
        _Action(Icons.block_rounded, context.tr('room.ban'), () => _repo.moderate(roomId, 'ban', targetUid: target.uid, minutes: 60), danger: true),
      ],
      if (!isSelf) _Action(Icons.flag_rounded, context.tr('report.user'), () async => context.push('/report/user/${target.uid}'), danger: true),
    ],
        header: ListTile(
          leading: UserAvatar(url: target.avatarUrl, name: target.displayName, size: 46, vipLevel: target.vipLevel),
          title: Row(children: [Flexible(child: Text(target.displayName, overflow: TextOverflow.ellipsis)), const SizedBox(width: 6), LevelBadge(level: target.level), const SizedBox(width: 4), VipBadge(level: target.vipLevel)]),
          subtitle: Text(context.tr('role.${target.role.name}')),
        ));
  }

  Future<void> _moveSeat(Seat from) async {
    final seats = (ref.read(roomSeatsProvider(roomId)).valueOrNull ?? const []).where((s) => s.empty && !s.locked).toList();
    final to = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: seats.isEmpty
            ? SizedBox(height: 140, child: EmptyState(message: ctx.tr('seat.none_free')))
            : Wrap(spacing: 10, runSpacing: 10, children: [
                for (final s in seats) ActionChip(label: Text(ctx.tr('seat.number', {'n': s.index})), onPressed: () => Navigator.pop(ctx, s.index)),
              ]),
      ),
    );
    if (to != null) await _run(() => _repo.manageSeat(roomId, 'move', seat: from.index, toSeat: to));
  }

  void _onMessageLongPress(RoomMessage m) {
    final myUid = ref.read(myUidProvider);
    final myRole = ref.read(myRoomMemberProvider(roomId)).valueOrNull?.role ?? RoomRole.listener;
    final staff = ref.read(currentUserProvider)?.role.isStaff ?? false;
    final canManage = myRole.canManage || staff;
    _sheet([
      _Action(Icons.copy_rounded, context.tr('common.copy'), () async => Clipboard.setData(ClipboardData(text: m.text))),
      if (canManage) _Action(Icons.delete_outline_rounded, context.tr('room.delete_message'), () => _repo.moderate(roomId, 'deleteMessage', messageId: m.id), danger: true),
      if (canManage && m.senderId != myUid) _Action(Icons.comments_disabled_rounded, context.tr('room.mute_chat'), () => _repo.moderate(roomId, 'muteChat', targetUid: m.senderId, minutes: 10)),
      if (m.senderId != myUid) _Action(Icons.flag_rounded, context.tr('report.message'), () async => context.push('/report/message/$roomId~${m.id}'), danger: true),
    ]);
  }

  void _openMore() {
    final myRole = ref.read(myRoomMemberProvider(roomId)).valueOrNull?.role ?? RoomRole.listener;
    final staff = ref.read(currentUserProvider)?.role.isStaff ?? false;
    _sheet([
      _Action(Icons.people_alt_rounded, context.tr('room.members'), () async => _openMembers()),
      _Action(Icons.share_rounded, context.tr('common.share'), _share),
      if (myRole == RoomRole.owner) _Action(Icons.edit_rounded, context.tr('room.edit'), () async => _editRoom()),
      if (myRole == RoomRole.owner) _Action(Icons.lock_rounded, context.tr('room.set_password'), () async => _setPassword()),
      if (myRole == RoomRole.owner || staff) _Action(Icons.power_settings_new_rounded, context.tr('room.close'), () async => _closeRoom(), danger: true),
      _Action(Icons.flag_rounded, context.tr('report.room'), () async => context.push('/report/room/$roomId'), danger: true),
    ]);
  }

  void _openMembers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final members = ref.watch(roomMembersProvider(roomId)).valueOrNull ?? const [];
        final sorted = [...members]..sort((a, b) => b.role.index.compareTo(a.role.index));
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.65,
          child: ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (_, i) {
              final m = sorted[i];
              return ListTile(
                leading: UserAvatar(url: m.avatarUrl, name: m.displayName, size: 42, vipLevel: m.vipLevel),
                title: Text(m.displayName),
                subtitle: Text(ctx.tr('role.${m.role.name}')),
                trailing: LevelBadge(level: m.level),
                onTap: () {
                  Navigator.pop(ctx);
                  _showUserActions(m);
                },
              );
            },
          ),
        );
      }),
    );
  }

  Future<void> _editRoom() async {
    final room = ref.read(roomProvider(roomId)).valueOrNull;
    if (room == null) return;
    final name = TextEditingController(text: room.name);
    final desc = TextEditingController(text: room.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('room.edit')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, maxLength: 40, decoration: InputDecoration(hintText: ctx.tr('room.name'))),
          TextField(controller: desc, maxLength: 200, decoration: InputDecoration(hintText: ctx.tr('room.description'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('common.save'))),
        ],
      ),
    );
    if (ok == true && name.text.trim().length >= 2) {
      await _run(() => _repo.updateRoom(roomId, name: name.text.trim(), description: desc.text.trim()));
    }
  }

  Future<void> _setPassword() async {
    final c = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('room.set_password')),
        content: TextField(controller: c, obscureText: true, maxLength: 32, decoration: InputDecoration(hintText: ctx.tr('room.password_clear_hint'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ctx.tr('common.save'))),
        ],
      ),
    );
    if (res == null) return;
    if (res.isNotEmpty && res.length < 4) return _toast(context.tr('room.password_short'));
    await _run(() => _repo.setPassword(roomId, res.isEmpty ? null : res));
  }

  Future<void> _closeRoom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('room.close')),
        content: Text(ctx.tr('room.close_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('room.close'))),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _repo.close(roomId));
      if (mounted) context.pop();
    }
  }

  // -------- build --------
  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(myUidProvider);
    ref.watch(voiceServiceProvider); // keeps the autoDispose engine alive while the screen is open

    ref.listen<AsyncValue<List<Seat>>>(roomSeatsProvider(roomId), (_, next) {
      if (_joined) next.whenData((s) => _syncMic(s, myUid));
    });
    ref.listen<AsyncValue<RoomMember?>>(myRoomMemberProvider(roomId), (_, next) {
      final m = next.valueOrNull;
      if (_joined && m != null && m.left && mounted) {
        _toast(context.tr('room.removed'));
        context.pop();
      }
    });
    ref.listen<AsyncValue<Room?>>(roomProvider(roomId), (_, next) {
      final r = next.valueOrNull;
      if (_joined && r != null && !r.isLive && mounted) {
        _toast(context.tr('room.closed'));
        context.pop();
      }
    });

    if (_joining) {
      return Scaffold(appBar: AppBar(), body: const SkeletonList(count: 5));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: _error!, onRetry: () => _join(widget.password)),
      );
    }

    final room = ref.watch(roomProvider(roomId)).valueOrNull;
    final members = ref.watch(roomMembersProvider(roomId)).valueOrNull ?? const <RoomMember>[];
    final memberMap = {for (final m in members) m.uid: m};
    final me = ref.watch(myRoomMemberProvider(roomId)).valueOrNull;
    final seats = ref.watch(roomSeatsProvider(roomId)).valueOrNull ?? const <Seat>[];
    final mySeat = seats.where((s) => s.userId == myUid).firstOrNull;
    final chatMuted = me?.chatMuted ?? false;
    final listeners = members.where((m) => !seats.any((s) => s.userId == m.uid)).toList();
    final connection = ref.watch(voiceStateProvider).valueOrNull ?? _voice.currentState;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1C1440), AppColors.bg], stops: [0, 0.6]),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _topBar(room, members.length),
                if (_voiceFailed || connection == VoiceConnectionState.failed)
                  MaterialBanner(
                    content: Text(context.tr('room.voice_failed')),
                    actions: [TextButton(onPressed: _connectVoice, child: Text(context.tr('common.retry')))],
                  )
                else if (connection == VoiceConnectionState.reconnecting)
                  Container(width: double.infinity, color: AppColors.gold.withOpacity(0.9), padding: const EdgeInsets.all(4), child: Text(context.tr('room.reconnecting'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: 12))),
                if (room != null) _hostBar(room),
                const SizedBox(height: 4),
                SeatGrid(roomId: roomId, members: memberMap, onSeatTap: _onSeatTap),
                _audienceStrip(listeners),
                const Divider(height: 1),
                Expanded(child: RoomChat(roomId: roomId, onLongPress: _onMessageLongPress, onTapUser: (uid) {
                  final m = memberMap[uid];
                  if (m != null) {
                    _showUserActions(m);
                  } else {
                    context.push('/profile/$uid');
                  }
                })),
                _bottomBar(mySeat, me, chatMuted),
              ],
            ),
          ),
          GiftOverlay(roomId: roomId),
        ],
      ),
    );
  }

  Widget _topBar(Room? room, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30), onPressed: () => context.pop(), tooltip: context.tr('room.exit')),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(room?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text('ID ${roomId.length > 6 ? roomId.substring(0, 6) : roomId} · ${context.tr('room.online', {'n': Fmt.compact(count)})}', style: TextStyle(fontSize: 11.5, color: context.palette.textMuted)),
          ]),
        ),
        IconButton(icon: const Icon(Icons.ios_share_rounded), onPressed: _share, tooltip: context.tr('common.share')),
        IconButton(icon: const Icon(Icons.more_horiz_rounded), onPressed: _openMore, tooltip: context.tr('common.more')),
      ]),
    );
  }

  Widget _hostBar(Room room) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        UserAvatar(url: room.ownerAvatar, name: room.ownerName, size: 34),
        const SizedBox(width: 8),
        Expanded(child: Text(room.ownerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(999)),
          child: Text(context.tr('role.owner'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _audienceStrip(List<RoomMember> listeners) {
    if (listeners.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: listeners.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _showUserActions(listeners[i]),
          child: UserAvatar(url: listeners[i].avatarUrl, name: listeners[i].displayName, size: 44, vipLevel: listeners[i].vipLevel),
        ),
      ),
    );
  }

  Widget _bottomBar(Seat? mySeat, RoomMember? me, bool chatMuted) {
    final seated = mySeat != null;
    final micOn = seated && !_voice.isMuted;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(color: context.palette.surface.withOpacity(0.92), border: Border(top: BorderSide(color: context.palette.border))),
      child: Row(children: [
        Expanded(child: ChatInputBar(controller: _chat, onSend: _sendMessage, enabled: !chatMuted, disabledHint: context.tr('room.chat_muted'))),
        const SizedBox(width: 6),
        _RoundBtn(
          icon: seated ? (micOn ? Icons.mic_rounded : Icons.mic_off_rounded) : Icons.front_hand_rounded,
          color: micOn ? AppColors.success : null,
          tooltip: seated ? context.tr(micOn ? 'room.mute' : 'room.unmute') : context.tr('room.raise_hand'),
          onTap: () {
            if (seated) {
              if (mySeat.micMuted) return _toast(context.tr('room.muted_by_host'));
              _setMic(_voice.isMuted);
            } else {
              _run(() async {
                await _voice.raiseHand();
                _toast(context.tr('room.hand_sent'));
              });
            }
          },
        ),
        _RoundBtn(icon: Icons.card_giftcard_rounded, color: AppColors.gold, tooltip: context.tr('gift.send'), onTap: _openGifts),
        _RoundBtn(icon: Icons.sports_esports_rounded, tooltip: context.tr('nav.games'), onTap: _openGames),
      ]),
    );
  }
}

class _Action {
  final IconData icon;
  final String label;
  final FutureOr<void> Function() run;
  final bool danger;
  _Action(this.icon, this.label, this.run, {this.danger = false});
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap, required this.tooltip, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(icon: Icon(icon, color: color), onPressed: onTap, tooltip: tooltip);
  }
}
