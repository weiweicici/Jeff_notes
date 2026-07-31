import 'package:record/record.dart';

abstract interface class AudioRecorderAdapter {
  Future<bool> hasPermission();
  Future<void> start(RecordConfig config, {required String path});
  Future<String?> stop();
  Future<void> dispose();
}

class RecordAudioRecorderAdapter implements AudioRecorderAdapter {
  RecordAudioRecorderAdapter([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(RecordConfig config, {required String path}) =>
      _recorder.start(config, path: path);

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

class FakeAudioRecorderAdapter implements AudioRecorderAdapter {
  bool permissionGranted;
  String? stopPath;
  bool isRecording = false;
  bool isDisposed = false;
  final List<String> startedPaths = [];

  FakeAudioRecorderAdapter({this.permissionGranted = true, this.stopPath});

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    isRecording = true;
    startedPaths.add(path);
  }

  @override
  Future<String?> stop() async {
    isRecording = false;
    return stopPath;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    isRecording = false;
  }
}
