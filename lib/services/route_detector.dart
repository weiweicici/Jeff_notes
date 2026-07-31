// ignore_for_file: experimental_member_use
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';

/// Structured decision from inspecting current audio output route.
class AudioRouteDecision {
  final bool isSafe;
  final String reason;
  final List<String> outputTypes;

  const AudioRouteDecision({
    required this.isSafe,
    required this.reason,
    required this.outputTypes,
  });

  @override
  String toString() =>
      'AudioRouteDecision(isSafe: $isSafe, reason: "$reason", outputTypes: $outputTypes)';
}

/// Abstract interface for inspecting audio output safety.
abstract interface class RouteDetector {
  Future<AudioRouteDecision> inspectCurrentOutput();
}

/// Production implementation for strict audio route detection (iOS/macOS & Android).
class SystemRouteDetector implements RouteDetector {
  const SystemRouteDetector();

  @override
  Future<AudioRouteDecision> inspectCurrentOutput() async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        return await _inspectIosRoute();
      } else if (Platform.isAndroid) {
        return await _inspectAndroidRoute();
      } else {
        // Desktop / Other platforms fail-closed by default
        return const AudioRouteDecision(
          isSafe: false,
          reason: 'Unsupported platform for headphone verification',
          outputTypes: [],
        );
      }
    } catch (e) {
      debugPrint('[SystemRouteDetector] Exception during route inspection: $e');
      return AudioRouteDecision(
        isSafe: false,
        reason: 'Inspection error (fail-closed): $e',
        outputTypes: const [],
      );
    }
  }

  Future<AudioRouteDecision> _inspectIosRoute() async {
    final avSession = AVAudioSession();
    final route = await avSession.currentRoute;
    final outputs = route.outputs;

    if (outputs.isEmpty) {
      return const AudioRouteDecision(
        isSafe: false,
        reason: 'AVAudioSession currentRoute outputs list is empty',
        outputTypes: [],
      );
    }

    final outputPortNames = outputs.map((o) => o.portType.name).toList();
    return classifyAppleOutputTypes(outputPortNames);
  }

  @visibleForTesting
  static AudioRouteDecision classifyAppleOutputTypes(
    List<String> outputPortNames,
  ) {
    if (outputPortNames.isEmpty) {
      return const AudioRouteDecision(
        isSafe: false,
        reason: 'AVAudioSession currentRoute outputs list is empty',
        outputTypes: [],
      );
    }
    final blocked = {
      AVAudioSessionPort.builtInSpeaker.name,
      AVAudioSessionPort.builtInReceiver.name,
    };

    if (outputPortNames.any(blocked.contains)) {
      return AudioRouteDecision(
        isSafe: false,
        reason:
            'BLOCKED: Built-in speaker/receiver detected in current route outputs',
        outputTypes: outputPortNames,
      );
    }

    // 2. Allow only when current output is an explicit headphone/Bluetooth/AirPlay/USB device
    final allowed = {
      AVAudioSessionPort.headphones.name,
      AVAudioSessionPort.bluetoothA2dp.name,
      AVAudioSessionPort.bluetoothLe.name,
      AVAudioSessionPort.bluetoothHfp.name,
      AVAudioSessionPort.airPlay.name,
      AVAudioSessionPort.usbAudio.name,
      AVAudioSessionPort.carAudio.name,
    };

    if (outputPortNames.any(allowed.contains)) {
      return AudioRouteDecision(
        isSafe: true,
        reason: 'Safe output route active',
        outputTypes: outputPortNames,
      );
    }

    return AudioRouteDecision(
      isSafe: false,
      reason:
          'BLOCKED: Current route output type is not in allowed headphone list',
      outputTypes: outputPortNames,
    );
  }

  Future<AudioRouteDecision> _inspectAndroidRoute() async {
    final session = await AudioSession.instance;
    final devices = await session.getDevices(includeInputs: false);

    if (devices.isEmpty) {
      return const AudioRouteDecision(
        isSafe: false,
        reason: 'Android audio devices list is empty',
        outputTypes: [],
      );
    }

    final deviceTypeNames = devices.map((d) => d.type.name).toList();

    final hasAllowedDevice = devices.any((d) {
      final t = d.type;
      return t == AudioDeviceType.bluetoothA2dp ||
          t == AudioDeviceType.bluetoothSco ||
          t == AudioDeviceType.bluetoothLe ||
          t == AudioDeviceType.hearingAid ||
          t == AudioDeviceType.wiredHeadset ||
          t == AudioDeviceType.wiredHeadphones ||
          t == AudioDeviceType.usbAudio;
    });

    if (hasAllowedDevice) {
      return AudioRouteDecision(
        isSafe: true,
        reason: 'Safe Android audio device active',
        outputTypes: deviceTypeNames,
      );
    }

    return AudioRouteDecision(
      isSafe: false,
      reason: 'BLOCKED: No safe Android headphone device found',
      outputTypes: deviceTypeNames,
    );
  }
}

/// Fake implementation for unit testing route safety matrices without hardware plugins.
class FakeRouteDetector implements RouteDetector {
  AudioRouteDecision decision;

  FakeRouteDetector([
    this.decision = const AudioRouteDecision(
      isSafe: true,
      reason: 'Fake safe route',
      outputTypes: ['bluetoothA2dp'],
    ),
  ]);

  @override
  Future<AudioRouteDecision> inspectCurrentOutput() async {
    return decision;
  }
}
