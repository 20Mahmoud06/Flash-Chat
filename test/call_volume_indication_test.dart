import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flash_chat_app/features/calls/bloc/call_bloc.dart';
import 'package:flash_chat_app/features/calls/bloc/call_event.dart';
import 'package:flash_chat_app/features/calls/bloc/call_state.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

class TestCallBloc extends CallBloc {
  void setStateForTest(CallState newState) {
    emit(newState);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestCallBloc bloc;
  const int amrUid = 1001;

  setUp(() {
    bloc = TestCallBloc();
    bloc.setStateForTest(const CallEngineReady(
      remoteUids: [amrUid],
      speakingUids: {},
    ));
  });

  tearDown(() async {
    await bloc.close();
  });

  group('CallBloc Audio Volume Indication & Speaking Detection', () {
    test('remote speaker lights up when volume exceeds threshold', () async {
      bloc.add(const CallAudioVolumeChanged([
        AudioVolumeInfo(uid: amrUid, volume: 80),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bloc.state, isA<CallEngineReady>());
      final ready = bloc.state as CallEngineReady;
      expect(ready.speakingUids, contains(amrUid));
      expect(ready.speakingUids, isNot(contains(0)));
    });

    test('speaker acoustic echo into mic with vad=0 does NOT mark local user as speaking', () async {
      // 1. Amr is speaking
      bloc.add(const CallAudioVolumeChanged([
        AudioVolumeInfo(uid: amrUid, volume: 80),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 2. Microphone picks up Amr's voice through speaker: volume=45, but VAD=0
      bloc.add(const CallAudioVolumeChanged([
        AudioVolumeInfo(uid: 0, volume: 45, vad: 0),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final ready = bloc.state as CallEngineReady;
      // Local user ("You" = 0) must NOT be speaking!
      expect(ready.speakingUids, isNot(contains(0)));
      // Remote user Amr must STILL be speaking (not wiped out by local callback)
      expect(ready.speakingUids, contains(amrUid));
    });

    test('simultaneous speaking: both local and remote are in speakingUids together', () async {
      // 1. Amr is speaking
      bloc.add(const CallAudioVolumeChanged([
        AudioVolumeInfo(uid: amrUid, volume: 80),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 2. Local user speaks at the same time: vad=1, volume=70
      bloc.add(const CallAudioVolumeChanged([
        AudioVolumeInfo(uid: 0, volume: 70, vad: 1),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final ready = bloc.state as CallEngineReady;
      // Both sides must be marked as speaking!
      expect(ready.speakingUids, contains(0));
      expect(ready.speakingUids, contains(amrUid));
      expect(ready.speakingUids.length, 2);
    });

    test('remote speaker stops while local user continues speaking', () async {
      // Both speaking
      bloc.setStateForTest(const CallEngineReady(
        remoteUids: [amrUid],
        speakingUids: {0, amrUid},
      ));

      // Amr stops (remote callback sends empty list or volume=0)
      bloc.add(const CallAudioVolumeChanged([]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final ready = bloc.state as CallEngineReady;
      expect(ready.speakingUids, contains(0));
      expect(ready.speakingUids, isNot(contains(amrUid)));
    });

    test('local user stops speaking while remote user continues', () async {
      // Both speaking
      bloc.setStateForTest(const CallEngineReady(
        remoteUids: [amrUid],
        speakingUids: {0, amrUid},
      ));

      // Local user goes silent: vad=0, volume=5
      bloc.add(const CallAudioVolumeChanged([
        AudioVolumeInfo(uid: 0, volume: 5, vad: 0),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final ready = bloc.state as CallEngineReady;
      expect(ready.speakingUids, isNot(contains(0)));
      expect(ready.speakingUids, contains(amrUid));
    });

    test('muting local user immediately removes 0 from speakingUids', () async {
      bloc.setStateForTest(const CallEngineReady(
        remoteUids: [amrUid],
        speakingUids: {0, amrUid},
        isMuted: false,
      ));

      bloc.add(const CallToggleMute());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final ready = bloc.state as CallEngineReady;
      expect(ready.isMuted, isTrue);
      expect(ready.speakingUids, isNot(contains(0)));
      expect(ready.speakingUids, contains(amrUid));
    });

    test('muting remote user immediately removes their uid from speakingUids', () async {
      bloc.setStateForTest(const CallEngineReady(
        remoteUids: [amrUid],
        speakingUids: {0, amrUid},
      ));

      bloc.add(const CallRemoteAudioMuted(amrUid, true));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final ready = bloc.state as CallEngineReady;
      expect(ready.mutedRemoteAudioUids, contains(amrUid));
      expect(ready.speakingUids, isNot(contains(amrUid)));
      expect(ready.speakingUids, contains(0));
    });
  });
}
