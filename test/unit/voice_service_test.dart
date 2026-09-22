import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_chat/core/services/voice/fake_voice_service.dart';
import 'package:yemen_chat/core/services/voice/voice_service.dart';

void main() {
  test('VoiceService contract: join, mute state, leave', () async {
    final VoiceService v = FakeVoiceService();
    expect(v.currentState, VoiceConnectionState.disconnected);
    expect(v.isMuted, isTrue);

    final states = <VoiceConnectionState>[];
    final sub = v.connectionState.listen(states.add);

    await v.joinRoom('room1');
    expect(v.currentState, VoiceConnectionState.connected);

    await v.unmute();
    expect(v.isMuted, isFalse);
    await v.mute();
    expect(v.isMuted, isTrue);

    await v.unmute();
    await v.leaveRoom();
    expect(v.isMuted, isTrue, reason: 'leaving must always mute');
    await Future<void>.delayed(Duration.zero);
    expect(states, [VoiceConnectionState.connected, VoiceConnectionState.disconnected]);
    await sub.cancel();
    await v.dispose();
  });

  test('speaking stream delivers sets of uids', () async {
    final v = FakeVoiceService();
    final future = v.speakingUserIds.first;
    v.simulateSpeaking({'a', 'b'});
    expect(await future, {'a', 'b'});
    await v.dispose();
  });
}
