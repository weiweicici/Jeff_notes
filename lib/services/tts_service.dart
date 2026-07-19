// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import '../main.dart';

enum ActiveAudioType { none, chinese, english, recorded }

class TtsService extends ChangeNotifier {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;

  AudioPlayer get _audioPlayer => globalAudioHandler.player;
  final FlutterTts _flutterTts = FlutterTts();

  bool _isInitialized = false;
  ActiveAudioType _currentAudioType = ActiveAudioType.none;

  ActiveAudioType get currentAudioType => _currentAudioType;

  // ── 中文本地原生 TTS 状态 ──────────────────────────
  bool _isChineseSynthesizing = false;
  double _chineseSpeed = 1.25;
  bool get isChineseSynthesizing => _isChineseSynthesizing;
  bool get isChinesePlaying => _audioPlayer.playing && _currentAudioType == ActiveAudioType.chinese;
  double get chineseSpeed => _chineseSpeed;

  Stream<Duration> get chinesePositionStream => _audioPlayer.positionStream;
  Stream<Duration?> get chineseDurationStream => _audioPlayer.durationStream;

  // ── 英文 AI 拟真音色 TTS 状态 ─────────────────────
  bool _isEnglishSynthesizing = false;
  double _englishSpeed = 1.0;
  bool get isEnglishSynthesizing => _isEnglishSynthesizing;
  bool get isEnglishPlaying => _audioPlayer.playing && (_currentAudioType == ActiveAudioType.english || _currentAudioType == ActiveAudioType.recorded);
  double get englishSpeed => _englishSpeed;

  Stream<Duration> get englishPositionStream => _audioPlayer.positionStream;
  Stream<Duration?> get englishDurationStream => _audioPlayer.durationStream;

  bool get isPlaying => _audioPlayer.playing;
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

  StreamSubscription? _devicesSubscription;
  Timer? _headphoneMonitor;

