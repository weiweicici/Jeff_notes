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
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'wakelock_service.dart';
import '../main.dart';

enum ActiveAudioType { none, chinese, english, recorded }

enum ChineseTtsEngine {
  iosNative,  // 方案一：iOS 系统原生中文 (0秒秒开 · 0元0Token)
  edgeNeural, // 方案二：微软 Edge 晓晓神经网络女声 (0元免费 · 播音级美音)
}

enum EnglishTtsEngine {
  iosNative,
  edgeNeural, // 独家保留：微软 Edge / Bella 高清神经网络播音女声
}

class TtsService extends ChangeNotifier {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;

  AudioPlayer get _audioPlayer => globalAudioHandler.player;
  final FlutterTts _flutterTts = FlutterTts();

  bool _isInitialized = false;
  ActiveAudioType _currentAudioType = ActiveAudioType.none;

  ActiveAudioType get currentAudioType => _currentAudioType;

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
  double _chineseSpeed = 1.25;
  bool _isChineseNativePlaying = false;
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
  double _englishSpeed = 0.8;
  bool _isLoopMode = false; // 默认：播放1次（单次播放），不再默认无限重复
  bool get isLoopMode => _isLoopMode;
  bool get isEnglishSynthesizing => _isEnglishSynthesizing;
  bool get isEnglishPlaying => _audioPlayer.playing && _currentAudioType == ActiveAudioType.english;
  bool get isRecordedPlaying => _audioPlayer.playing && _currentAudioType == ActiveAudioType.recorded;
  double get englishSpeed => _englishSpeed;

  Future<void> toggleLoopMode() async {
    _isLoopMode = !_isLoopMode;
    await _audioPlayer.setLoopMode(_isLoopMode ? LoopMode.one : LoopMode.off);
    notifyListeners();
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
      _audioPlayer.playing || (_isChineseNativePlaying && _currentAudioType == ActiveAudioType.chinese);
  bool get isSynthesizing => _isChineseSynthesizing || _isEnglishSynthesizing;

  TtsService._internal();

  Future<void> init() async {
    if (_isInitialized) return;

    // 1. Configure AudioSession — category must be playback for TTS audio
    //    so iOS routes directly to headphones and NEVER defaults/forces speaker.
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
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
      notifyListeners();
    });

    // 注意：flutter_tts 的 setProgressHandler 在 iOS 上不可靠（不持续触发），
    // 改用 Timer.periodic 计时器在 speakChinese 中模拟进度。

    // 3. Listen to just_audio state changes (for English AI player)
    _audioPlayer.playerStateStream.listen((_) {
      notifyListeners();
    });

