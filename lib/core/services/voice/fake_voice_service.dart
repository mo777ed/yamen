import 'dart:async';
import 'voice_service.dart';

/// In-memory implementation for tests and UI development without a LiveKit server.
class FakeVoiceService implements VoiceService {
  final _state = StreamController<VoiceConnectionState>.broadcast();
  final _speaking = StreamController<Set<String>>.broadcast();
  final _hands = StreamController<String>.broadcast();
  VoiceConnectionState _current = VoiceConnectionState.disconnected;
  bool _muted = true;
  String? joinedRoom;

  @override
  VoiceConnectionState get currentState => _current;
  @override
  Stream<VoiceConnectionState> get connectionState => _state.stream;
  @override
  Stream<Set<String>> get speakingUserIds => _speaking.stream;
  @override
  Stream<String> get handRaises => _hands.stream;
  @override
  bool get isMuted => _muted;

  void simulateSpeaking(Set<String> ids) => _speaking.add(ids);

  @override
  Future<void> joinRoom(String roomId) async {
    joinedRoom = roomId;
    _current = VoiceConnectionState.connected;
    _state.add(_current);
  }

  @override
  Future<void> leaveRoom() async {
    joinedRoom = null;
    _muted = true;
    _current = VoiceConnectionState.disconnected;
    _state.add(_current);
  }

  @override
  Future<void> mute() async => _muted = true;
  @override
  Future<void> unmute() async => _muted = false;
  @override
  Future<void> raiseHand() async {}
  @override
  Future<void> dispose() async {
    await _state.close();
    await _speaking.close();
    await _hands.close();
  }
}
