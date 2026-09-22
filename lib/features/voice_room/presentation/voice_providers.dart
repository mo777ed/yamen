import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/voice/livekit_voice_service.dart';
import '../../../core/services/voice/voice_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../rooms/data/room_repository.dart';

/// One audio engine per open room. To change provider, return another VoiceService here.
final voiceServiceProvider = Provider.autoDispose<VoiceService>((ref) {
  final repo = ref.watch(roomRepositoryProvider);
  final svc = LiveKitVoiceService(credentialsFor: repo.credentialsFor, selfUid: ref.read(myUidProvider));
  ref.onDispose(() {
    svc.dispose();
  });
  return svc;
});

final speakingProvider = StreamProvider.autoDispose<Set<String>>((ref) => ref.watch(voiceServiceProvider).speakingUserIds);
final voiceStateProvider = StreamProvider.autoDispose<VoiceConnectionState>((ref) => ref.watch(voiceServiceProvider).connectionState);