    // 4. 监听设备变更（含 AirPods/有线耳机的拔出）→ 有耳机被移除且正在播放时暂停
    //    用 devicesChangedEventStream 比 becomingNoisy 更可靠（后者对 AirPods 不触发）
    _devicesSubscription = session.devicesChangedEventStream.listen((event) async {
      if (!isPlaying) return;
      final hasHeadphoneRemoved = event.devicesRemoved.any((d) {
        final t = d.type;
        return t == AudioDeviceType.wiredHeadset ||
               t == AudioDeviceType.wiredHeadphones ||
               t == AudioDeviceType.bluetoothSco ||
               t == AudioDeviceType.bluetoothA2dp ||
               t == AudioDeviceType.bluetoothLe ||
               t == AudioDeviceType.hearingAid ||
               t == AudioDeviceType.airPlay ||
               t == AudioDeviceType.usbAudio;
      });
      if (hasHeadphoneRemoved) {
        debugPrint('[TtsService] Headphone device removed during playback → pausing.');
        await pauseAll();
      }
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
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));
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
          await avSession.overrideOutputAudioPort(AVAudioSessionPortOverride.none);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[TtsService] ensurePlaybackSession error: $e');
    }
  }

  StreamSubscription? _devicesSubscription;
  Timer? _headphoneMonitor;
  String lastRouteDebug = '';

  void _startHeadphoneMonitor() {
    _stopHeadphoneMonitor();
    // 100ms 高频周期性安全轮询（devicesChangedEventStream 已在 init() 中全局注册）
    _headphoneMonitor = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!isPlaying) {
        _stopHeadphoneMonitor();
        return;
      }
      if (!(await isHeadphonesConnected())) {
        debugPrint('[TtsService] Headphone monitor — lost headphones/speaker selected during playback, stopping immediately.');
        await stopAll();
      }
    });
  }

  void _stopHeadphoneMonitor() {
    _headphoneMonitor?.cancel();
    _headphoneMonitor = null;
  }

  /// 持续轮询检查耳机连接（每 200ms 查一次，最多 4 秒）。
  /// 如果前 2 秒仍未检测到耳机，尝试强制 iOS 重新评估路由再继续轮询。
  Future<bool> isHeadphonesConnected() async {
    lastRouteDebug = '';
    const maxAttempts = 20;
    for (int i = 0; i < maxAttempts; i++) {
      final connected = await _queryCurrentRoute();
      if (connected) {
        lastRouteDebug = '';
        return true;
      }
      if (i == 10 && Platform.isIOS) {
        try {
          final avSession = AVAudioSession();
          await avSession.overrideOutputAudioPort(AVAudioSessionPortOverride.none);
        } catch (_) {}
      }
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

  /// 严密检查系统硬件与输出路由（允许耳机/蓝牙/AirPlay输出，坚决禁止扬声器外放）
  Future<bool> _queryCurrentRoute() async {
    try {
      // 每次查询前重新配置会话，确保不被录音残留的 defaultToSpeaker 干扰
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      ));
      await session.setActive(true);

      // 1. 对 iOS/macOS，直接严密核查系统【当前激活生效的输出端口 currentRoute.outputs】
      if (Platform.isIOS || Platform.isMacOS) {
        // A. 先用插件查（快速路径）
        final avSession = AVAudioSession();
        final route = await avSession.currentRoute;
        final outputs = route.outputs;
        final pluginPortNames = outputs.map((o) => o.portType.name).join(", ");
        debugPrint('[TtsService] plugin currentRoute outputs: $pluginPortNames');

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
              lastRouteDebug = '';
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
            debugPrint('[TtsService] getDevices found headphone — overriding route.');
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
              lastRouteDebug = '';
              return true;
            }
          }
        } catch (_) {}
        lastRouteDebug = 'only speaker/receiver: $pluginPortNames';
        debugPrint('[TtsService] iOS route only has speaker — BLOCKED!');
        return false;
      }

      // 2. Android 硬件检查（session 已在 iOS 路径前声明）
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
      debugPrint('[TtsService] _queryCurrentRoute error: $e');
    }
    return false;
  }

  String _sanitizeMarkdown(String markdown) {
    String text = markdown;
    text = text.replaceAll(RegExp(r'[#\*_~=]'), '');
    text = text.replaceAll(RegExp(r'^\s*[\-\*\+]\s+', multiLine: true), '，');
    text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '，');
    text = text.replaceAll(RegExp(r'^-{3,}\s*$', multiLine: true), '');
    text = text.replaceAll(RegExp(r'[\|\-\+]+'), ' ');
    text = text.replaceAllMapped(RegExp(r'\[(.*?)\]\(.*?\)'), (match) => match[1] ?? '');
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
            int end = (start + maxChunkSize < sentence.length) ? start + maxChunkSize : sentence.length;
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
  Future<void> prefetchEnglish(String text, {String? geminiKey, String? siliconFlowKey}) async {
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
      debugPrint("[TtsPrefetch] English audio already cached: ${cachedFile.path}");
      return;
    }

    try {
      debugPrint("[TtsPrefetch] Silently pre-synthesizing English audio in background...");
      List<int>? synthesizedBytes;

      final effectiveSiliconKey = (siliconFlowKey ?? '').trim();
      final effectiveGeminiKey = (geminiKey ?? '').trim();

      if (effectiveSiliconKey.isNotEmpty) {
        try {
          synthesizedBytes = await _synthesizeWithSiliconFlow(clean, effectiveSiliconKey, textHash);
        } catch (e) {
          debugPrint("[TtsPrefetch] SiliconFlow prefetch error: $e");
        }
      }

      if ((synthesizedBytes == null || synthesizedBytes.isEmpty) && effectiveGeminiKey.isNotEmpty) {
        try {
          synthesizedBytes = await _synthesizeWithGemini(clean, effectiveGeminiKey);
        } catch (e) {
          debugPrint("[TtsPrefetch] Gemini prefetch error: $e");
        }
      }

      if (synthesizedBytes == null || synthesizedBytes.isEmpty) {
        synthesizedBytes = await _synthesizeWithEdgeNeural(clean);
      }

      if (synthesizedBytes.isNotEmpty) {
        await cachedFile.writeAsBytes(synthesizedBytes);
        debugPrint("[TtsPrefetch] English audio successfully pre-fetched to disk cache!");
      }
    } catch (e) {
      debugPrint("[TtsPrefetch] Background prefetch failed: $e");
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // 🇨🇳 中文朗读接口（方案 1: iOS 本地原生 / 方案 2: 微软 Edge 晓晓神经网络女声）
  // ════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════
  // 🇨🇳 中文朗读接口（方案 1: iOS 本地原生 / 方案 2: 微软 Edge 晓晓神经网络女声）
  // ════════════════════════════════════════════════════════════════════

  Future<void> speakChinese(String text, {String? geminiKey, String? siliconFlowKey}) async {
    await init();
    await stopAll();
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected())) throw Exception("NoHeadphones | ${lastRouteDebug}");

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
      _chineseNativeDuration = Duration(milliseconds: (estTotalSeconds * 1000).toInt());

      await _flutterTts.stop();
      await _flutterTts.setLanguage("zh-CN");
      await _flutterTts.setSpeechRate(_chineseSpeed * 0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setCompletionHandler(() {
        _isChineseNativePlaying = false;
        _chineseNativeTimer?.cancel();
        _chineseNativePosition = _chineseNativeDuration;
        notifyListeners();
      });

      _chineseNativeTimer?.cancel();
      _chineseNativeTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
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

      await _flutterTts.speak(clean);
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
      debugPrint("[TtsCache] Hit local Chinese neural disk cache: ${cachedFile.path}");
      _currentAudioType = ActiveAudioType.chinese;
      final duration = await _audioPlayer.setFilePath(cachedFile.path);
      globalAudioHandler.setPlaybackMetadata(
        title: _formatLockscreenTitle(clean),
        artist: '中文 · 晓晓神经网络女声',
        duration: duration,
      );
      await _audioPlayer.setSpeed(_chineseSpeed);
      await _audioPlayer.play();
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
        debugPrint("[TtsService] Synthesizing Chinese via Microsoft Edge WebSocket (Xiaoxiao)...");
        synthesizedBytes = await _synthesizeWithEdgeWebSocket(clean, "zh-CN-XiaoxiaoNeural");
      } catch (wsErr) {
        debugPrint("[TtsService] Microsoft Edge WebSocket failed ($wsErr)");
      }

      // 2. 微软 Edge HTTP 代理节点降级
      if (synthesizedBytes == null || synthesizedBytes.isEmpty) {
        try {
          debugPrint("[TtsService] Synthesizing Chinese audio via Microsoft Edge HTTP Proxy...");
          synthesizedBytes = await _synthesizeChineseWithEdge(clean);
        } catch (edgeErr) {
          debugPrint("[TtsService] Chinese Edge Neural HTTP failed ($edgeErr)");
        }
      }

      // 3. 硅基流动（SiliconFlow）第三级备用通道
      final effectiveSiliconKey = (siliconFlowKey ?? '').trim();
      if ((synthesizedBytes == null || synthesizedBytes.isEmpty) && effectiveSiliconKey.isNotEmpty) {
        try {
          debugPrint("[TtsService] Synthesizing Chinese via SiliconFlow CosyVoice...");
          synthesizedBytes = await _synthesizeChineseWithSiliconFlow(clean, effectiveSiliconKey);
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
        await _audioPlayer.play();
        _startHeadphoneMonitor();
        notifyListeners();
        return;
      }

      // 5. 若所有在线 API 均失败或网络断开，平滑回退至 iOS 本地离线原生发音（不爆弹窗，保证 100% 正常播放）
      debugPrint("[TtsService] Online Chinese TTS unavailable, falling back to iOS Native Speech");
      _isChineseSynthesizing = false;
      _currentAudioType = ActiveAudioType.chinese;
      _isChineseNativePlaying = true;
      _chineseNativePosition = Duration.zero;

      final estTotalSeconds = (clean.length / 3.8).clamp(2.0, 600.0);
      _chineseNativeDuration = Duration(milliseconds: (estTotalSeconds * 1000).toInt());

      await _flutterTts.stop();
      await _flutterTts.setLanguage("zh-CN");
      await _flutterTts.setSpeechRate(_chineseSpeed * 0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setCompletionHandler(() {
        _isChineseNativePlaying = false;
        _chineseNativeTimer?.cancel();
        _chineseNativePosition = _chineseNativeDuration;
        notifyListeners();
      });

      _chineseNativeTimer?.cancel();
      _chineseNativeTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
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

      await _flutterTts.speak(clean);
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

  /// 微软 Edge 官方 WebSocket 协议神经网络发音合成
  Future<List<int>> _synthesizeWithEdgeWebSocket(String text, String voiceName) async {
    final chunks = _splitTextIntoChunks(text, maxChunkSize: 350);
    final allAudioBytes = <int>[];

    final token = "6A5AA1D4EAFF4E9FB37E23D68491D6F4";
    final version = "1-143.0.3650.75";

    for (final chunk in chunks) {
      final safeChunk = _escapeXml(chunk);
      final lang = voiceName.startsWith("zh") ? "zh-CN" : "en-US";
      final requestId = md5.convert(utf8.encode(DateTime.now().toIso8601String() + chunk)).toString().replaceAll('-', '');

      // 动态计算微软 Edge Sec-MS-GEC 防盗链 Token (基于 100ns Windows FileTime 时间戳)
      final unixSec = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000);
      var fileTimeTicks = (unixSec + 11644473600) * 10000000;
      fileTimeTicks -= (fileTimeTicks % 3000000000); // 5 分钟向上取整对齐

      final strToHash = "${fileTimeTicks.toStringAsFixed(0)}$token";
      final secMsGec = sha256.convert(utf8.encode(strToHash)).toString().toUpperCase();

      final wsUrl = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=$token&Sec-MS-GEC=$secMsGec&Sec-MS-GEC-Version=$version";

      final client = HttpClient();
      client.userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0";

      final random = Random();
      final muid = List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join().toUpperCase();

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

      socket.listen((data) {
        if (data is List<int> && data.length > 2) {
          final headerLength = (data[0] << 8) | data[1];
          if (data.length >= 2 + headerLength) {
            final headerStr = utf8.decode(data.sublist(2, 2 + headerLength), allowMalformed: true);
            if (headerStr.contains("Path:audio")) {
              chunkBytes.addAll(data.sublist(2 + headerLength));
            }
          }
        } else if (data is String) {
          if (data.contains("Path:turn.end")) {
            if (!completer.isCompleted) completer.complete();
          }
        }
      }, onError: (err) {
        if (!completer.isCompleted) completer.completeError(err);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete();
      });

      final configFrame =
          "Content-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n"
          '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
      socket.add(configFrame);

      final ssmlFrame =
          "X-RequestId:$requestId\r\nContent-Type:application/ssml+xml\r\nPath:ssml\r\n\r\n"
          "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xmlns:mstts='http://www.w3.org/2001/mstts' xml:lang='$lang'><voice name='$voiceName'><prosody pitch='+0Hz' rate='+0%'>$safeChunk</prosody></voice></speak>";
      socket.add(ssmlFrame);

      await completer.future.timeout(const Duration(seconds: 45), onTimeout: () {
        socket.close();
        throw TimeoutException('Edge WebSocket chunk timeout after 45s');
      });

      await socket.close();

      if (chunkBytes.isNotEmpty) {
        allAudioBytes.addAll(chunkBytes);
      } else {
        throw Exception("Edge WebSocket chunk returned empty audio");
      }
    }

    if (allAudioBytes.isEmpty) throw Exception("Edge WebSocket returned empty audio");
    return allAudioBytes;
  }

  /// 微软 Edge 晓晓中文神经网络播音女声 HTTP 备用
  Future<List<int>> _synthesizeChineseWithEdge(String text) async {
    final chunks = _splitTextIntoChunks(text, maxChunkSize: 600);
    final allMp3Bytes = <int>[];

    for (final chunk in chunks) {
      // 1. Public Edge TTS Proxy Endpoint 1
      try {
        final url2 = Uri.parse("https://edge-tts.duti.tech/api/tts");
        final resp2 = await http.post(
          url2,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "text": chunk,
            "voice": "zh-CN-XiaoxiaoNeural",
          }),
        ).timeout(const Duration(seconds: 15));

        if (resp2.statusCode == 200 && resp2.bodyBytes.isNotEmpty) {
          allMp3Bytes.addAll(resp2.bodyBytes);
          continue;
        }
      } catch (_) {}

      // 2. Public Edge TTS Proxy Endpoint 2
      try {
        final url3 = Uri.parse("https://tts.m8a.net/api/tts");
        final resp3 = await http.post(
          url3,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "text": chunk,
            "voice": "zh-CN-XiaoxiaoNeural",
          }),
        ).timeout(const Duration(seconds: 15));

        if (resp3.statusCode == 200 && resp3.bodyBytes.isNotEmpty) {
          allMp3Bytes.addAll(resp3.bodyBytes);
          continue;
        }
      } catch (_) {}

      throw Exception("All Edge Chinese endpoints returned empty");
    }

    if (allMp3Bytes.isEmpty) throw Exception("Chinese Edge Neural returned empty data");
    return allMp3Bytes;
  }

  Future<List<int>> _synthesizeChineseWithSiliconFlow(String text, String siliconFlowKey) async {
    final chunks = _splitTextIntoChunks(text, maxChunkSize: 600);
    final allBytes = <int>[];

    for (final chunk in chunks) {
      final url = Uri.parse("https://api.siliconflow.cn/v1/audio/speech");

      // 1. 优先使用 SiliconFlow 的 24kHz 中文神经网络晓晓女声 (speech:zh-CN-XiaoxiaoNeural)
      var response = await http.post(
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
      ).timeout(const Duration(seconds: 20));

      // 2. 若专有模型未提供，使用 CosyVoice 24kHz 高级双语女声 Bella 兜底
      if (response.statusCode != 200) {
        response = await http.post(
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
        ).timeout(const Duration(seconds: 20));
      }

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        allBytes.addAll(response.bodyBytes);
      } else {
        throw Exception("SiliconFlow Chinese HTTP ${response.statusCode}");
      }
    }

    if (allBytes.isEmpty) throw Exception("SiliconFlow Chinese returned empty data");
    return allBytes;
  }

  Future<void> playChinese() async {
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected())) throw Exception("NoHeadphones | ${lastRouteDebug}");
    WakelockService.enable();
    _currentAudioType = ActiveAudioType.chinese;
    if (_isChineseNativePlaying || (_chineseNativePosition > Duration.zero && _chineseNativeDuration > Duration.zero)) {
      // 原生 TTS 履复：重新启动 timer，位置保持不变
      _isChineseNativePlaying = true;
      _chineseNativeTimer?.cancel();
      _chineseNativeTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
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
      // flutter_tts iOS 支持 pause/continue，timer 重启即恢复进度条
      // 注：flutter_tts 在 iOS 上 pause() 后可通过 speak() 同一文本继续（iOS 原生支持）
      notifyListeners();
    } else {
      // 普通 _audioPlayer 模式（微软合成音频）
      await _audioPlayer.play();
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
  }

  Future<void> seekChinese(Duration position) async {
    if (_isChineseNativePlaying ||
        (_chineseNativePosition > Duration.zero && _chineseNativeDuration > Duration.zero)) {
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
    await init();
    await stopAll();
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected())) throw Exception("NoHeadphones | ${lastRouteDebug}");

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
    await _audioPlayer.setLoopMode(_isLoopMode ? LoopMode.one : LoopMode.off);
    await _audioPlayer.play();
    _startHeadphoneMonitor();
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════
  // 🇬🇧 英文 AI 拟真音色朗读接口（SiliconFlow AI + 2级缓存降级方案）
  // ════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════
  // 🇬🇧 英文 AI 拟真音色朗读接口（Gemini 2.0 Flash 原生 API + 硅基流动降级方案）
  // ════════════════════════════════════════════════════════════════════

  Future<void> speakEnglish(String text, {String? geminiKey, String? siliconFlowKey}) async {
    await init();
    await stopAll();
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected())) throw Exception("NoHeadphones | ${lastRouteDebug}");

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
                  (name.contains("Samantha") || name.contains("Ava") || name.contains("Karen") || name.contains("Allison"))) {
                await _flutterTts.setVoice({"name": name, "locale": locale});
                break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint("[TtsService] Voice selection fallback: $e");
      }

      await _flutterTts.speak(clean);
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
      await _audioPlayer.setLoopMode(_isLoopMode ? LoopMode.one : LoopMode.off);
      await _audioPlayer.play();
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
        debugPrint("[TtsService] Synthesizing English audio via Microsoft Edge WebSocket (Jenny)...");
        synthesizedBytes = await _synthesizeWithEdgeWebSocket(clean, "en-US-JennyNeural");
      } catch (wsErr) {
        debugPrint("[TtsService] English Edge WebSocket failed ($wsErr)");
      }

      // 2. 微软 Edge HTTP 降级方案
      if (synthesizedBytes == null || synthesizedBytes.isEmpty) {
        try {
          debugPrint("[TtsService] Synthesizing audio via Microsoft Edge Neural HTTP...");
          synthesizedBytes = await _synthesizeWithEdgeNeural(clean);
        } catch (e) {
          debugPrint("[TtsService] Edge Neural HTTP failed: $e");
        }
      }

      // 3. 若配置了 SiliconFlow Key，备用尝试 24kHz 播音级女声 Bella
      if ((synthesizedBytes == null || synthesizedBytes.isEmpty) && effectiveSiliconKey.isNotEmpty) {
        try {
          debugPrint("[TtsService] Synthesizing audio via SiliconFlow Bella Female Voice...");
          synthesizedBytes = await _synthesizeWithSiliconFlow(clean, effectiveSiliconKey, textHash);
        } catch (e) {
          debugPrint("[TtsService] SiliconFlow Bella failed: $e");
        }
      }

      // 4. 若配置了 Gemini Key，备用尝试 Google 官方播音女声
      if ((synthesizedBytes == null || synthesizedBytes.isEmpty) && effectiveGeminiKey.isNotEmpty) {
        try {
          debugPrint("[TtsService] Synthesizing audio via Google API...");
          synthesizedBytes = await _synthesizeWithGemini(clean, effectiveGeminiKey);
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
        await _audioPlayer.setLoopMode(_isLoopMode ? LoopMode.one : LoopMode.off);
        await _audioPlayer.play();
        _startHeadphoneMonitor();
        notifyListeners();
        return;
      } else {
        throw Exception("All online neural TTS endpoints returned empty");
      }
    } catch (e) {
      debugPrint("[TtsService] All online neural TTS failed ($e). Fallback to iOS Native Speech.");
      _isEnglishSynthesizing = false;
      notifyListeners();

      // 4. 终极离线兜底：使用 iPhone 芯片内置的 iOS 原生英文女声（保障断网/无信号时 100% 依然可播放）
      _currentAudioType = ActiveAudioType.english;
      await _flutterTts.stop();
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(_englishSpeed * 0.5);
      await _flutterTts.speak(clean);
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
          final resp = await http.post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "text": chunk,
              "voice": "en-US-JennyNeural",
            }),
          ).timeout(const Duration(seconds: 15));
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
          final resp = await http.post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "text": chunk,
              "voice": "en-US-JennyNeural",
            }),
          ).timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            allMp3Bytes.addAll(resp.bodyBytes);
            chunkOk = true;
          }
        } catch (_) {}
      }

      // 3. 微软官方 Bing TTS API 兜底
      if (!chunkOk) {
        try {
          final fallbackUrl = Uri.parse("https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/single/tts?api-key=6A5AA1D4EA63472594685157EF9E74B3");
          final fallbackResp = await http.post(
            fallbackUrl,
            headers: {
              "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0",
              "Content-Type": "application/ssml+xml",
              "X-Microsoft-OutputFormat": "audio-24khz-48kbitrate-mono-mp3",
            },
            body: utf8.encode(
              "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
              "<voice name='en-US-JennyNeural'>"
              "<prosody pitch='+0Hz' rate='+0%'>$chunk</prosody>"
              "</voice></speak>",
            ),
          ).timeout(const Duration(seconds: 25));
          if (fallbackResp.statusCode == 200 && fallbackResp.bodyBytes.isNotEmpty) {
            allMp3Bytes.addAll(fallbackResp.bodyBytes);
            chunkOk = true;
          }
        } catch (_) {}
      }

      if (!chunkOk) {
        throw Exception("All Edge English endpoints returned empty");
      }
    }

    if (allMp3Bytes.isEmpty) throw Exception("Edge Neural English returned empty data");
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
      for (final modality in [["AUDIO"], ["audio"]]) {
        if (chunkSuccess) break;
        try {
          final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${geminiKey.trim()}");
          final response = await http.post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "contents": [
                {
                  "parts": [
                    {
                      "text": "Read the following English text aloud clearly, fluently, and naturally with realistic intonation:\n\n$chunk"
                    }
                  ]
                }
              ],
              "generationConfig": {
                "responseModalities": modality,
                "speechConfig": {
                  "voiceConfig": {
                    "prebuiltVoiceConfig": {
                      "voiceName": "Aoede" // 优美清晰的 Studio 级原声女音色
                    }
                  }
                }
              }
            }),
          ).timeout(const Duration(seconds: 35));

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
            lastError = "Gemini API (${response.statusCode}): ${errJson['error']?['message'] ?? response.body}";
          }
        } catch (e) {
          lastError = e.toString();
        }
      }

      // 尝试 2：使用 Google Cloud TTS API (Studio-O / Journey 级原生优美英文女声)
      if (!chunkSuccess) {
        try {
          final ttsUrl = Uri.parse("https://texttospeech.googleapis.com/v1/text:synthesize?key=${geminiKey.trim()}");
          final ttsResponse = await http.post(
            ttsUrl,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "input": {"text": chunk},
              "voice": {
                "languageCode": "en-US",
                "name": "en-US-Studio-O" // Google 官方最高阶 Studio 播音级女声
              },
              "audioConfig": {
                "audioEncoding": "MP3"
              }
            }),
          ).timeout(const Duration(seconds: 35));

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
    if (allAudioBytes.length > 4 && allAudioBytes[0] == 0xFF && (allAudioBytes[1] & 0xE0) == 0xE0) {
      return allAudioBytes;
    }
    return _addWavHeader(allAudioBytes, sampleRate: 24000);
  }

  /// 硅基流动 API 备用合成方案
  Future<List<int>> _synthesizeWithSiliconFlow(String text, String siliconFlowKey, String textHash) async {
    final chunks = _splitTextIntoChunks(text, maxChunkSize: 800);
    final chunkBytesList = <List<int>>[];

    for (int i = 0; i < chunks.length; i++) {
      final url = Uri.parse("https://api.siliconflow.cn/v1/audio/speech");
      final response = await http.post(
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
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        chunkBytesList.add(response.bodyBytes);
      } else {
        final errBody = response.body.length > 300 ? response.body.substring(0, 300) : response.body;
        throw Exception("SiliconFlow API 错误 (HTTP ${response.statusCode}): $errBody");
      }
    }

    final combined = <int>[];
    for (final bytes in chunkBytesList) {
      combined.addAll(bytes);
    }
    return combined;
  }

  /// 构建标准的 44 字节 PCM WAV 头文件
  List<int> _addWavHeader(List<int> pcmBytes, {int sampleRate = 24000, int channels = 1, int bitsPerSample = 16}) {
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
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
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
    await ensurePlaybackSession();
    await Future.delayed(const Duration(milliseconds: 300));
    if (!(await isHeadphonesConnected())) throw Exception("NoHeadphones | ${lastRouteDebug}");
    _currentAudioType = ActiveAudioType.english;
    await _audioPlayer.play();
    _startHeadphoneMonitor();
  }

  Future<void> pauseEnglish() async {
    await _flutterTts.stop();
    await _audioPlayer.pause();
    notifyListeners();
  }

  Future<void> stopEnglish() async {
    await _flutterTts.stop();
    if (_currentAudioType == ActiveAudioType.english || _currentAudioType == ActiveAudioType.recorded) {
      await _audioPlayer.stop();
      _currentAudioType = ActiveAudioType.none;
      globalAudioHandler.setPlaybackMetadata(
        title: 'Jeff Notes',
        artist: '播放已停止',
      );
      notifyListeners();
    }
  }

  Future<void> seekEnglish(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<void> setEnglishSpeed(double speed) async {
    _englishSpeed = speed;
    if (_currentAudioType == ActiveAudioType.english || _currentAudioType == ActiveAudioType.recorded) {
      await _audioPlayer.setSpeed(speed);
    }
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════
  // 通用控制
  // ════════════════════════════════════════════════════════════════════

  Future<void> pauseAll() async {
    _isChineseNativePlaying = false;
    _chineseNativeTimer?.cancel();
    _stopHeadphoneMonitor();
    await _flutterTts.pause();
    await _audioPlayer.pause();
    notifyListeners();
  }

  Future<void> stopAll() async {
    WakelockService.disable();
    _isChineseNativePlaying = false;
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
    await stopAll(); // 停止播放 + 释放 setActive(false)
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      ));
      await session.setActive(true); // 重新激活，解除麦克风静音
      debugPrint('[TtsService] Session released and re-activated for recording');
    } catch (e) {
      debugPrint('[TtsService] releaseForRecording session error: $e');
    }
  }

  Future<void> speak(String text, {String? siliconFlowKey}) async {
    if (siliconFlowKey != null && siliconFlowKey.isNotEmpty) {
      await speakEnglish(text, siliconFlowKey: siliconFlowKey);
    } else {
      await speakChinese(text);
    }
  }

  Future<void> stop() => stopAll();

  // ── Supabase 云端 Audio Cache 辅助函数 ──────────────────────────

  Future<void> _tryFetchFromSupabaseCloud(File targetFile, String textHash) async {
    try {
      final fileName = 'english_$textHash.mp3';
      final bytes = await SupabaseConfig.client.storage
          .from('tts_audio')
          .download(fileName)
          .timeout(const Duration(seconds: 10));
      if (bytes.isNotEmpty) {
        await targetFile.writeAsBytes(bytes);
        debugPrint("[TtsCache] Fetched audio from Supabase cloud: $fileName");
      }
    } catch (e) {
      debugPrint("[TtsCache] Cloud cache miss: $e");
    }
  }

  Future<void> _tryUploadToSupabaseCloud(File file, String textHash) async {
    try {
      final fileName = 'english_$textHash.mp3';
      await SupabaseConfig.client.storage.from('tts_audio').upload(
            fileName,
            file,
            fileOptions: const FileOptions(cacheControl: '3600000', upsert: true),
          );
      debugPrint("[TtsCache] Uploaded synthesized audio to Supabase cloud: $fileName");
    } catch (e) {
      debugPrint("[TtsCache] Cloud upload skipped/error: $e");
    }
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    _audioPlayer.dispose();
    _flutterTts.stop();
    super.dispose();
  }
}
