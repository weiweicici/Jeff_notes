// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wakelock_service.dart';
import 'route_detector.dart';
import 'edge_tts_auth.dart';
import 'diagnostic_log_service.dart';
import '../main.dart';

enum ActiveAudioType { none, chinese, english, recorded }

enum ChineseTtsEngine {
  iosNative, // 方案一：iOS 系统原生中文 (0秒秒开 · 0元0Token)
  edgeNeural, // 方案二：微软 Edge 晓晓神经网络女声 (0元免费 · 播音级美音)
}

enum EnglishTtsEngine {
  iosNative,
  edgeNeural, // 独家保留：微软 Edge / Bella 高清神经网络播音女声
}

class EdgeSentenceBoundary {
  const EdgeSentenceBoundary({
    required this.text,
    required this.offset,
    required this.duration,
  });

  final String text;
  final Duration offset;
  final Duration duration;

  Map<String, Object> toJson() => {
    'text': text,
    'offset_us': offset.inMicroseconds,
    'duration_us': duration.inMicroseconds,
  };

  factory EdgeSentenceBoundary.fromJson(Map<String, dynamic> json) =>
      EdgeSentenceBoundary(
        text: json['text']?.toString() ?? '',
        offset: Duration(microseconds: (json['offset_us'] as num).toInt()),
        duration: Duration(microseconds: (json['duration_us'] as num).toInt()),
      );
}

/// Keeps a finite dictation repeat parked while the user pauses playback.
/// just_audio completes `play()` both on natural completion and on pause, so
/// the dictation loop needs this separate signal to distinguish the two.
@visibleForTesting
class DictationPauseGate {
  bool _isPaused = false;
  Completer<void>? _resumeCompleter;

  bool get isPaused => _isPaused;

  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    _resumeCompleter = Completer<void>();
  }

  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    final completer = _resumeCompleter;
    _resumeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void cancel() => resume();

  Future<void> waitWhilePaused() async {
    while (_isPaused) {
      final resumeFuture = _resumeCompleter?.future;
      if (resumeFuture == null) return;
      await resumeFuture;
    }
  }
}

class _EdgeSynthesisWithBoundaries {
  const _EdgeSynthesisWithBoundaries({
    required this.audioBytes,
    required this.boundaries,
  });

  final List<int> audioBytes;
  final List<EdgeSentenceBoundary> boundaries;
}

class TtsService extends ChangeNotifier {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;

  RouteDetector routeDetector = const SystemRouteDetector();

  AudioPlayer get _audioPlayer => globalAudioHandler.player;
  final FlutterTts _flutterTts = FlutterTts();

  bool _isInitialized = false;
  ActiveAudioType _currentAudioType = ActiveAudioType.none;
  bool _playbackBlockedForRecording = false;

  ActiveAudioType get currentAudioType => _currentAudioType;
  bool get playbackBlockedForRecording => _playbackBlockedForRecording;

  void _ensurePlaybackAllowed() {
    if (_playbackBlockedForRecording) {
      throw StateError('PlaybackBlockedDuringRecording');
    }
  }

  // ── 中文本地原生 TTS 状态 ──────────────────────────
  ChineseTtsEngine _chineseEngine = ChineseTtsEngine.edgeNeural;
  ChineseTtsEngine get chineseEngine => _chineseEngine;

  Future<void> setChineseEngine(ChineseTtsEngine engine) async {
    _chineseEngine = engine;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chinese_tts_engine', engine.name);
    notifyListeners();
  }

  bool _isChineseSynthesizing = false;
  double _chineseSpeed = 1.2;
  bool _isChineseNativePlaying = false;
  String? _lastNativeChineseText;
  Duration _chineseNativePosition = Duration.zero;
  Duration _chineseNativeDuration = Duration.zero;
  Timer? _chineseNativeTimer;

  bool get isChineseSynthesizing => _isChineseSynthesizing;
  bool get isChinesePlaying =>
      (_audioPlayer.playing && _currentAudioType == ActiveAudioType.chinese) ||
      (_isChineseNativePlaying && _currentAudioType == ActiveAudioType.chinese);
  double get chineseSpeed => _chineseSpeed;

  Stream<Duration> get chinesePositionStream => _audioPlayer.positionStream;
  Stream<Duration?> get chineseDurationStream => _audioPlayer.durationStream;

  // ── 英文 AI 拟真音色 TTS 状态 ─────────────────────
  EnglishTtsEngine _englishEngine = EnglishTtsEngine.edgeNeural;
  EnglishTtsEngine get englishEngine => _englishEngine;

  Future<void> setEnglishEngine(EnglishTtsEngine engine) async {
    _englishEngine = engine;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('english_tts_engine', engine.name);
    notifyListeners();
  }

  bool _isEnglishSynthesizing = false;
  bool _isNativeEnglishPlaying = false;
  double _englishSpeed = 0.6;
  bool _isLoopMode = true; // 默认：无限重复播放
  bool _isEnglishDictationPlaying = false;
  int _dictationSentenceIndex = 0;
  int _dictationSentenceCount = 0;
  int _dictationRepeatIndex = 0;
  int _dictationRepeatCount = 3;
  int _dictationCycleIndex = 0;
  int _dictationRunId = 0;
  int _dictationExtraReplayRequests = 0;
  int _dictationSentenceNavigationRequest = 0;
  Completer<void>? _dictationCommandSignal;
  bool _isEnglishDictationExtraReplay = false;
  DateTime? _dictationMediaPauseAt;
  final DictationPauseGate _dictationPauseGate = DictationPauseGate();
  bool get isLoopMode => _isLoopMode;
  bool get isEnglishSynthesizing => _isEnglishSynthesizing;
  bool get isEnglishDictationPlaying => _isEnglishDictationPlaying;
  int get dictationSentenceIndex => _dictationSentenceIndex;
  int get dictationSentenceCount => _dictationSentenceCount;
  int get dictationRepeatIndex => _dictationRepeatIndex;
  int get dictationRepeatCount => _dictationRepeatCount;
  int get dictationCycleIndex => _dictationCycleIndex;
  bool get isEnglishDictationPaused => _dictationPauseGate.isPaused;
  bool get isEnglishDictationExtraReplay => _isEnglishDictationExtraReplay;
  bool get isEnglishPlaying =>
      (_audioPlayer.playing && _currentAudioType == ActiveAudioType.english) ||
      (_isNativeEnglishPlaying && _currentAudioType == ActiveAudioType.english);
  bool get isRecordedPlaying =>
      _audioPlayer.playing && _currentAudioType == ActiveAudioType.recorded;
  double get englishSpeed => _englishSpeed;

  Future<void> setLoopMode(bool enabled) async {
    if (_isLoopMode == enabled) {
      await _applyAudioPlayerLoopMode();
      return;
    }
    _isLoopMode = enabled;
    await _applyAudioPlayerLoopMode();
    notifyListeners();
  }

  Future<void> toggleLoopMode() => setLoopMode(!_isLoopMode);

  Future<void> _applyAudioPlayerLoopMode() => _audioPlayer.setLoopMode(
    _isLoopMode && !_isEnglishDictationPlaying ? LoopMode.one : LoopMode.off,
  );

  @visibleForTesting
  static bool shouldContinueEnglishDictation({
    required bool loopEnabled,
    required int runId,
    required int currentRunId,
  }) => loopEnabled && runId == currentRunId;

  /// Returns a zero-based sentence index. [sentenceCount] is also a valid
  /// result for "next" on the last sentence and means finish this round.
  @visibleForTesting
  static int resolveEnglishDictationSentenceNavigation({
    required int currentIndex,
    required int sentenceCount,
    required int direction,
  }) {
    if (sentenceCount <= 0) return 0;
    if (direction < 0) return max(0, currentIndex - 1);
    if (direction > 0) return min(sentenceCount, currentIndex + 1);
    return currentIndex.clamp(0, sentenceCount - 1);
  }

  @visibleForTesting
  static bool isRapidDictationMediaReplay(
    DateTime pauseAt,
    DateTime playAt, {
    Duration window = const Duration(milliseconds: 700),
  }) {
    final elapsed = playAt.difference(pauseAt);
    return !elapsed.isNegative && elapsed <= window;
  }

  /// Splits simple English prose into dictation-sized sentences. Generated
  /// essays intentionally use short sentences, so this keeps the listening
  /// unit predictable without trying to infer paragraph-level pauses.
  static List<String> splitEnglishSentences(String text) {
    final clean = text
        .replaceAll(RegExp(r'==|[*_~`#>|\[\]\(\)]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return const [];

    final sentences = clean
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.contains(RegExp(r'[A-Za-z]')))
        .toList();
    return sentences.isEmpty ? [clean] : sentences;
  }

  static Duration estimateEnglishDictationDuration(
    String text, {
    required int repeatCount,
    required Duration pauseBetweenSentences,
    required double speed,
  }) {
    final sentences = splitEnglishSentences(text);
    final words = RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)?").allMatches(text).length;
    final wordsPerMinute = 150 * speed.clamp(0.4, 2.0);
    final speechSeconds = words == 0 ? 0 : words / wordsPerMinute * 60;
    final pauses = sentences.length > 1
        ? pauseBetweenSentences.inSeconds * (sentences.length - 1)
        : 0;
    return Duration(seconds: (speechSeconds * repeatCount + pauses).round());
  }

  Stream<Duration> get englishPositionStream => _audioPlayer.positionStream;
  Stream<Duration?> get englishDurationStream => _audioPlayer.durationStream;
  Duration? get currentDuration =>
      (_isChineseNativePlaying && _currentAudioType == ActiveAudioType.chinese)
      ? _chineseNativeDuration
      : _audioPlayer.duration;
  Duration get currentPosition =>
      (_isChineseNativePlaying && _currentAudioType == ActiveAudioType.chinese)
      ? _chineseNativePosition
      : _audioPlayer.position;

  bool get isPlaying =>
      _audioPlayer.playing ||
      _isChineseNativePlaying ||
      _isNativeEnglishPlaying;
  bool get isSynthesizing => _isChineseSynthesizing || _isEnglishSynthesizing;

