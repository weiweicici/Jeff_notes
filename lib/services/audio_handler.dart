import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();

  MyAudioHandler() {
    // Forward playback events from just_audio to audio_service
    player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  /// iOS: 使用 AVAudioSession.currentRoute.outputs 做实时路由检查（不用缓存设备列表）
  Future<bool> _isHeadphonesConnected() async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final avSession = AVAudioSession();
        final route = await avSession.currentRoute;
        final outputs = route.outputs;

        debugPrint('[AudioHandler] iOS currentRoute outputs: ${outputs.map((o) => o.portType.name).join(", ")}');

        if (outputs.isEmpty) return false;

        for (final output in outputs) {
          final t = output.portType;
          if (t != AVAudioSessionPort.builtInSpeaker &&
              t != AVAudioSessionPort.builtInReceiver) {
            return true;
          }
        }
        return false;
      }

      // Android fallback
      final session = await AudioSession.instance;
      final devices = await session.getDevices();
      if (devices.isEmpty) return false;
      for (final device in devices) {
        // ignore: experimental_member_use
        final type = device.type;
        if (type == AudioDeviceType.wiredHeadset ||
            type == AudioDeviceType.wiredHeadphones ||
            type == AudioDeviceType.bluetoothSco ||
            type == AudioDeviceType.bluetoothA2dp ||
            type == AudioDeviceType.bluetoothLe ||
            type == AudioDeviceType.hearingAid ||
            type == AudioDeviceType.airPlay ||
            type == AudioDeviceType.usbAudio) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[AudioHandler] Headphone check error: $e');
    }
    return false;
  }

  /// Intercepts the lock-screen / Control Center "play" button.
  /// Refuses to play if no headphones are connected.
  @override
  Future<void> play() async {
    if (!(await _isHeadphonesConnected())) {
      debugPrint('[AudioHandler] Lock-screen play() blocked — no headphones connected.');
      return; // Silently block playback without headphones
    }
    await player.play();
  }

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);

  /// Helper to change current media item information (title, artist, duration)
  void setPlaybackMetadata({required String title, required String artist, Duration? duration}) {
    mediaItem.add(MediaItem(
      id: 'tts_audio',
      album: 'Jeff Notes',
      title: title,
      artist: artist,
      duration: duration,
    ));
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