  void _startHeadphoneMonitor() {
    _stopHeadphoneMonitor();
    _headphoneMonitor = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!isPlaying) {
        _stopHeadphoneMonitor();
        return;
      }
      if (!(await isHeadphonesConnected())) {
        debugPrint('[TtsService] Headphone monitor — lost headphones during playback, pausing.');
        await pauseAll();
      }
    });
  }

  void _stopHeadphoneMonitor() {
    _headphoneMonitor?.cancel();
    _headphoneMonitor = null;
  }

  /// 检查当前是否有耳机/蓝牙连接。
  Future<bool> isHeadphonesConnected() async {
    if (await _queryCurrentRoute()) return true;
    await Future.delayed(const Duration(milliseconds: 200));
    return await _queryCurrentRoute();
  }

  /// 严密检查系统输出路由（只允许耳机/蓝牙输出，坚决禁止扬声器外放）
  Future<bool> _queryCurrentRoute() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      ));
      await session.setActive(true);

      if (Platform.isIOS || Platform.isMacOS) {
        final avSession = AVAudioSession();
        final route = await avSession.currentRoute;
        final outputs = route.outputs;

        debugPrint('[TtsService] iOS currentRoute outputs: ${outputs.map((o) => o.portType.name).join(", ")}');

        if (outputs.isEmpty) {
          try { await session.setActive(false); } catch (_) {}
          return false;
        }

        for (final output in outputs) {
          final t = output.portType;
          if (t != AVAudioSessionPort.builtInSpeaker &&
              t != AVAudioSessionPort.builtInReceiver) {
            return true;
          }
        }

        // 端口全是扬声器或听筒 → 绝对无耳机连接
        try {
          await session.setActive(false);
        } catch (_) {}
        return false;
      }

      // Android: use getDevices()
      final devices = await session.getDevices();
      if (devices.isEmpty) {
        try {
          await session.setActive(false);
        } catch (_) {}
        return false;
      }
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

      try {
        await session.setActive(false);
      } catch (_) {}
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
    text = text.replaceAll(RegExp(r'\n+'), '，');
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

  // ════════════════════════════════════════════════════════════════════
  // 🇨🇳 中文朗读接口（使用 iOS/Android 本地系统 TTS 合成文件 + 2级缓存降级方案）
  // ════════════════════════════════════════════════════════════════════

  Future<void> speakChinese(String text) async {
    await init();
    if (!(await isHeadphonesConnected())) throw Exception("NoHeadphones");

    final clean = _sanitizeMarkdown(text);
    if (clean.isEmpty) return;

    await stopAll();

    // ── 检查本地磁盘 Cache（针对同一文本的 MD5 散列名）──────────────
    final textHash = md5.convert(utf8.encode(clean)).toString();
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory("${docsDir.path}/tts_cache");
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final ext = Platform.isIOS || Platform.isMacOS ? 'caf' : 'wav';
    final cachedFile = File("${cacheDir.path}/chinese_$textHash.$ext");

    // 如果命中了本地缓存，直接毫秒级载入本地文件播放，0秒等待！
    if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
      debugPrint("[TtsCache] Hit local Chinese disk cache: ${cachedFile.path}");
      _currentAudioType = ActiveAudioType.chinese;
      final duration = await _audioPlayer.setFilePath(cachedFile.path);
      globalAudioHandler.setPlaybackMetadata(
        title: '中文大意 (本地缓存)',
        artist: 'Jeff Notes',
        duration: duration,
      );
      await _audioPlayer.setSpeed(_chineseSpeed);
      await _audioPlayer.play();
      _startHeadphoneMonitor();
      notifyListeners();
      return;
    }

    // ── 检查 Supabase 云端 Cache（跨设备共享缓存）───
    await _tryFetchFromSupabaseCloud(cachedFile, textHash);
    if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
      debugPrint("[TtsCache] Hit Supabase Cloud Chinese Cache: ${cachedFile.path}");
      _currentAudioType = ActiveAudioType.chinese;
      final duration = await _audioPlayer.setFilePath(cachedFile.path);
      globalAudioHandler.setPlaybackMetadata(
        title: '中文大意 (云端缓存)',
        artist: 'Jeff Notes',
        duration: duration,
      );
      await _audioPlayer.setSpeed(_chineseSpeed);
      await _audioPlayer.play();
      _startHeadphoneMonitor();
      notifyListeners();
      return;
    }

    // ── 未命中缓存：本地调用 FlutterTts 原生合成文件 ──────────────
    try {
      _isChineseSynthesizing = true;
      notifyListeners();

      await _flutterTts.setSharedInstance(true);
      await _flutterTts.setLanguage("zh-CN");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      await _flutterTts.synthesizeToFile(clean, cachedFile.path, true);

      if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
        debugPrint("[TtsCache] Saved synthesized Chinese audio to local cache: ${cachedFile.path}");

        // 异步在后台静默保存一份到 Supabase Storage 云端（全网用户共享缓存）
        _tryUploadToSupabaseCloud(cachedFile, textHash);

        _isChineseSynthesizing = false;
        _currentAudioType = ActiveAudioType.chinese;

        final duration = await _audioPlayer.setFilePath(cachedFile.path);
        globalAudioHandler.setPlaybackMetadata(
          title: '中文大意',
          artist: 'Jeff Notes',
          duration: duration,
        );
        await _audioPlayer.setSpeed(_chineseSpeed);
        await _audioPlayer.play();
        _startHeadphoneMonitor();
        notifyListeners();
        return;
      } else {
        throw Exception("中文语音合成输出文件失败");
      }
    } catch (e) {
      debugPrint("[TtsService] synthesizeToFile failed ($e), falling back to live TTS speak");
      _isChineseSynthesizing = false;
      notifyListeners();

      // 降级无缝兜底：如果系统环境不支持文件合成，自动回退至 live speak，绝不打断用户或弹出 OSStatus 错误
      _currentAudioType = ActiveAudioType.chinese;
      await _flutterTts.stop();
      await _flutterTts.setLanguage("zh-CN");
      await _flutterTts.setSpeechRate(_chineseSpeed * 0.5);
      await _flutterTts.speak(clean);
      _startHeadphoneMonitor();
      notifyListeners();
    } finally {
      _isChineseSynthesizing = false;
      notifyListeners();
    }
  }

  Future<void> playChinese() async {
    if (!(await isHeadphonesConnected())) throw Exception("NoHeadphones");
    _currentAudioType = ActiveAudioType.chinese;
    await _audioPlayer.play();
    _startHeadphoneMonitor();
  }

  Future<void> pauseChinese() async {
    await _audioPlayer.pause();
    notifyListeners();
  }

  Future<void> stopChinese() async {
    if (_currentAudioType == ActiveAudioType.chinese) {
      await _audioPlayer.stop();
      _currentAudioType = ActiveAudioType.none;
      notifyListeners();
    }
  }

  Future<void> seekChinese(Duration position) async {
    await _audioPlayer.seek(position);
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
    if (!(await isHeadphonesConnected())) throw Exception("NoHeadphones");

    await stopAll();

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
    await _audioPlayer.play();
    _startHeadphoneMonitor();
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════════
  // 🇬🇧 英文 AI 拟真音色朗读接口（SiliconFlow AI + 2级缓存降级方案）
  // ════════════════════════════════════════════════════════════════════

  Future<void> speakEnglish(String text, {required String siliconFlowKey}) async {
    await init();
    if (!(await isHeadphonesConnected())) throw Exception("NoHeadphones");

    final clean = _sanitizeMarkdown(text);
    if (clean.isEmpty) return;

    await stopAll();

    // ── 检查本地磁盘 Cache（针对同一文本的 MD5 散列名）──────────────
    final textHash = md5.convert(utf8.encode(clean)).toString();
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory("${docsDir.path}/tts_cache");
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    final cachedFile = File("${cacheDir.path}/english_$textHash.mp3");

    // 如果命中了本地缓存，直接毫秒级载入本地文件播放，0秒等待 & 0消耗 Token！
    if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
      debugPrint("[TtsCache] Hit local disk cache: ${cachedFile.path}");
      _currentAudioType = ActiveAudioType.english;
      final duration = await _audioPlayer.setFilePath(cachedFile.path);
      globalAudioHandler.setPlaybackMetadata(
        title: '英文听力原声 (本地缓存)',
        artist: 'Jeff Notes AI',
        duration: duration,
      );
      await _audioPlayer.setSpeed(_englishSpeed);
      await _audioPlayer.play();
      _startHeadphoneMonitor();
      notifyListeners();
      return;
    }

    // ── 检查 Supabase 云端 Cache（跨设备共享缓存，0 API Token 消耗）───
    await _tryFetchFromSupabaseCloud(cachedFile, textHash);
    if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
      debugPrint("[TtsCache] Hit Supabase Cloud Cache: ${cachedFile.path}");
      _currentAudioType = ActiveAudioType.english;
      final duration = await _audioPlayer.setFilePath(cachedFile.path);
      globalAudioHandler.setPlaybackMetadata(
        title: '英文听力原声 (云端缓存)',
        artist: 'Jeff Notes AI',
        duration: duration,
      );
      await _audioPlayer.setSpeed(_englishSpeed);
      await _audioPlayer.play();
      _startHeadphoneMonitor();
      notifyListeners();
      return;
    }

    // ── 未命中缓存：发起 API 语音合成并持久化存入 Cache ──────────────
    if (siliconFlowKey.trim().isEmpty) {
      throw Exception("未配置 SiliconFlow API Key");
    }

    try {
      _isEnglishSynthesizing = true;
      notifyListeners();

      final chunks = _splitTextIntoChunks(clean, maxChunkSize: 800);
      final tempDir = await getTemporaryDirectory();
      final audioSources = <AudioSource>[];
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
            "voice": "FunAudioLLM/CosyVoice2-0.5B:alex",
            "response_format": "mp3",
            "stream": false,
          }),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final file = File("${tempDir.path}/silicon_english_${textHash}_$i.mp3");
          await file.writeAsBytes(response.bodyBytes);
          audioSources.add(AudioSource.file(file.path));
          chunkBytesList.add(response.bodyBytes);
        } else {
          final errBody = response.body.length > 300 ? response.body.substring(0, 300) : response.body;
          throw Exception("SiliconFlow API 错误 (HTTP ${response.statusCode}): $errBody");
        }
      }

      if (audioSources.isEmpty) throw Exception("语音合成失败");

      // 将下载好的所有 Chunk 合并写入本地 Cache 文件，下次即可免请求播放
      final sink = cachedFile.openWrite();
      for (final bytes in chunkBytesList) {
        sink.add(bytes);
      }
      await sink.close();
      debugPrint("[TtsCache] Saved synthesized English MP3 to local cache: ${cachedFile.path}");

      // 异步在后台静默保存一份到 Supabase Storage 云端（全网用户共享缓存）
      _tryUploadToSupabaseCloud(cachedFile, textHash);

      _isEnglishSynthesizing = false;
      _currentAudioType = ActiveAudioType.english;

      final duration = await _audioPlayer.setFilePath(cachedFile.path);
      globalAudioHandler.setPlaybackMetadata(
        title: '英文听力原声',
        artist: 'Jeff Notes AI',
        duration: duration,
      );
      await _audioPlayer.setSpeed(_englishSpeed);
      await _audioPlayer.play();
      _startHeadphoneMonitor();
      notifyListeners();
    } catch (e) {
      _isEnglishSynthesizing = false;
      notifyListeners();
      rethrow;
    } finally {
      _isEnglishSynthesizing = false;
      notifyListeners();
    }
  }

  Future<void> playEnglish() async {
    if (!(await isHeadphonesConnected())) throw Exception("NoHeadphones");
    _currentAudioType = ActiveAudioType.english;
    await _audioPlayer.play();
    _startHeadphoneMonitor();
  }

  Future<void> pauseEnglish() async {
    await _audioPlayer.pause();
    notifyListeners();
  }

  Future<void> stopEnglish() async {
    if (_currentAudioType == ActiveAudioType.english || _currentAudioType == ActiveAudioType.recorded) {
      await _audioPlayer.stop();
      _currentAudioType = ActiveAudioType.none;
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
    _stopHeadphoneMonitor();
    await _flutterTts.pause();
    await _audioPlayer.pause();
    notifyListeners();
  }

  Future<void> stopAll() async {
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
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
                                       AVAudioSessionCategoryOptions.allowBluetooth |
                                       AVAudioSessionCategoryOptions.allowBluetoothA2dp,
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
