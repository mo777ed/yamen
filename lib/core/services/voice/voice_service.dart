import 'dart:async';

enum VoiceConnectionState { disconnected, connecting, connected, reconnecting, failed }

/// The only audio API the UI is allowed to touch. Swap the provider
/// (LiveKit, Agora, ZEGO...) by writing a new implementation and changing one provider.
abstract class VoiceService {
  VoiceConnectionState get currentState;
  Stream<VoiceConnectionState> get connectionState;

  /// uids of participants currently speaking (drives the speaking animation).
  Stream<Set<String>> get speakingUserIds;

  /// uids of listeners who asked to speak (see [raiseHand]).
  Stream<String> get handRaises;

  bool get isMuted;

  Future<void> joinRoom(String roomId);
  Future<void> leaveRoom();
  Future<void> mute();
  Future<void> unmute();
  Future<void> raiseHand();
  Future<void> dispose();
}
