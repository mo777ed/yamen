import 'dart:async';
import 'dart:convert';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';

import '../../errors/failures.dart';
import 'voice_service.dart';

class VoiceCredentials {
  final String url;
  final String token;
  const VoiceCredentials(this.url, this.token);
}

/// LiveKit implementation. Tokens are minted by the `joinRoom` Cloud Function,
/// so a client can never grant itself publish rights.
class LiveKitVoiceService implements VoiceService {
  LiveKitVoiceService({required this.credentialsFor, required this.selfUid});

  final Future<VoiceCredentials> Function(String roomId) credentialsFor;
  final String selfUid;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  bool _muted = true;
  VoiceConnectionState _state = VoiceConnectionState.disconnected;

  final _stateCtrl = StreamController<VoiceConnectionState>.broadcast();
  final _speakingCtrl = StreamController<Set<String>>.broadcast();
  final _handCtrl = StreamController<String>.broadcast();

  @override
  VoiceConnectionState get currentState => _state;
  @override
  Stream<VoiceConnectionState> get connectionState => _stateCtrl.stream;
  @override
  Stream<Set<String>> get speakingUserIds => _speakingCtrl.stream;
  @override
  Stream<String> get handRaises => _handCtrl.stream;
  @override
  bool get isMuted => _muted;

  void _emit(VoiceConnectionState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  @override
  Future<void> joinRoom(String roomId) async {
    if (_room != null) await leaveRoom();
    _emit(VoiceConnectionState.connecting);
    try {
      final creds = await credentialsFor(roomId);
      final room = lk.Room(
        roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
      );
      _listener = room.createListener()
        ..on<lk.ActiveSpeakersChangedEvent>((e) {
          _speakingCtrl.add(e.speakers.map((p) => p.identity).toSet());
        })
        ..on<lk.RoomReconnectingEvent>((_) => _emit(VoiceConnectionState.reconnecting))
        ..on<lk.RoomReconnectedEvent>((_) => _emit(VoiceConnectionState.connected))
        ..on<lk.RoomDisconnectedEvent>((_) => _emit(VoiceConnectionState.disconnected))
        ..on<lk.DataReceivedEvent>((e) {
          try {
            final msg = jsonDecode(utf8.decode(e.data)) as Map<String, dynamic>;
            if (msg['t'] == 'hand' && e.participant != null) _handCtrl.add(e.participant!.identity);
          } catch (_) {/* ignore malformed data messages */}
        });
      await room.connect(creds.url, creds.token);
      _room = room;
      _muted = true;
      _emit(VoiceConnectionState.connected);
    } catch (e) {
      _emit(VoiceConnectionState.failed);
      throw const Failure('voice-connect', 'تعذّر الاتصال بالصوت، حاول مرة أخرى');
    }
  }

  @override
  Future<void> leaveRoom() async {
    final room = _room;
    _room = null;
    await _listener?.dispose();
    _listener = null;
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
    _muted = true;
    _emit(VoiceConnectionState.disconnected);
  }

  @override
  Future<void> unmute() async {
    final room = _room;
    if (room == null) return;
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw const Failure('mic-permission', 'اسمح للتطبيق باستخدام الميكروفون من إعدادات الجهاز');
    }
    try {
      await room.localParticipant?.setMicrophoneEnabled(true);
      _muted = false;
    } catch (_) {
      throw const Failure('mic-denied', 'لا يمكنك التحدث الآن، اعتلِ مقعداً أولاً');
    }
  }

  @override
  Future<void> mute() async {
    await _room?.localParticipant?.setMicrophoneEnabled(false);
    _muted = true;
  }

  @override
  Future<void> raiseHand() async {
    final payload = utf8.encode(jsonEncode({'t': 'hand', 'uid': selfUid}));
    await _room?.localParticipant?.publishData(payload, reliable: true);
  }

  @override
  Future<void> dispose() async {
    await leaveRoom();
    await _stateCtrl.close();
    await _speakingCtrl.close();
    await _handCtrl.close();
  }
}
