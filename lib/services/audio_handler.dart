// ignore_for_file: experimental_member_use
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();

  MyAudioHandler() {
    player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    });

    // Instant device route change listener (AirPlay picker / headphone unplugged)
    AudioSession.instance.then((session) {
      session.devicesChangedEventStream.listen((_) async {
        if (player.playing && !(await _isHeadphonesConnected())) {
          debugPrint('[AudioHandler] Route changed to Speaker — stopping player immediately!');
          await player.stop();
        }
      });
    });

    // Last line of defense: if playback starts without headphones, immediately stop.
    player.playingStream.listen((playing) async {
      if (!playing) return;
      if (!(await _isHeadphonesConnected())) {
        debugPrint('[AudioHandler] playingStream — no headphones, stopping immediately.');
        await player.stop();
      }
    });
  }

  /// 持续轮询检查耳机连接（每 200ms 查一次，最多 4 秒）
  Future<bool> _isHeadphonesConnected() async {
    const maxAttempts = 20;
    for (int i = 0; i < maxAttempts; i++) {
      if (await _queryRoute()) return true;
      // 第 10 次强制 iOS 刷新路由（约 2 秒时）
      if (i == 10 && Platform.isIOS) {
        try {
          final avSession = AVAudioSession();
          await avSession.overrideOutputAudioPort(AVAudioSessionPortOverride.none);
        } catch (_) {}
      }
      // 第 15 次再次强制刷新（约 3 秒时）
      if (i == 15 && Platform.isIOS) {
        try {
          final avSession = AVAudioSession();
          await avSession.overrideOutputAudioPort(AVAudioSessionPortOverride.none);
        } catch (_) {}
      }
      if (i < maxAttempts - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    return false;
  }

  Future<bool> _queryRoute() async {
    try {
      // ⚠️ 必须用 allowBluetoothA2DP：.playback + .none 无法把 AirPods 4（H2芯片）路由到 A2DP
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      ));
      await session.setActive(true);

      // 1. 对 iOS/macOS，直接核查系统【当前激活生效的输出端口 currentRoute.outputs】
      if (Platform.isIOS || Platform.isMacOS) {
        // A. 先用插件查（快速路径）
        final avSession = AVAudioSession();
        final route = await avSession.currentRoute;
        final outputs = route.outputs;

        if (outputs.isNotEmpty) {
          for (final output in outputs) {
            final t = output.portType;
            final n = output.portName;
            if (t == AVAudioSessionPort.headphones ||
                t == AVAudioSessionPort.bluetoothA2dp ||
                t == AVAudioSessionPort.bluetoothLe ||
                t == AVAudioSessionPort.bluetoothHfp ||
                t == AVAudioSessionPort.airPlay ||
                t == AVAudioSessionPort.usbAudio ||
                t == AVAudioSessionPort.carAudio ||
                n.contains('AirPods') ||
                n.contains('Bluetooth') ||
                n.contains('耳机')) {
              return true;
            }
          }
        }

        // B. 插件的 currentRoute 只显示扬声器，用 getDevices() 兜底查是否有耳机类设备可用
        try {
          final devices = await session.getDevices(includeInputs: false);
          final hasHeadphoneDevice = devices.any((d) =>
            d.type == AudioDeviceType.wiredHeadset ||
            d.type == AudioDeviceType.wiredHeadphones ||
            d.type == AudioDeviceType.bluetoothSco ||
            d.type == AudioDeviceType.bluetoothA2dp ||
            d.type == AudioDeviceType.bluetoothLe ||
            d.type == AudioDeviceType.hearingAid ||
            d.type == AudioDeviceType.airPlay ||
            d.type == AudioDeviceType.usbAudio ||
            d.type == AudioDeviceType.carAudio ||
            d.name.contains('AirPods') ||
            d.name.contains('Bluetooth') ||
            d.name.contains('耳机'));
          if (hasHeadphoneDevice) {
            await avSession.overrideOutputAudioPort(AVAudioSessionPortOverride.none);
            await Future.delayed(const Duration(milliseconds: 200));
            final retryRoute = await avSession.currentRoute;
            if (retryRoute.outputs.any((o) =>
              o.portType == AVAudioSessionPort.headphones ||
              o.portType == AVAudioSessionPort.bluetoothA2dp ||
              o.portType == AVAudioSessionPort.bluetoothLe ||
              o.portType == AVAudioSessionPort.bluetoothHfp ||
              o.portType == AVAudioSessionPort.airPlay ||
              o.portType == AVAudioSessionPort.usbAudio ||
              o.portType == AVAudioSessionPort.carAudio ||
              o.portName.contains('AirPods') ||
              o.portName.contains('Bluetooth') ||
              o.portName.contains('耳机'))) {
              return true;
            }
          }
        } catch (_) {}
        return false;
      }

      // 2. Android 硬件检查
      // session 已在 iOS 路径前声明，此处复用
      final devices = await session.getDevices();
      for (final device in devices) {
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

  VoidCallback? onSkipNext;
  VoidCallback? onSkipPrevious;

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
    mediaItem.add(MediaItem(
      id: 'tts_audio',
      album: 'Jeff Notes Academic',
      title: title,
      artist: artist,
      duration: duration ?? Duration.zero,
      artUri: artUri,
    ));
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
