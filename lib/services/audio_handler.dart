// ignore_for_file: experimental_member_use
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'route_detector.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();
  final RouteDetector routeDetector;

  MyAudioHandler({RouteDetector? routeDetector})
    : routeDetector = routeDetector ?? const SystemRouteDetector() {
    player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });

    // Instant device route change listener (AirPlay picker / headphone unplugged)
    AudioSession.instance.then((session) {
      session.devicesChangedEventStream.listen((_) async {
        if (player.playing && !(await _isHeadphonesConnected())) {
          debugPrint(
            '[AudioHandler] Route changed to Speaker — stopping player immediately!',
          );
          await player.stop();
        }
      });
    });

    // Last line of defense: if playback starts without headphones, immediately stop.
    player.playingStream.listen((playing) async {
      if (!playing) return;
      if (!(await _isHeadphonesConnected())) {
        debugPrint(
          '[AudioHandler] playingStream — no headphones, stopping immediately.',
        );
        await player.stop();
      }
    });
  }

  /// [Phase 4] 使用结构化 RouteDetector 统一判定输出安全
  Future<bool> _isHeadphonesConnected() async {
    try {
      final decision = await routeDetector.inspectCurrentOutput();
      return decision.isSafe;
    } catch (e) {
      debugPrint('[AudioHandler] Headphone check error: $e');
      return false;
    }
  }

  /// Intercepts the lock-screen / Control Center "play" button.
  /// Refuses to play if no headphones are connected.
  @override
  Future<void> play() async {
    if (!(await _isHeadphonesConnected())) {
      debugPrint(
        '[AudioHandler] Lock-screen play() blocked — no headphones connected.',
      );
      return; // Silently block playback without headphones
    }
    if (onPlayRequested != null) {
      await onPlayRequested!();
      return;
    }
    await player.play();
  }

  @override
  Future<void> pause() async {
    if (onPauseRequested != null) {
      await onPauseRequested!();
      return;
    }
    await player.pause();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);

  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;
  Future<void> Function()? onPlayRequested;
  Future<void> Function()? onPauseRequested;

  @override
  Future<void> skipToNext() async {
    onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onSkipPrevious?.call();
  }

  /// Helper to change current media item information (title, artist, duration, artwork)
  void setPlaybackMetadata({
    required String title,
    required String artist,
    Duration? duration,
    Duration? position,
    bool? isPlaying,
    Uri? artUri,
  }) {
    mediaItem.add(
      MediaItem(
        id: 'tts_audio',
        album: 'Jeff Notes Academic',
        title: title,
        artist: artist,
        duration: duration ?? Duration.zero,
        artUri: artUri,
      ),
    );
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
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
