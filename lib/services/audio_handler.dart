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
            '[AudioHandler] Route changed to Speaker — pausing safely and retaining Now Playing.',
          );
          if (onUnsafeRouteDetected != null) {
            await onUnsafeRouteDetected!();
          } else {
            await player.pause();
          }
          publishRemotePlaybackIntent(false);
        }
      });
    });

    // Last line of defense: if playback starts without headphones, immediately stop.
    player.playingStream.listen((playing) async {
      if (!playing) return;
      if (!(await _isHeadphonesConnected())) {
        debugPrint(
          '[AudioHandler] playingStream — no headphones, pausing immediately.',
        );
        if (onUnsafeRouteDetected != null) {
          await onUnsafeRouteDetected!();
        } else {
          await player.pause();
        }
        publishRemotePlaybackIntent(false);
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
      publishRemotePlaybackIntent(true);
      return;
    }
    await player.play();
  }

  @override
  Future<void> pause() async {
    if (onPauseRequested != null) {
      await onPauseRequested!();
      publishRemotePlaybackIntent(false);
      return;
    }
    await player.pause();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  /// Uses the full audio item's real position instead of the sentence-sized
  /// Now Playing metadata. During dictation the metadata duration describes
  /// only the current sentence, while the player holds one complete MP3.
  Future<void> _seekRelativeToPlayer(Duration offset) async {
    var target = player.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    final duration = player.duration;
    if (duration != null && target > duration) target = duration;
    await player.seek(target);
  }

  @override
  Future<void> rewind() =>
      _seekRelativeToPlayer(-AudioService.config.rewindInterval);

  @override
  Future<void> fastForward() =>
      _seekRelativeToPlayer(AudioService.config.fastForwardInterval);

  @override
  Future<void> stop() => player.stop();

  @override
  Future<void> setSpeed(double speed) => player.setSpeed(speed);

  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;
  Future<void> Function()? onPlayRequested;
  Future<void> Function()? onPauseRequested;
  Future<void> Function()? onUnsafeRouteDetected;

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

  /// Claims iOS Now Playing as soon as the user starts a TTS document.
  /// `playing=true` with `loading` is the standard media state for content
  /// that will begin automatically as soon as buffering/synthesis completes.
  void publishPreparingPlayback({
    required String title,
    required String artist,
  }) {
    setPlaybackMetadata(title: title, artist: artist);
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [
          MediaControl.rewind,
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.skipToNext,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.rewind,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.fastForward,
        },
        processingState: AudioProcessingState.loading,
        playing: true,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
      ),
    );
  }

  void publishRemotePlaybackIntent(bool shouldPlay) {
    final state = playbackState.value;
    playbackState.add(
      state.copyWith(
        controls: [
          MediaControl.rewind,
          MediaControl.skipToPrevious,
          shouldPlay ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.fastForward,
        ],
        playing: shouldPlay,
      ),
    );
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.rewind,
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.fastForward,
      },
      androidCompactActionIndices: const [1, 2, 3],
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