  TtsService._internal();

  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Configure AudioSession — category must be playback for TTS audio
    //    so iOS routes directly to headphones and NEVER defaults/forces speaker.
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ),
    );
    await session.setActive(true);

    // 2. Init FlutterTts for Chinese local playback
    await _flutterTts.setSharedInstance(true);
    await _flutterTts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [],
      IosTextToSpeechAudioMode.spokenAudio,
    );
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setLanguage("zh-CN");

    _flutterTts.setErrorHandler((msg) {
      debugPrint("Chinese Local TTS Error: $msg");
      _finishNativePlayback();
      notifyListeners();
    });
    _flutterTts.setCancelHandler(_finishNativePlayback);

    // 注意：flutter_tts 的 setProgressHandler 在 iOS 上不可靠（不持续触发），
    // 改用 Timer.periodic 计时器在 speakChinese 中模拟进度。

    // 3. Listen to just_audio state changes (for English AI player)
    _audioPlayer.playerStateStream.listen((_) {
      notifyListeners();
    });

    // 4. Any device/output change must be validated against the actual active
    // route. Control Center can select Speaker without reporting the previous
    // headphone as removed.
    _devicesSubscription = session.devicesChangedEventStream.listen((_) async {
      if (!shouldKeepHeadphoneMonitorAlive(
        isPlaying: isPlaying,
        isDictationActive: _isEnglishDictationPlaying,
      )) {
        return;
      }
      await _enforceSafeOutputRoute('device_change');
    });

    _isInitialized = true;
  }

  /// 生成锁屏标题：取文本前 maxChars 个字符，换行符替换为空格
  String _formatLockscreenTitle(String text, {int maxChars = 100}) {
    final cleaned = text
        .replaceAll(RegExp(r'==|[*_~`#>|\[\]\(\)-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length <= maxChars) return cleaned;
    return '${cleaned.substring(0, maxChars)}…';
  }

  /// 恢复并激活 iOS/Android 为 Category.playback 纯播放模式（消除录音残留的 defaultToSpeaker 模式）
  Future<void> ensurePlaybackSession() async {
    _ensurePlaybackAllowed();
    try {
      final session = await AudioSession.instance;
      _ensurePlaybackAllowed();
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
      _ensurePlaybackAllowed();
      await session.setActive(true);
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [],
        IosTextToSpeechAudioMode.spokenAudio,
      );
      // 强制 iOS 重新评估路由，确保耳机被选中而非 stuck 在扬声器
      if (Platform.isIOS) {
        try {
          final avSession = AVAudioSession();
          await avSession.overrideOutputAudioPort(
            AVAudioSessionPortOverride.none,
          );
        } catch (_) {}
      }
    } catch (e) {
      if (e is StateError && e.message == 'PlaybackBlockedDuringRecording') {
        rethrow;
      }
      unawaited(
        DiagnosticLogService.instance.record(
          'tts',
          'playback_session_restore_failed',
          fields: {'errorType': e.runtimeType},
        ),
      );
      debugPrint('[TtsService] ensurePlaybackSession error: $e');
    }
  }

  StreamSubscription? _devicesSubscription;
  Timer? _headphoneMonitor;
  bool _isCheckingHeadphones = false; // [BUG-03 Fix] 防止并发耳机检测堆积
  String lastRouteDebug = '';

  @visibleForTesting
  static bool shouldKeepHeadphoneMonitorAlive({
    required bool isPlaying,
    required bool isDictationActive,
  }) => isPlaying || isDictationActive;

  Future<void> _enforceSafeOutputRoute(String source) async {
    if (_isCheckingHeadphones) return;
    _isCheckingHeadphones = true;
    try {
      final decision = await routeDetector.inspectCurrentOutput();
      lastRouteDebug = decision.isSafe ? '' : decision.reason;
      if (decision.isSafe) return;
      unawaited(
        DiagnosticLogService.instance.record(
          'tts',
          'route_lost_during_playback',
          fields: {
            'source': source,
            'outputs': decision.outputTypes.join(','),
            'reason': decision.reason,
          },
        ),
      );
      debugPrint(
        '[TtsService] Unsafe output route detected ($source): '
        '${decision.outputTypes}. Stopping TTS immediately.',
      );
      await stopAll();
    } finally {
      _isCheckingHeadphones = false;
    }
  }

  void _startHeadphoneMonitor() {
    _stopHeadphoneMonitor();
    // Keep polling throughout an active dictation, including finite-clip
    // completion, sentence gaps and a user pause. Those states temporarily
    // make AudioPlayer.playing false but must not disable route protection.
    _headphoneMonitor = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      if (!shouldKeepHeadphoneMonitorAlive(
        isPlaying: isPlaying,
        isDictationActive: _isEnglishDictationPlaying,
      )) {
        _stopHeadphoneMonitor();
        return;
      }
      await _enforceSafeOutputRoute('continuous_monitor');
    });
  }

  void _stopHeadphoneMonitor() {
    _headphoneMonitor?.cancel();
    _headphoneMonitor = null;
  }

  /// [Phase 4 Rule 1 & 2] 统一 TTS 发声安全门：恢复 pure playback session 并在路由不安全时硬切断播放
  Future<bool> prepareSafePlayback({required String playbackSource}) async {
    if (_playbackBlockedForRecording) {
      unawaited(
        DiagnosticLogService.instance.record(
          'tts',
          'playback_blocked_recording',
          fields: {'source': playbackSource},
        ),
      );
      return false;
    }
    await ensurePlaybackSession();
    final decision = await routeDetector.inspectCurrentOutput();
    unawaited(
      DiagnosticLogService.instance.record(
        'tts',
        decision.isSafe ? 'route_allowed' : 'route_blocked',
        fields: {
          'source': playbackSource,
          'outputs': decision.outputTypes.join(','),
          'reason': decision.reason,
        },
      ),
    );
    if (!decision.isSafe) {
      lastRouteDebug = decision.reason;
      debugPrint(
        '[TtsService Safety Gate] BLOCKED playback ($playbackSource): ${decision.reason}',
      );
      await stopAll();
      return false;
    }
    lastRouteDebug = '';
    return true;
  }

  Future<void> _playAudioSafely(String playbackSource) async {
    if (!await prepareSafePlayback(playbackSource: playbackSource)) {
      throw StateError('Unsafe audio route: $lastRouteDebug');
    }
    await _audioPlayer.play();
  }

  /// Plays the already-loaded full audio file until an absolute position.
  ///
  /// Do not implement dictation sentences with `AudioPlayer.setClip`: on iOS
  /// every clip change reloads the native AVPlayerItem. Repeating that for
  /// every sentence can leave just_audio's KVO registrations out of sync and
  /// crash the process the next time the native player is disposed. Seeking
  /// within one loaded item keeps the same AVPlayerItem for the whole lesson.
  Future<void> _playAudioUntilSafely(
    String playbackSource, {
    required Duration end,
  }) async {
    if (!await prepareSafePlayback(playbackSource: playbackSource)) {
      throw StateError('Unsafe audio route: $lastRouteDebug');
    }

    if (_audioPlayer.position >= end) {
      await _audioPlayer.pause();
      return;
    }

    final reachedEnd = Completer<void>();
    final positionSubscription = _audioPlayer
        .createPositionStream(
          minPeriod: const Duration(milliseconds: 20),
          maxPeriod: const Duration(milliseconds: 40),
        )
        .listen((position) {
          if (position >= end && !reachedEnd.isCompleted) {
            reachedEnd.complete();
          }
        });

    final playFuture = _audioPlayer.play();
    try {
      await Future.any<void>([playFuture, reachedEnd.future]);
      if (reachedEnd.isCompleted) {
        await _audioPlayer.pause();
        await playFuture;
      }
    } finally {
      await positionSubscription.cancel();
    }
  }

  Future<void> _speakNativeSafely(
    String text, {
    required String playbackSource,
  }) async {
    if (!await prepareSafePlayback(playbackSource: playbackSource)) {
      throw StateError('Unsafe audio route: $lastRouteDebug');
    }
    _isNativeEnglishPlaying = _currentAudioType == ActiveAudioType.english;
    _isChineseNativePlaying = _currentAudioType == ActiveAudioType.chinese;
    if (_isChineseNativePlaying) _lastNativeChineseText = text;
    _flutterTts.setCompletionHandler(() {
      unawaited(
        _handleNativePlaybackCompletion(text, playbackSource: playbackSource),
      );
    });
    _flutterTts.setCancelHandler(_finishNativePlayback);
    await _flutterTts.speak(text);
  }

  Future<void> _handleNativePlaybackCompletion(
    String text, {
    required String playbackSource,
  }) async {
    final channelIsStillActive =
        (_currentAudioType == ActiveAudioType.chinese &&
            _isChineseNativePlaying) ||
        (_currentAudioType == ActiveAudioType.english &&
            _isNativeEnglishPlaying);
    if (!shouldRepeatNativePlayback(
      loopEnabled: _isLoopMode,
      playbackBlocked: _playbackBlockedForRecording,
      channelIsStillActive: channelIsStillActive,
    )) {
      _finishNativePlayback();
      return;
    }

    if (!await prepareSafePlayback(playbackSource: '$playbackSource loop')) {
      _finishNativePlayback();
      return;
    }

    if (_currentAudioType == ActiveAudioType.chinese) {
      _chineseNativePosition = Duration.zero;
      _startChineseNativeProgressTimer();
    }
    WakelockService.enable();
    notifyListeners();
    await _flutterTts.speak(text);
  }

  @visibleForTesting
  static bool shouldRepeatNativePlayback({
    required bool loopEnabled,
    required bool playbackBlocked,
    required bool channelIsStillActive,
  }) => loopEnabled && !playbackBlocked && channelIsStillActive;

  void _startChineseNativeProgressTimer() {
    _chineseNativeTimer?.cancel();
    _chineseNativeTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) {
      if (!_isChineseNativePlaying) {
        timer.cancel();
        return;
      }
      _chineseNativePosition += const Duration(milliseconds: 200);
      if (_chineseNativePosition >= _chineseNativeDuration) {
        _chineseNativePosition = _chineseNativeDuration;
        timer.cancel();
      }
      notifyListeners();
    });
  }

  void _finishNativePlayback() {
    if (_isChineseNativePlaying) {
      _chineseNativePosition = _chineseNativeDuration;
    }
    _isChineseNativePlaying = false;
    _isNativeEnglishPlaying = false;
    _chineseNativeTimer?.cancel();
    _stopHeadphoneMonitor();
    WakelockService.disable();
    notifyListeners();
  }

  /// 检查耳机/蓝牙输出是否连接（不再 4 秒多轮轮询，使用单次硬硬核路由检查）
  Future<bool> isHeadphonesConnected() async {
    final decision = await routeDetector.inspectCurrentOutput();
    lastRouteDebug = decision.isSafe ? '' : decision.reason;
    return decision.isSafe;
  }

  String _sanitizeMarkdown(String markdown) {
    String text = markdown;
    text = text.replaceAll(RegExp(r'[#\*_~=]'), '');
    text = text.replaceAll(RegExp(r'^\s*[\-\*\+]\s+', multiLine: true), '，');
    text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '，');
    text = text.replaceAll(RegExp(r'^-{3,}\s*$', multiLine: true), '');
    text = text.replaceAll(RegExp(r'[\|\-\+]+'), ' ');
    text = text.replaceAllMapped(
      RegExp(r'\[(.*?)\]\(.*?\)'),
      (match) => match[1] ?? '',
    );
    final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(markdown);
    text = text.replaceAll(RegExp(r'\n+'), hasChinese ? '，' : ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }

  List<String> _splitTextIntoChunks(String text, {int maxChunkSize = 800}) {
    if (text.length <= maxChunkSize) return [text];
    final chunks = <String>[];
    final regExp = RegExp(r'([^.!?;\n]+[.!?;\n]?)');
    final matches = regExp.allMatches(text);

    StringBuffer currentChunk = StringBuffer();
    for (final match in matches) {
      final sentence = match.group(0) ?? '';
      if (currentChunk.length + sentence.length > maxChunkSize) {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk.toString().trim());
          currentChunk.clear();
        }
        if (sentence.length > maxChunkSize) {
          int start = 0;
          while (start < sentence.length) {
            int end = (start + maxChunkSize < sentence.length)
                ? start + maxChunkSize
                : sentence.length;
            chunks.add(sentence.substring(start, end).trim());
            start = end;
          }
        } else {
          currentChunk.write(sentence);
        }
      } else {
        currentChunk.write(sentence);
      }
    }
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString().trim());
    }
    return chunks.where((c) => c.isNotEmpty).toList();
  }

  /// 后台静默预生成与下载英文神经网络音频（0 秒阻塞，全自动提前就绪）
  Future<void> prefetchEnglish(
    String text, {
    String? geminiKey,
    String? siliconFlowKey,
  }) async {
    final clean = _sanitizeMarkdown(text);
    if (clean.isEmpty) return;

    final textHash = md5.convert(utf8.encode(clean)).toString();
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory("${docsDir.path}/tts_cache");
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final cachedFile = File("${cacheDir.path}/english_neural_$textHash.mp3");

    // 若已经预载过，直接跳过
    if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
      debugPrint(
        "[TtsPrefetch] English audio already cached: ${cachedFile.path}",
      );
      return;
    }

    try {
      debugPrint(
        "[TtsPrefetch] Silently pre-synthesizing English audio in background...",
      );
      List<int>? synthesizedBytes;

      final effectiveSiliconKey = (siliconFlowKey ?? '').trim();
      final effectiveGeminiKey = (geminiKey ?? '').trim();

      if (effectiveSiliconKey.isNotEmpty) {
        try {
          synthesizedBytes = await _synthesizeWithSiliconFlow(
            clean,
            effectiveSiliconKey,
            textHash,
          );
        } catch (e) {
          debugPrint("[TtsPrefetch] SiliconFlow prefetch error: $e");
        }
      }

      if ((synthesizedBytes == null || synthesizedBytes.isEmpty) &&
          effectiveGeminiKey.isNotEmpty) {
        try {
          synthesizedBytes = await _synthesizeWithGemini(
            clean,
            effectiveGeminiKey,
          );
        } catch (e) {
          debugPrint("[TtsPrefetch] Gemini prefetch error: $e");
        }
      }

      if (synthesizedBytes == null || synthesizedBytes.isEmpty) {
        synthesizedBytes = await _synthesizeWithEdgeNeural(clean);
      }

      if (synthesizedBytes.isNotEmpty) {
        await cachedFile.writeAsBytes(synthesizedBytes);
        debugPrint(
          "[TtsPrefetch] English audio successfully pre-fetched to disk cache!",
        );
      }
    } catch (e) {
      debugPrint("[TtsPrefetch] Background prefetch failed: $e");
    }
  }

  Future<void> _handleDictationMediaPause() async {
    if (_isEnglishDictationPlaying) {
      _dictationMediaPauseAt = DateTime.now();
    }
    await pauseEnglish();
  }

  Future<void> _handleDictationMediaPlay() async {
    final pauseAt = _dictationMediaPauseAt;
    final now = DateTime.now();
    if (_isEnglishDictationPlaying &&
        _dictationPauseGate.isPaused &&
        pauseAt != null &&
        isRapidDictationMediaReplay(pauseAt, now)) {
      _requestExtraEnglishDictationReplay();
      return;
    }
    _dictationMediaPauseAt = null;
    await playEnglish();
  }

  void _requestExtraEnglishDictationReplay() {
    if (!_isEnglishDictationPlaying) return;
    _dictationExtraReplayRequests++;
    _dictationMediaPauseAt = null;
    _dictationPauseGate.resume();
    _wakeDictationCommandLoop();
    // Interrupt the current finite play() future so the dictation state
    // machine can restart this clip as an uncounted replay.
    unawaited(_audioPlayer.pause());
    notifyListeners();
  }

  void requestPreviousEnglishDictationSentence() {
    _requestEnglishDictationSentenceNavigation(-1);
  }

  void requestNextEnglishDictationSentence() {
    _requestEnglishDictationSentenceNavigation(1);
  }

  void _requestEnglishDictationSentenceNavigation(int direction) {
    if (!_isEnglishDictationPlaying || direction == 0) return;
    _dictationSentenceNavigationRequest = direction.sign;
    _dictationExtraReplayRequests = 0;
    _isEnglishDictationExtraReplay = false;
    _dictationMediaPauseAt = null;
    _dictationPauseGate.resume();
    _wakeDictationCommandLoop();
    // A remote next/previous command must take effect immediately, including
    // in the middle of one of the three planned repeats.
    unawaited(_audioPlayer.pause());
    notifyListeners();
  }

  void _wakeDictationCommandLoop() {
    final signal = _dictationCommandSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  Future<void> _waitForDictationCommandOrGap(Duration duration) async {
    if (_dictationSentenceNavigationRequest != 0 ||
        _dictationExtraReplayRequests > 0) {
      return;
    }
    final signal = Completer<void>();
    _dictationCommandSignal = signal;
    try {
      await Future.any<void>([Future<void>.delayed(duration), signal.future]);
    } finally {
      if (identical(_dictationCommandSignal, signal)) {
        _dictationCommandSignal = null;
      }
    }
  }

  void _setEnglishDictationMetadata({
    required Duration duration,
    required int repeatCount,
    required bool isExtraReplay,
  }) {
    globalAudioHandler.setPlaybackMetadata(
      title:
          '听写第 $_dictationCycleIndex 轮：第 $_dictationSentenceIndex / $_dictationSentenceCount 句',
      artist: isExtraReplay
          ? '额外重播 · 不计入 $_dictationRepeatIndex / $repeatCount 次'
          : '第 $_dictationRepeatIndex / $repeatCount 次 · 微软 Jenny',
      duration: duration,
    );
  }

  Future<bool> _playPendingExtraDictationReplays({
    required int runId,
    required Duration clipStart,
    required Duration clipEnd,
    required Duration clipDuration,
    required int repeatCount,
  }) async {
    while (_dictationExtraReplayRequests > 0 &&
        _dictationSentenceNavigationRequest == 0 &&
        runId == _dictationRunId) {
      _dictationExtraReplayRequests--;
      _isEnglishDictationExtraReplay = true;
      _setEnglishDictationMetadata(
        duration: clipDuration,
        repeatCount: repeatCount,
        isExtraReplay: true,
      );
      await _audioPlayer.seek(clipStart);
      notifyListeners();

      while (runId == _dictationRunId) {
        await _dictationPauseGate.waitWhilePaused();
        if (runId != _dictationRunId) return false;
        if (_dictationSentenceNavigationRequest != 0) break;
        await _playAudioUntilSafely(
          'English dictation extra replay',
          end: clipEnd,
        );
        if (_dictationSentenceNavigationRequest != 0) break;
        if (_dictationPauseGate.isPaused) continue;
        if (_dictationExtraReplayRequests > 0) break;
        await _audioPlayer.pause();
        break;
      }
    }

    _isEnglishDictationExtraReplay = false;
    notifyListeners();
    return runId == _dictationRunId;
  }

  /// Synthesizes one complete Edge MP3 plus sentence offsets, then seeks and
  /// pauses within that single loaded file for dictation practice.
  Future<void> startEnglishDictation(
    String text, {
    String? geminiKey,
    String? siliconFlowKey,
    int repeatCount = 3,
    Duration pauseBetweenSentences = const Duration(seconds: 3),
  }) async {
    final sentences = splitEnglishSentences(_sanitizeMarkdown(text));
    if (sentences.isEmpty) return;

    await init();
    await stopAll();
    _ensurePlaybackAllowed();
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected())) {
      throw Exception('NoHeadphones | $lastRouteDebug');
    }

    final runId = ++_dictationRunId;
    final safeRepeatCount = repeatCount.clamp(1, 5).toInt();
    _isEnglishSynthesizing = true;
    _isEnglishDictationPlaying = true;
    _dictationSentenceCount = sentences.length;
    _dictationSentenceIndex = 0;
    _dictationRepeatIndex = 0;
    _dictationRepeatCount = safeRepeatCount;
    _dictationCycleIndex = 0;
    _dictationExtraReplayRequests = 0;
    _dictationSentenceNavigationRequest = 0;
    _dictationCommandSignal = null;
    _isEnglishDictationExtraReplay = false;
    _dictationMediaPauseAt = null;
    _dictationPauseGate.cancel();
    globalAudioHandler.onPlayRequested = _handleDictationMediaPlay;
    globalAudioHandler.onPauseRequested = _handleDictationMediaPause;
    // OpenRun Pro: double-click sends nextTrack; triple-click sends
    // previousTrack. Map those native media commands to dictation actions.
    globalAudioHandler.onSkipNext = requestNextEnglishDictationSentence;
    globalAudioHandler.onSkipPrevious = _requestExtraEnglishDictationReplay;
    notifyListeners();

    var dictationAudioLoaded = false;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${docsDir.path}/tts_cache');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
      final cleanText = _sanitizeMarkdown(text);
      final textHash = md5.convert(utf8.encode(cleanText)).toString();
      final audioFile = File(
        '${cacheDir.path}/english_dictation_$textHash.mp3',
      );
      final boundaryFile = File(
        '${cacheDir.path}/english_dictation_$textHash.json',
      );
      List<EdgeSentenceBoundary> boundaries = [];

      if (await audioFile.exists() &&
          await audioFile.length() > 0 &&
          await boundaryFile.exists()) {
        try {
          final decoded = jsonDecode(await boundaryFile.readAsString());
          if (decoded is List) {
            boundaries = decoded
                .whereType<Map>()
                .map(
                  (item) => EdgeSentenceBoundary.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList();
          }
        } catch (error) {
          debugPrint('[TtsService] Dictation cache index invalid: $error');
          boundaries = [];
        }
      }

      if (boundaries.isEmpty) {
        final synthesized = await _synthesizeEnglishEssayWithEdgeBoundaries(
          cleanText,
        );
        if (runId != _dictationRunId) return;
        boundaries = synthesized.boundaries;
        await audioFile.writeAsBytes(synthesized.audioBytes, flush: true);
        await boundaryFile.writeAsString(
          jsonEncode(boundaries.map((boundary) => boundary.toJson()).toList()),
          flush: true,
        );
      }

      if (boundaries.isEmpty) {
        throw Exception('微软语音未返回句子时间数据，请重试');
      }

      _isEnglishSynthesizing = false;
      _currentAudioType = ActiveAudioType.english;
      WakelockService.enable();
      final fullDuration = await _audioPlayer.setFilePath(audioFile.path);
      dictationAudioLoaded = true;
      if (fullDuration == null || fullDuration <= Duration.zero) {
        throw Exception('无法读取微软生成的作文语音文件');
      }
      await _audioPlayer.setSpeed(_englishSpeed);
      await _audioPlayer.setLoopMode(LoopMode.off);
      _startHeadphoneMonitor();
      notifyListeners();

      _dictationSentenceCount = boundaries.length;
      _dictationCycleIndex = 1;
      var sentenceIndex = 0;
      while (runId == _dictationRunId) {
        if (sentenceIndex >= boundaries.length) {
          if (!shouldContinueEnglishDictation(
            loopEnabled: _isLoopMode,
            runId: runId,
            currentRunId: _dictationRunId,
          )) {
            break;
          }
          _dictationCycleIndex++;
          sentenceIndex = 0;
          notifyListeners();
          continue;
        }

        final boundary = boundaries[sentenceIndex];
        final nextOffset = sentenceIndex + 1 < boundaries.length
            ? boundaries[sentenceIndex + 1].offset
            : fullDuration;
        final clipStart = boundary.offset < Duration.zero
            ? Duration.zero
            : boundary.offset;
        var clipEnd = boundary.duration > Duration.zero
            ? clipStart + boundary.duration
            : nextOffset;
        if (clipEnd > fullDuration) clipEnd = fullDuration;
        if (clipEnd <= clipStart) {
          throw Exception('微软返回的第 ${sentenceIndex + 1} 句时间范围无效');
        }
        final clipDuration = clipEnd - clipStart;
        var navigationInterruptedSentence = false;

        for (
          var repeatIndex = 0;
          repeatIndex < safeRepeatCount;
          repeatIndex++
        ) {
          if (runId != _dictationRunId) return;
          if (_dictationSentenceNavigationRequest != 0) {
            navigationInterruptedSentence = true;
            break;
          }
          _dictationSentenceIndex = sentenceIndex + 1;
          _dictationRepeatIndex = repeatIndex + 1;
          _setEnglishDictationMetadata(
            duration: clipDuration,
            repeatCount: safeRepeatCount,
            isExtraReplay: false,
          );
          await _audioPlayer.seek(clipStart);
          notifyListeners();

          while (runId == _dictationRunId) {
            await _dictationPauseGate.waitWhilePaused();
            if (runId != _dictationRunId) return;
            if (_dictationSentenceNavigationRequest != 0) {
              navigationInterruptedSentence = true;
              break;
            }
            if (_dictationExtraReplayRequests > 0) {
              final shouldContinue = await _playPendingExtraDictationReplays(
                runId: runId,
                clipStart: clipStart,
                clipEnd: clipEnd,
                clipDuration: clipDuration,
                repeatCount: safeRepeatCount,
              );
              if (!shouldContinue) return;
              if (_dictationSentenceNavigationRequest != 0) {
                navigationInterruptedSentence = true;
                break;
              }
              _setEnglishDictationMetadata(
                duration: clipDuration,
                repeatCount: safeRepeatCount,
                isExtraReplay: false,
              );
              await _audioPlayer.seek(clipStart);
              notifyListeners();
              continue;
            }
            await _playAudioUntilSafely('English dictation', end: clipEnd);
            if (_dictationSentenceNavigationRequest != 0) {
              navigationInterruptedSentence = true;
              break;
            }
            if (_dictationPauseGate.isPaused) continue;
            if (_dictationExtraReplayRequests > 0) continue;
            break;
          }
          if (runId != _dictationRunId) return;
          await _audioPlayer.pause();
          if (navigationInterruptedSentence) break;
        }

        if (runId != _dictationRunId) return;
        if (navigationInterruptedSentence ||
            _dictationSentenceNavigationRequest != 0) {
          final direction = _dictationSentenceNavigationRequest;
          _dictationSentenceNavigationRequest = 0;
          sentenceIndex = resolveEnglishDictationSentenceNavigation(
            currentIndex: sentenceIndex,
            sentenceCount: boundaries.length,
            direction: direction,
          );
          notifyListeners();
          continue;
        }

        final shouldPauseAfterSentence =
            sentenceIndex < boundaries.length - 1 ||
            shouldContinueEnglishDictation(
              loopEnabled: _isLoopMode,
              runId: runId,
              currentRunId: _dictationRunId,
            );
        if (!shouldPauseAfterSentence) {
          sentenceIndex++;
          continue;
        }

        // Commands also remain responsive during the three-second gap. A
        // triple-click here replays the sentence that just finished; next or
        // previous changes sentence immediately without waiting out the gap.
        while (runId == _dictationRunId) {
          if (_dictationSentenceNavigationRequest != 0) {
            final direction = _dictationSentenceNavigationRequest;
            _dictationSentenceNavigationRequest = 0;
            sentenceIndex = resolveEnglishDictationSentenceNavigation(
              currentIndex: sentenceIndex,
              sentenceCount: boundaries.length,
              direction: direction,
            );
            notifyListeners();
            break;
          }
          if (_dictationExtraReplayRequests > 0) {
            final shouldContinue = await _playPendingExtraDictationReplays(
              runId: runId,
              clipStart: clipStart,
              clipEnd: clipEnd,
              clipDuration: clipDuration,
              repeatCount: safeRepeatCount,
            );
            if (!shouldContinue) return;
            continue;
          }
          await _waitForDictationCommandOrGap(pauseBetweenSentences);
          if (_dictationSentenceNavigationRequest == 0 &&
              _dictationExtraReplayRequests == 0) {
            sentenceIndex++;
            break;
          }
        }
      }
    } finally {
      if (runId == _dictationRunId) {
        _isEnglishSynthesizing = false;
        _isEnglishDictationPlaying = false;
        _isNativeEnglishPlaying = false;
        _dictationRepeatIndex = 0;
        _dictationCycleIndex = 0;
        _dictationExtraReplayRequests = 0;
        _dictationSentenceNavigationRequest = 0;
        _wakeDictationCommandLoop();
        _dictationCommandSignal = null;
        _isEnglishDictationExtraReplay = false;
        _dictationMediaPauseAt = null;
        _dictationPauseGate.cancel();
        globalAudioHandler.onPlayRequested = null;
        globalAudioHandler.onPauseRequested = null;
        globalAudioHandler.onSkipNext = null;
        globalAudioHandler.onSkipPrevious = null;
        _currentAudioType = ActiveAudioType.none;
        _stopHeadphoneMonitor();
        WakelockService.disable();
        if (dictationAudioLoaded) {
          // Keep the cached full file loaded for the controls, but leave it
          // paused. Dictation never replaces it with per-sentence clips.
          await _audioPlayer.pause();
        }
        await _applyAudioPlayerLoopMode();
        notifyListeners();
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // 🇨🇳 中文朗读接口（方案 1: iOS 本地原生 / 方案 2: 微软 Edge 晓晓神经网络女声）
  // ════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════
  // 🇨🇳 中文朗读接口（方案 1: iOS 本地原生 / 方案 2: 微软 Edge 晓晓神经网络女声）
  // ════════════════════════════════════════════════════════════════════

  Future<void> speakChinese(
    String text, {
    String? geminiKey,
    String? siliconFlowKey,
  }) async {
    _ensurePlaybackAllowed();
    await init();
    await stopAll();
    _ensurePlaybackAllowed();
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected()))
      throw Exception("NoHeadphones | ${lastRouteDebug}");

    final clean = _sanitizeMarkdown(text);
    if (clean.isEmpty) return;

    WakelockService.enable();

    final textHash = md5.convert(utf8.encode(clean)).toString();
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory("${docsDir.path}/tts_cache");
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    // ════════════════════════════════════════════════════════════════════
    // 方案一：iOS 系统原生中文 (0秒秒开，纯离线系统发音)
    // ════════════════════════════════════════════════════════════════════
    if (_chineseEngine == ChineseTtsEngine.iosNative) {
      _currentAudioType = ActiveAudioType.chinese;
      _isChineseNativePlaying = true;
      _chineseNativePosition = Duration.zero;

      final estTotalSeconds = (clean.length / 3.8).clamp(2.0, 600.0);
      _chineseNativeDuration = Duration(
        milliseconds: (estTotalSeconds * 1000).toInt(),
      );

      await _flutterTts.stop();
      await _flutterTts.setLanguage("zh-CN");
      await _flutterTts.setSpeechRate(_chineseSpeed * 0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _startChineseNativeProgressTimer();

      await _speakNativeSafely(clean, playbackSource: 'Chinese native');
      globalAudioHandler.setPlaybackMetadata(
        title: _formatLockscreenTitle(clean),
        artist: '中文 · iOS 原生语音',
        duration: _chineseNativeDuration,
      );
      _startHeadphoneMonitor();
      notifyListeners();
      return;
    }

    // ════════════════════════════════════════════════════════════════════
    // 方案二：微软 Edge 晓晓神经网络播音女声 (zh-CN-XiaoxiaoNeural · 24kHz 拟真女声)
    // ════════════════════════════════════════════════════════════════════
    final cachedFile = File("${cacheDir.path}/chinese_neural_$textHash.mp3");

    if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
      debugPrint(
        "[TtsCache] Hit local Chinese neural disk cache: ${cachedFile.path}",
      );
      _currentAudioType = ActiveAudioType.chinese;
      final duration = await _audioPlayer.setFilePath(cachedFile.path);
      globalAudioHandler.setPlaybackMetadata(
        title: _formatLockscreenTitle(clean),
        artist: '中文 · 晓晓神经网络女声',
        duration: duration,
      );
      await _audioPlayer.setSpeed(_chineseSpeed);
      await _applyAudioPlayerLoopMode();
      await _playAudioSafely('Chinese cached audio');
      _startHeadphoneMonitor();
      notifyListeners();
      return;
    }

    try {
      _isChineseSynthesizing = true;
      notifyListeners();

      List<int>? synthesizedBytes;

      // 1. 优先使用微软 Edge 官方 WebSocket 协议直连 (zh-CN-XiaoxiaoNeural · 24kHz 播音女声)
      try {
        debugPrint(
          "[TtsService] Synthesizing Chinese via Microsoft Edge WebSocket (Xiaoxiao)...",
        );
        synthesizedBytes = await _synthesizeWithEdgeWebSocket(
          clean,
          "zh-CN-XiaoxiaoNeural",
        );
      } catch (wsErr) {
        debugPrint("[TtsService] Microsoft Edge WebSocket failed ($wsErr)");
      }

      // 2. 微软 Edge HTTP 代理节点降级
      if (synthesizedBytes == null || synthesizedBytes.isEmpty) {
        try {
          debugPrint(
            "[TtsService] Synthesizing Chinese audio via Microsoft Edge HTTP Proxy...",
          );
          synthesizedBytes = await _synthesizeChineseWithEdge(clean);
        } catch (edgeErr) {
          debugPrint("[TtsService] Chinese Edge Neural HTTP failed ($edgeErr)");
        }
      }

      // 3. 硅基流动（SiliconFlow）第三级备用通道
      final effectiveSiliconKey = (siliconFlowKey ?? '').trim();
      if ((synthesizedBytes == null || synthesizedBytes.isEmpty) &&
          effectiveSiliconKey.isNotEmpty) {
        try {
          debugPrint(
            "[TtsService] Synthesizing Chinese via SiliconFlow CosyVoice...",
          );
          synthesizedBytes = await _synthesizeChineseWithSiliconFlow(
            clean,
            effectiveSiliconKey,
          );
        } catch (e) {
          debugPrint("[TtsService] SiliconFlow Chinese failed: $e");
        }
      }

      // 4. 有线/无线合成成功，保存本地缓存并由 _audioPlayer 播放
      if (synthesizedBytes != null && synthesizedBytes.isNotEmpty) {
        await cachedFile.writeAsBytes(synthesizedBytes);
        _isChineseSynthesizing = false;
        _currentAudioType = ActiveAudioType.chinese;

        final duration = await _audioPlayer.setFilePath(cachedFile.path);
        globalAudioHandler.setPlaybackMetadata(
          title: _formatLockscreenTitle(clean),
          artist: '中文 · 晓晓神经网络女声',
          duration: duration,
        );
        await _audioPlayer.setSpeed(_chineseSpeed);
        await _applyAudioPlayerLoopMode();
        await _playAudioSafely('Chinese synthesized audio');
        _startHeadphoneMonitor();
        notifyListeners();
        return;
      }

      // 5. 若所有在线 API 均失败或网络断开，平滑回退至 iOS 本地离线原生发音（不爆弹窗，保证 100% 正常播放）
      debugPrint(
        "[TtsService] Online Chinese TTS unavailable, falling back to iOS Native Speech",
      );
      _isChineseSynthesizing = false;
      _currentAudioType = ActiveAudioType.chinese;
      _isChineseNativePlaying = true;
      _chineseNativePosition = Duration.zero;

      final estTotalSeconds = (clean.length / 3.8).clamp(2.0, 600.0);
      _chineseNativeDuration = Duration(
        milliseconds: (estTotalSeconds * 1000).toInt(),
      );

      await _flutterTts.stop();
      await _flutterTts.setLanguage("zh-CN");
      await _flutterTts.setSpeechRate(_chineseSpeed * 0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _startChineseNativeProgressTimer();

      await _speakNativeSafely(
        clean,
        playbackSource: 'Chinese native fallback',
      );
      globalAudioHandler.setPlaybackMetadata(
        title: _formatLockscreenTitle(clean),
        artist: '中文 · iOS 离线原生语音',
        duration: _chineseNativeDuration,
      );
      _startHeadphoneMonitor();
      notifyListeners();
    } finally {
      _isChineseSynthesizing = false;
      notifyListeners();
    }
  }

  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  @visibleForTesting
  static List<EdgeSentenceBoundary> parseEdgeSentenceMetadata(String frame) {
    if (!frame.contains('Path:audio.metadata')) return const [];
    final separator = frame.indexOf('\r\n\r\n');
    if (separator < 0 || separator + 4 >= frame.length) return const [];
    final decoded = jsonDecode(frame.substring(separator + 4));
    final metadata = decoded is Map ? decoded['Metadata'] : null;
    if (metadata is! List) return const [];

    final boundaries = <EdgeSentenceBoundary>[];
    for (final entry in metadata) {
      if (entry is! Map) continue;
      final type = entry['Type']?.toString() ?? '';
      if (!type.toLowerCase().contains('sentence')) continue;
      final data = entry['Data'];
      if (data is! Map) continue;
      final offsetTicks = (data['Offset'] as num?)?.toInt() ?? 0;
      final durationTicks = (data['Duration'] as num?)?.toInt() ?? 0;
      final textData = data['text'] ?? data['Text'];
      final sentenceText = textData is Map
          ? (textData['Text'] ?? textData['text'])?.toString() ?? ''
          : textData?.toString() ?? '';
      boundaries.add(
        EdgeSentenceBoundary(
          text: sentenceText.trim(),
          offset: Duration(microseconds: offsetTicks ~/ 10),
          duration: Duration(microseconds: durationTicks ~/ 10),
        ),
      );
    }
    return boundaries;
  }

  /// 微软 Edge 官方 WebSocket 协议神经网络发音合成
  Future<List<int>> _synthesizeWithEdgeWebSocket(
    String text,
    String voiceName,
  ) async {
    final chunks = _splitTextIntoChunks(text, maxChunkSize: 350);
    final allAudioBytes = <int>[];

    for (final chunk in chunks) {
      final safeChunk = _escapeXml(chunk);
      final lang = voiceName.startsWith("zh") ? "zh-CN" : "en-US";
      final requestId = md5
          .convert(utf8.encode(DateTime.now().toIso8601String() + chunk))
          .toString()
          .replaceAll('-', '');

      // [Phase 4 Section 4.5] 使用 EdgeTtsAuth 动态计算 Sec-MS-GEC 防盗链 Token 并在 WebSocket 连接时安全隔离凭据
      final wsUrl = EdgeTtsAuth.buildWebSocketUrl(utcNow: DateTime.now());

      final client = HttpClient();
      client.userAgent =
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0";

      try {
        final secureRandom = Random.secure();
        final muid = List.generate(
          32,
          (_) => secureRandom.nextInt(16).toRadixString(16),
        ).join().toUpperCase();

        final socket = await WebSocket.connect(
          wsUrl,
          headers: {
            "Pragma": "no-cache",
            "Cache-Control": "no-cache",
            "Origin": "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
            "Cookie": "muid=$muid;",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Accept-Language": "en-US,en;q=0.9",
          },
          customClient: client,
        ).timeout(const Duration(seconds: 15));

        final chunkBytes = <int>[];
        final completer = Completer<void>();

        socket.listen(
          (data) {
            if (data is List<int> && data.length > 2) {
              final headerLength = (data[0] << 8) | data[1];
              if (data.length >= 2 + headerLength) {
                final headerStr = utf8.decode(
                  data.sublist(2, 2 + headerLength),
                  allowMalformed: true,
                );
                if (headerStr.contains("Path:audio")) {
                  chunkBytes.addAll(data.sublist(2 + headerLength));
                }
              }
            } else if (data is String) {
              if (data.contains("Path:turn.end")) {
                if (!completer.isCompleted) completer.complete();
              }
            }
          },
          onError: (err) {
            if (!completer.isCompleted) completer.completeError(err);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
        );

        final configFrame =
            "Content-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n"
            '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
        socket.add(configFrame);

        final ssmlFrame =
            "X-RequestId:$requestId\r\nContent-Type:application/ssml+xml\r\nPath:ssml\r\n\r\n"
            "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xmlns:mstts='http://www.w3.org/2001/mstts' xml:lang='$lang'><voice name='$voiceName'><prosody pitch='+0Hz' rate='+0%'>$safeChunk</prosody></voice></speak>";
        socket.add(ssmlFrame);

        await completer.future.timeout(
          const Duration(seconds: 45),
          onTimeout: () {
            socket.close();
            throw TimeoutException('Edge WebSocket chunk timeout after 45s');
          },
        );

        await socket.close();

        if (chunkBytes.isNotEmpty) {
          allAudioBytes.addAll(chunkBytes);
        } else {
          throw Exception("Edge WebSocket chunk returned empty audio");
        }
      } finally {
        // [BUG-15 Fix] 必须显式关闭 HttpClient，防止多 chunk 合成时 HTTP 连接池泄漏
        client.close(force: true);
      }
    }

    if (allAudioBytes.isEmpty)
      throw Exception("Edge WebSocket returned empty audio");
    return allAudioBytes;
  }

  /// Synthesizes one complete essay and captures Edge sentence offsets from
  /// the same request. The audio and metadata therefore share one timeline.
  Future<_EdgeSynthesisWithBoundaries>
  _synthesizeEnglishEssayWithEdgeBoundaries(String text) async {
    final safeText = _escapeXml(text);
    final requestId = md5
        .convert(utf8.encode('${DateTime.now().toIso8601String()}$text'))
        .toString();
    final wsUrl = EdgeTtsAuth.buildWebSocketUrl(utcNow: DateTime.now());
    final client = HttpClient()
      ..userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 '
          'Safari/537.36 Edg/143.0.0.0';

    try {
      final secureRandom = Random.secure();
      final muid = List.generate(
        32,
        (_) => secureRandom.nextInt(16).toRadixString(16),
      ).join().toUpperCase();
      final socket = await WebSocket.connect(
        wsUrl,
        headers: {
          'Pragma': 'no-cache',
          'Cache-Control': 'no-cache',
          'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
          'Cookie': 'muid=$muid;',
          'Accept-Encoding': 'gzip, deflate, br, zstd',
          'Accept-Language': 'en-US,en;q=0.9',
        },
        customClient: client,
      ).timeout(const Duration(seconds: 15));

      final audioBytes = <int>[];
      final rawBoundaries = <EdgeSentenceBoundary>[];
      final completer = Completer<void>();

      void parseMetadataFrame(String frame) {
        try {
          rawBoundaries.addAll(parseEdgeSentenceMetadata(frame));
        } catch (error) {
          debugPrint('[TtsService] Edge boundary metadata parse error: $error');
        }
      }

      socket.listen(
        (data) {
          if (data is List<int> && data.length > 2) {
            final headerLength = (data[0] << 8) | data[1];
            if (data.length < 2 + headerLength) return;
            final header = utf8.decode(
              data.sublist(2, 2 + headerLength),
              allowMalformed: true,
            );
            if (header.contains('Path:audio')) {
              audioBytes.addAll(data.sublist(2 + headerLength));
            }
          } else if (data is String) {
            parseMetadataFrame(data);
            if (data.contains('Path:turn.end') && !completer.isCompleted) {
              completer.complete();
            }
          }
        },
        onError: (Object error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      socket.add(
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":'
        '{"sentenceBoundaryEnabled":"true",'
        '"wordBoundaryEnabled":"true"},'
        '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}',
      );
      socket.add(
        'X-RequestId:$requestId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'Path:ssml\r\n\r\n'
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
        "xmlns:mstts='http://www.w3.org/2001/mstts' xml:lang='en-US'>"
        "<voice name='en-US-JennyNeural'><prosody pitch='+0Hz' rate='+0%'>"
        '$safeText</prosody></voice></speak>',
      );

      await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          unawaited(socket.close());
          throw TimeoutException('Edge essay synthesis timeout after 60s');
        },
      );
      await socket.close();

      if (audioBytes.isEmpty) {
        throw Exception('Edge returned empty essay audio');
      }
      rawBoundaries.sort((a, b) => a.offset.compareTo(b.offset));
      if (rawBoundaries.isEmpty) {
        throw Exception('Edge did not return sentence boundary metadata');
      }

      final normalized = <EdgeSentenceBoundary>[];
      for (var index = 0; index < rawBoundaries.length; index++) {
        final current = rawBoundaries[index];
        final nextOffset = index + 1 < rawBoundaries.length
            ? rawBoundaries[index + 1].offset
            : null;
        final duration = current.duration > Duration.zero
            ? current.duration
            : nextOffset != null
            ? nextOffset - current.offset
            : Duration.zero;
        normalized.add(
          EdgeSentenceBoundary(
            text: current.text,
            offset: current.offset,
            duration: duration,
          ),
        );
      }
      return _EdgeSynthesisWithBoundaries(
        audioBytes: audioBytes,
        boundaries: normalized,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 微软 Edge 晓晓中文神经网络播音女声 HTTP 备用
  Future<List<int>> _synthesizeChineseWithEdge(String text) async {
    final chunks = _splitTextIntoChunks(text, maxChunkSize: 600);
    final allMp3Bytes = <int>[];

    for (final chunk in chunks) {
      // 1. Public Edge TTS Proxy Endpoint 1
      try {
        final url2 = Uri.parse("https://edge-tts.duti.tech/api/tts");
        final resp2 = await http
            .post(
              url2,
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "text": chunk,
                "voice": "zh-CN-XiaoxiaoNeural",
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (resp2.statusCode == 200 && resp2.bodyBytes.isNotEmpty) {
          allMp3Bytes.addAll(resp2.bodyBytes);
          continue;
        }
      } catch (_) {}

      // 2. Public Edge TTS Proxy Endpoint 2
      try {
        final url3 = Uri.parse("https://tts.m8a.net/api/tts");
        final resp3 = await http
            .post(
              url3,
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "text": chunk,
                "voice": "zh-CN-XiaoxiaoNeural",
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (resp3.statusCode == 200 && resp3.bodyBytes.isNotEmpty) {
          allMp3Bytes.addAll(resp3.bodyBytes);
          continue;
        }
      } catch (_) {}

      throw Exception("All Edge Chinese endpoints returned empty");
    }

    if (allMp3Bytes.isEmpty)
      throw Exception("Chinese Edge Neural returned empty data");
    return allMp3Bytes;
  }

  Future<List<int>> _synthesizeChineseWithSiliconFlow(
    String text,
    String siliconFlowKey,
  ) async {
    final chunks = _splitTextIntoChunks(text, maxChunkSize: 600);
    final allBytes = <int>[];

    for (final chunk in chunks) {
      final url = Uri.parse("https://api.siliconflow.cn/v1/audio/speech");

      // 1. 优先使用 SiliconFlow 的 24kHz 中文神经网络晓晓女声 (speech:zh-CN-XiaoxiaoNeural)
      var response = await http
          .post(
            url,
            headers: {
              "Authorization": "Bearer ${siliconFlowKey.trim()}",
              "Content-Type": "application/json",
            },
            body: jsonEncode({
              "model": "speech:zh-CN-XiaoxiaoNeural",
              "input": chunk,
              "voice": "speech:zh-CN-XiaoxiaoNeural",
              "response_format": "mp3",
              "stream": false,
            }),
          )
          .timeout(const Duration(seconds: 20));

      // 2. 若专有模型未提供，使用 CosyVoice 24kHz 高级双语女声 Bella 兜底
      if (response.statusCode != 200) {
        response = await http
            .post(
              url,
              headers: {
                "Authorization": "Bearer ${siliconFlowKey.trim()}",
                "Content-Type": "application/json",
              },
              body: jsonEncode({
                "model": "FunAudioLLM/CosyVoice2-0.5B",
                "input": chunk,
                "voice": "FunAudioLLM/CosyVoice2-0.5B:bella",
                "response_format": "mp3",
                "stream": false,
              }),
            )
            .timeout(const Duration(seconds: 20));
      }

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        allBytes.addAll(response.bodyBytes);
      } else {
        throw Exception("SiliconFlow Chinese HTTP ${response.statusCode}");
      }
    }

    if (allBytes.isEmpty)
      throw Exception("SiliconFlow Chinese returned empty data");
    return allBytes;
  }

  Future<void> playChinese() async {
    _ensurePlaybackAllowed();
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected()))
      throw Exception("NoHeadphones | ${lastRouteDebug}");
    WakelockService.enable();
    _currentAudioType = ActiveAudioType.chinese;
    if (_isChineseNativePlaying ||
        (_chineseNativePosition > Duration.zero &&
            _chineseNativeDuration > Duration.zero)) {
      // 原生 TTS 履复：重新启动 timer，位置保持不变
      _isChineseNativePlaying = true;
      _startChineseNativeProgressTimer();
      final text = _lastNativeChineseText;
      if (text == null || text.isEmpty) return;
      await _speakNativeSafely(text, playbackSource: 'Chinese native resume');
      notifyListeners();
    } else {
      // 普通 _audioPlayer 模式（微软合成音频）
      await _applyAudioPlayerLoopMode();
      await _playAudioSafely('Chinese resume');
    }
    _startHeadphoneMonitor();
  }

  Future<void> pauseChinese() async {
    if (_isChineseNativePlaying) {
      // 原生 TTS 暂停：停止 timer 和语音
      _isChineseNativePlaying = false;
      _chineseNativeTimer?.cancel();
      await _flutterTts.pause();
    } else {
      // _audioPlayer 模式
      await _audioPlayer.pause();
    }
    notifyListeners();
  }

  Future<void> stopChinese() async {
    await _flutterTts.stop();
    if (_currentAudioType == ActiveAudioType.chinese) {
      await _audioPlayer.stop();
      _currentAudioType = ActiveAudioType.none;
      globalAudioHandler.setPlaybackMetadata(
        title: 'Jeff Notes',
        artist: '播放已停止',
      );
      notifyListeners();
    }
    _finishNativePlayback();
  }

  Future<void> seekChinese(Duration position) async {
    if (_isChineseNativePlaying ||
        (_chineseNativePosition > Duration.zero &&
            _chineseNativeDuration > Duration.zero)) {
      // 原生 TTS 模式：更新虚拟进度，无法真实 seek flutter_tts
      // Duration 没有内置 clamp，手动实现
      final clamped = position < Duration.zero
          ? Duration.zero
          : position > _chineseNativeDuration
          ? _chineseNativeDuration
          : position;
      _chineseNativePosition = clamped;
      notifyListeners();
    } else {
      await _audioPlayer.seek(position);
    }
  }

  Future<void> setChineseSpeed(double speed) async {
    _chineseSpeed = speed;
    if (_currentAudioType == ActiveAudioType.chinese) {
      await _audioPlayer.setSpeed(speed);
    }
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════
  // 🎙️ 真实课堂现场原声音频朗读接口（使用录音时的真实 .wav 文件）
  // ════════════════════════════════════════════════════════════════════

  Future<void> speakRecordedAudio(String wavPath) async {
    _ensurePlaybackAllowed();
    await init();
    await stopAll();
    _ensurePlaybackAllowed();
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected()))
      throw Exception("NoHeadphones | ${lastRouteDebug}");

    WakelockService.enable();

    final file = File(wavPath);
    if (!await file.exists()) {
      throw Exception("找不到真实课堂录音文件");
    }

    _currentAudioType = ActiveAudioType.recorded;
    final duration = await _audioPlayer.setFilePath(file.path);
    globalAudioHandler.setPlaybackMetadata(
      title: '英文原声 (真实课堂录音)',
      artist: 'Jeff Notes Real Classroom Audio',
      duration: duration,
    );
    await _audioPlayer.setSpeed(_englishSpeed);
    await _applyAudioPlayerLoopMode();
    await _playAudioSafely('Recorded audio');
    _startHeadphoneMonitor();
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════
  // 🇬🇧 英文 AI 拟真音色朗读接口（SiliconFlow AI + 2级缓存降级方案）
  // ════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════
  // 🇬🇧 英文 AI 拟真音色朗读接口（Gemini 2.0 Flash 原生 API + 硅基流动降级方案）
  // ════════════════════════════════════════════════════════════════════

  Future<void> speakEnglish(
    String text, {
    String? geminiKey,
    String? siliconFlowKey,
  }) async {
    _ensurePlaybackAllowed();
    await init();
    await stopAll();
    _ensurePlaybackAllowed();
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected()))
      throw Exception("NoHeadphones | ${lastRouteDebug}");

    final clean = _sanitizeMarkdown(text);
    if (clean.isEmpty) return;

    WakelockService.enable();

    // ════════════════════════════════════════════════════════════════════
    // 方案一：iOS 系统原生高保真美音女声 (0.000秒秒开 · 0元0Token · 100%离线)
    // ════════════════════════════════════════════════════════════════════
    if (_englishEngine == EnglishTtsEngine.iosNative) {
      _currentAudioType = ActiveAudioType.english;
      await _flutterTts.stop();
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(_englishSpeed * 0.5);
      await _flutterTts.setPitch(1.0);

      try {
        final voices = await _flutterTts.getVoices;
        if (voices != null && voices is List) {
          for (final voice in voices) {
            if (voice is Map) {
              final name = voice["name"]?.toString() ?? "";
              final locale = voice["locale"]?.toString() ?? "";
              if (locale.contains("en-US") &&
                  (name.contains("Samantha") ||
                      name.contains("Ava") ||
                      name.contains("Karen") ||
                      name.contains("Allison"))) {
                await _flutterTts.setVoice({"name": name, "locale": locale});
                break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint("[TtsService] Voice selection fallback: $e");
      }

      await _speakNativeSafely(clean, playbackSource: 'English native');
      globalAudioHandler.setPlaybackMetadata(
        title: _formatLockscreenTitle(clean),
        artist: 'English · iOS Native Voice',
      );
      _startHeadphoneMonitor();
      notifyListeners();
      return;
    }

    // ════════════════════════════════════════════════════════════════════
    // 方案二：高清神经网络播音女声 (Bella / Edge Neural · 24kHz 拟真女声)
    // ════════════════════════════════════════════════════════════════════
    final textHash = md5.convert(utf8.encode(clean)).toString();
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory("${docsDir.path}/tts_cache");
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final cachedFile = File("${cacheDir.path}/english_neural_$textHash.mp3");

    // 如果命中了本地缓存，毫秒级载入本地文件播放
    if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
      debugPrint("[TtsCache] Hit Neural local disk cache: ${cachedFile.path}");
      _currentAudioType = ActiveAudioType.english;
      final duration = await _audioPlayer.setFilePath(cachedFile.path);
      globalAudioHandler.setPlaybackMetadata(
        title: _formatLockscreenTitle(clean),
        artist: 'English · AI Neural Voice',
        duration: duration,
      );
      await _audioPlayer.setSpeed(_englishSpeed);
      await _applyAudioPlayerLoopMode();
      await _playAudioSafely('English cached audio');
      _startHeadphoneMonitor();
      notifyListeners();
      return;
    }

    try {
      _isEnglishSynthesizing = true;
      notifyListeners();

      List<int>? synthesizedBytes;

      final effectiveSiliconKey = (siliconFlowKey ?? '').trim();
      final effectiveGeminiKey = (geminiKey ?? '').trim();

      // 1. 优先使用微软 Edge 官方 WebSocket 协议直连 (en-US-JennyNeural · 24kHz 播音美音)
      try {
        debugPrint(
          "[TtsService] Synthesizing English audio via Microsoft Edge WebSocket (Jenny)...",
        );
        synthesizedBytes = await _synthesizeWithEdgeWebSocket(
          clean,
          "en-US-JennyNeural",
        );
      } catch (wsErr) {
        debugPrint("[TtsService] English Edge WebSocket failed ($wsErr)");
      }

      // 2. 微软 Edge HTTP 降级方案
      if (synthesizedBytes == null || synthesizedBytes.isEmpty) {
        try {
          debugPrint(
            "[TtsService] Synthesizing audio via Microsoft Edge Neural HTTP...",
          );
          synthesizedBytes = await _synthesizeWithEdgeNeural(clean);
        } catch (e) {
          debugPrint("[TtsService] Edge Neural HTTP failed: $e");
        }
      }

      // 3. 三级兜底：iOS 原生离线语音（秒播 · 零延迟 · 零成本 · 不断网保障）
      if (synthesizedBytes == null || synthesizedBytes.isEmpty) {
        try {
          debugPrint(
            "[TtsService] Fallback to iOS Native Speech (3rd tier)...",
          );
          _currentAudioType = ActiveAudioType.english;
          await _flutterTts.stop();
          await _flutterTts.setLanguage("en-US");
          await _flutterTts.setSpeechRate(_englishSpeed * 0.5);
          await _flutterTts.setPitch(1.0);
          final voices = await _flutterTts.getVoices;
          if (voices != null && voices is List) {
            for (final voice in voices) {
              if (voice is Map) {
                final name = voice["name"]?.toString() ?? "";
                final locale = voice["locale"]?.toString() ?? "";
                if (locale.contains("en-US") &&
                    (name.contains("Samantha") ||
                        name.contains("Ava") ||
                        name.contains("Karen") ||
                        name.contains("Allison"))) {
                  await _flutterTts.setVoice({"name": name, "locale": locale});
                  break;
                }
              }
            }
          }
          await _speakNativeSafely(
            clean,
            playbackSource: 'English native fallback',
          );
          globalAudioHandler.setPlaybackMetadata(
            title: _formatLockscreenTitle(clean),
            artist: 'English · iOS Native Voice',
          );
          _startHeadphoneMonitor();
          _isEnglishSynthesizing = false;
          notifyListeners();
          return;
        } catch (iosErr) {
          debugPrint("[TtsService] iOS Native failed: $iosErr");
        }
      }

      // 4. 若配置了 SiliconFlow Key，备用尝试 24kHz 播音级女声 Bella
      if ((synthesizedBytes == null || synthesizedBytes.isEmpty) &&
          effectiveSiliconKey.isNotEmpty) {
        try {
          debugPrint(
            "[TtsService] Synthesizing audio via SiliconFlow Bella Female Voice...",
          );
          synthesizedBytes = await _synthesizeWithSiliconFlow(
            clean,
            effectiveSiliconKey,
            textHash,
          );
        } catch (e) {
          debugPrint("[TtsService] SiliconFlow Bella failed: $e");
        }
      }

      // 5. 若配置了 Gemini Key，备用尝试 Google 官方播音女声
      if ((synthesizedBytes == null || synthesizedBytes.isEmpty) &&
          effectiveGeminiKey.isNotEmpty) {
        try {
          debugPrint("[TtsService] Synthesizing audio via Google API...");
          synthesizedBytes = await _synthesizeWithGemini(
            clean,
            effectiveGeminiKey,
          );
        } catch (e) {
          debugPrint("[TtsService] Gemini audio failed: $e");
        }
      }

      if (synthesizedBytes != null && synthesizedBytes.isNotEmpty) {
        await cachedFile.writeAsBytes(synthesizedBytes);
        _isEnglishSynthesizing = false;
        _currentAudioType = ActiveAudioType.english;

        final duration = await _audioPlayer.setFilePath(cachedFile.path);
        globalAudioHandler.setPlaybackMetadata(
          title: _formatLockscreenTitle(clean),
          artist: 'English · AI Neural Voice',
          duration: duration,
        );
        await _audioPlayer.setSpeed(_englishSpeed);
        await _applyAudioPlayerLoopMode();
        await _playAudioSafely('English synthesized audio');
        _startHeadphoneMonitor();
        notifyListeners();
        return;
      } else {
        throw Exception("All online neural TTS endpoints returned empty");
      }
    } catch (e) {
      debugPrint(
        "[TtsService] All remaining TTS failed ($e). Last resort: iOS Native Speech.",
      );
      _isEnglishSynthesizing = false;
      notifyListeners();

      _currentAudioType = ActiveAudioType.english;
      await _flutterTts.stop();
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(_englishSpeed * 0.5);
      await _speakNativeSafely(
        clean,
        playbackSource: 'English last-resort native',
      );
      globalAudioHandler.setPlaybackMetadata(
        title: _formatLockscreenTitle(clean),
        artist: 'English · iOS Native Voice',
      );
      _startHeadphoneMonitor();
      notifyListeners();
      return;
    } finally {
      _isEnglishSynthesizing = false;
      notifyListeners();
    }
  }

  /// 微软 Edge 神经网络播音级英文女声合成 (Jenny / Ava)
  Future<List<int>> _synthesizeWithEdgeNeural(String text) async {
    final chunks = _splitTextIntoChunks(text, maxChunkSize: 600);
    final allMp3Bytes = <int>[];

    for (final chunk in chunks) {
      bool chunkOk = false;

      // 1. Public Edge TTS Proxy Endpoint 1
      if (!chunkOk) {
        try {
          final url = Uri.parse("https://edge-tts.duti.tech/api/tts");
          final resp = await http
              .post(
                url,
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({"text": chunk, "voice": "en-US-JennyNeural"}),
              )
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            allMp3Bytes.addAll(resp.bodyBytes);
            chunkOk = true;
          }
        } catch (_) {}
      }

      // 2. Public Edge TTS Proxy Endpoint 2
      if (!chunkOk) {
        try {
          final url = Uri.parse("https://tts.m8a.net/api/tts");
          final resp = await http
              .post(
                url,
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({"text": chunk, "voice": "en-US-JennyNeural"}),
              )
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            allMp3Bytes.addAll(resp.bodyBytes);
            chunkOk = true;
          }
        } catch (_) {}
      }

      // 3. 微软官方 Bing TTS API 兜底
      if (!chunkOk) {
        try {
          final fallbackUrl = Uri.parse(
            "https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/single/tts?api-key=6A5AA1D4EA63472594685157EF9E74B3",
          );
          final fallbackResp = await http
              .post(
                fallbackUrl,
                headers: {
                  "User-Agent":
                      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0",
                  "Content-Type": "application/ssml+xml",
                  "X-Microsoft-OutputFormat": "audio-24khz-48kbitrate-mono-mp3",
                },
                body: utf8.encode(
                  "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
                  "<voice name='en-US-JennyNeural'>"
                  "<prosody pitch='+0Hz' rate='+0%'>$chunk</prosody>"
                  "</voice></speak>",
                ),
              )
              .timeout(const Duration(seconds: 25));
          if (fallbackResp.statusCode == 200 &&
              fallbackResp.bodyBytes.isNotEmpty) {
            allMp3Bytes.addAll(fallbackResp.bodyBytes);
            chunkOk = true;
          }
        } catch (_) {}
      }

      if (!chunkOk) {
        throw Exception("All Edge English endpoints returned empty");
      }
    }

    if (allMp3Bytes.isEmpty)
      throw Exception("Edge Neural English returned empty data");
    return allMp3Bytes;
  }

  /// 使用 Google API (Gemini 2.0 Flash / Google Cloud TTS) 进行原生 Studio 级高保真英文女声合成
  Future<List<int>> _synthesizeWithGemini(String text, String geminiKey) async {
    final chunks = _splitTextIntoChunks(text, maxChunkSize: 900);
    final allAudioBytes = <int>[];
    String? lastError;

    for (final chunk in chunks) {
      bool chunkSuccess = false;

      // 尝试 1：Google Gemini 2.0 Flash Native Audio API (generativelanguage.googleapis.com)
      for (final modality in [
        ["AUDIO"],
        ["audio"],
      ]) {
        if (chunkSuccess) break;
        try {
          final url = Uri.parse(
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${geminiKey.trim()}",
          );
          final response = await http
              .post(
                url,
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                  "contents": [
                    {
                      "parts": [
                        {
                          "text":
                              "Read the following English text aloud clearly, fluently, and naturally with realistic intonation:\n\n$chunk",
                        },
                      ],
                    },
                  ],
                  "generationConfig": {
                    "responseModalities": modality,
                    "speechConfig": {
                      "voiceConfig": {
                        "prebuiltVoiceConfig": {
                          "voiceName": "Aoede", // 优美清晰的 Studio 级原声女音色
                        },
                      },
                    },
                  },
                }),
              )
              .timeout(const Duration(seconds: 35));

          if (response.statusCode == 200) {
            final json = jsonDecode(response.body);
            final candidates = json['candidates'] as List?;
            if (candidates != null && candidates.isNotEmpty) {
              final parts = candidates[0]['content']?['parts'] as List?;
              if (parts != null && parts.isNotEmpty) {
                for (final part in parts) {
                  final inlineData = part['inlineData'];
                  if (inlineData != null && inlineData['data'] != null) {
                    final base64Audio = inlineData['data'] as String;
                    final rawBytes = base64Decode(base64Audio);
                    allAudioBytes.addAll(rawBytes);
                    chunkSuccess = true;
                    break;
                  }
                }
              }
            }
          } else {
            final errJson = jsonDecode(response.body);
            lastError =
                "Gemini API (${response.statusCode}): ${errJson['error']?['message'] ?? response.body}";
          }
        } catch (e) {
          lastError = e.toString();
        }
      }

      // 尝试 2：使用 Google Cloud TTS API (Studio-O / Journey 级原生优美英文女声)
      if (!chunkSuccess) {
        try {
          final ttsUrl = Uri.parse(
            "https://texttospeech.googleapis.com/v1/text:synthesize?key=${geminiKey.trim()}",
          );
          final ttsResponse = await http
              .post(
                ttsUrl,
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                  "input": {"text": chunk},
                  "voice": {
                    "languageCode": "en-US",
                    "name": "en-US-Studio-O", // Google 官方最高阶 Studio 播音级女声
                  },
                  "audioConfig": {"audioEncoding": "MP3"},
                }),
              )
              .timeout(const Duration(seconds: 35));

          if (ttsResponse.statusCode == 200) {
            final json = jsonDecode(ttsResponse.body);
            final audioContent = json['audioContent'] as String?;
            if (audioContent != null && audioContent.isNotEmpty) {
              final mp3Bytes = base64Decode(audioContent);
              allAudioBytes.addAll(mp3Bytes);
              chunkSuccess = true;
            }
          } else {
            final errJson = jsonDecode(ttsResponse.body);
            lastError = errJson['error']?['message'] ?? ttsResponse.body;
          }
        } catch (e) {
          lastError = e.toString();
        }
      }

      if (!chunkSuccess) {
        throw Exception("Google 语音合成失败: ${lastError ?? '请检查 API Key 权限'}");
      }
    }

    if (allAudioBytes.isEmpty) throw Exception("Google 语音 API 返回了空音频数据");

    // 若是 MP3 格式直接返回，若是 PCM 则加入 44 字节 WAV 头
    if (allAudioBytes.length > 4 &&
        allAudioBytes[0] == 0xFF &&
        (allAudioBytes[1] & 0xE0) == 0xE0) {
      return allAudioBytes;
    }
    return _addWavHeader(allAudioBytes, sampleRate: 24000);
  }

  /// 硅基流动 API 备用合成方案
  Future<List<int>> _synthesizeWithSiliconFlow(
    String text,
    String siliconFlowKey,
    String textHash,
  ) async {
    final chunks = _splitTextIntoChunks(text, maxChunkSize: 800);
    final chunkBytesList = <List<int>>[];

    for (int i = 0; i < chunks.length; i++) {
      final url = Uri.parse("https://api.siliconflow.cn/v1/audio/speech");
      final response = await http
          .post(
            url,
            headers: {
              "Authorization": "Bearer ${siliconFlowKey.trim()}",
              "Content-Type": "application/json",
            },
            body: jsonEncode({
              "model": "FunAudioLLM/CosyVoice2-0.5B",
              "input": chunks[i],
              "voice": "FunAudioLLM/CosyVoice2-0.5B:bella", // 高清流畅自然英文播音女声
              "response_format": "mp3",
              "stream": false,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        chunkBytesList.add(response.bodyBytes);
      } else {
        final errBody = response.body.length > 300
            ? response.body.substring(0, 300)
            : response.body;
        throw Exception(
          "SiliconFlow API 错误 (HTTP ${response.statusCode}): $errBody",
        );
      }
    }

    final combined = <int>[];
    for (final bytes in chunkBytesList) {
      combined.addAll(bytes);
    }
    return combined;
  }

  /// 构建标准的 44 字节 PCM WAV 头文件
  List<int> _addWavHeader(
    List<int> pcmBytes, {
    int sampleRate = 24000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmBytes.length;
    final chunkSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6d); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcmBytes);
    return wav;
  }

  Future<void> playEnglish() async {
    _ensurePlaybackAllowed();
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected()))
      throw Exception("NoHeadphones | ${lastRouteDebug}");
    if (_isEnglishDictationPlaying && _dictationPauseGate.isPaused) {
      _dictationPauseGate.resume();
      _startHeadphoneMonitor();
      notifyListeners();
      return;
    }
    _currentAudioType = ActiveAudioType.english;
    await _applyAudioPlayerLoopMode();
    await _playAudioSafely('English resume');
    _startHeadphoneMonitor();
  }

  Future<void> pauseEnglish() async {
    // [BUG-10 Fix] 之前调用 _flutterTts.stop() 会重置 TTS 状态，
    // 恢复播放时从头开始。改为 pause() 与 pauseChinese() 行为一致，可从暂停位置续播。
    if (_isEnglishDictationPlaying) _dictationPauseGate.pause();
    await _flutterTts.pause();
    await _audioPlayer.pause();
    if (!_isEnglishDictationPlaying) _stopHeadphoneMonitor();
    notifyListeners();
  }

  Future<void> stopEnglish() async {
    _dictationRunId++;
    _isEnglishDictationPlaying = false;
    _dictationRepeatIndex = 0;
    _dictationCycleIndex = 0;
    _dictationExtraReplayRequests = 0;
    _dictationSentenceNavigationRequest = 0;
    _wakeDictationCommandLoop();
    _dictationCommandSignal = null;
    _isEnglishDictationExtraReplay = false;
    _dictationMediaPauseAt = null;
    _dictationPauseGate.cancel();
    globalAudioHandler.onPlayRequested = null;
    globalAudioHandler.onPauseRequested = null;
    globalAudioHandler.onSkipNext = null;
    globalAudioHandler.onSkipPrevious = null;
    _isEnglishSynthesizing = false;
    await _flutterTts.stop();
    if (_currentAudioType == ActiveAudioType.english ||
        _currentAudioType == ActiveAudioType.recorded) {
      await _audioPlayer.stop();
      _currentAudioType = ActiveAudioType.none;
      globalAudioHandler.setPlaybackMetadata(
        title: 'Jeff Notes',
        artist: '播放已停止',
      );
      notifyListeners();
    }
    _finishNativePlayback();
  }

  Future<void> seekEnglish(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<void> setEnglishSpeed(double speed) async {
    _englishSpeed = speed;
    if (_currentAudioType == ActiveAudioType.english ||
        _currentAudioType == ActiveAudioType.recorded) {
      await _audioPlayer.setSpeed(speed);
    }
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════
  // 通用控制
  // ════════════════════════════════════════════════════════════════════

  Future<void> pauseAll() async {
    if (_isEnglishDictationPlaying) _dictationPauseGate.pause();
    _isChineseNativePlaying = false;
    _isNativeEnglishPlaying = false;
    _chineseNativeTimer?.cancel();
    if (!_isEnglishDictationPlaying) _stopHeadphoneMonitor();
    await _flutterTts.pause();
    await _audioPlayer.pause();
    notifyListeners();
  }

  Future<void> stopAll() async {
    _dictationRunId++;
    _isEnglishDictationPlaying = false;
    _dictationRepeatIndex = 0;
    _dictationCycleIndex = 0;
    _dictationExtraReplayRequests = 0;
    _dictationSentenceNavigationRequest = 0;
    _wakeDictationCommandLoop();
    _dictationCommandSignal = null;
    _isEnglishDictationExtraReplay = false;
    _dictationMediaPauseAt = null;
    _dictationPauseGate.cancel();
    globalAudioHandler.onPlayRequested = null;
    globalAudioHandler.onPauseRequested = null;
    globalAudioHandler.onSkipNext = null;
    globalAudioHandler.onSkipPrevious = null;
    WakelockService.disable();
    _isChineseNativePlaying = false;
    _isNativeEnglishPlaying = false;
    _chineseNativeTimer?.cancel();
    _stopHeadphoneMonitor();
    await _flutterTts.stop();
    await _audioPlayer.stop();
    _currentAudioType = ActiveAudioType.none;
    _isChineseSynthesizing = false;
    _isEnglishSynthesizing = false;
    notifyListeners();
    // 释放音频会话独占，让麦克风可以被后续录音重新激活
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e) {
      debugPrint('[TtsService] stopAll session release error: $e');
    }
  }

  /// 录音开始前调用：停止所有 TTS 并将会话切回 playAndRecord + setActive
  Future<void> releaseForRecording() async {
    _playbackBlockedForRecording = true;
    notifyListeners();
    await stopAll(); // 停止播放 + 释放 setActive(false)
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        ),
      );
      await session.setActive(true); // 重新激活，解除麦克风静音
      debugPrint(
        '[TtsService] Session released and re-activated for recording',
      );
    } catch (e) {
      debugPrint('[TtsService] releaseForRecording session error: $e');
    }
  }

  /// Re-enable playback only after the recorder has released and restored the
  /// shared audio session. This avoids a tap racing the stop transition.
  void allowPlaybackAfterRecording() {
    if (!_playbackBlockedForRecording) return;
    _playbackBlockedForRecording = false;
    notifyListeners();
  }

  Future<void> speak(String text, {String? siliconFlowKey}) async {
    _ensurePlaybackAllowed();
    if (siliconFlowKey != null && siliconFlowKey.isNotEmpty) {
      await speakEnglish(text, siliconFlowKey: siliconFlowKey);
    } else {
      await speakChinese(text);
    }
  }

  Future<void> stop() => stopAll();

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    // The shared AudioPlayer is owned by the process-wide AudioService
    // handler, not by this ChangeNotifier singleton. Disposing it here can
    // race AudioService/just_audio's own teardown and makes every TTS module
    // lose the same player.
    _flutterTts.stop();
    super.dispose();
  }
}
