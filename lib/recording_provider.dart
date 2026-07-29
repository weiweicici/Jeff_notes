import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'services/supabase_config.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'openai_service.dart';
import 'ai_orchestrator_service.dart';
import 'api_scheduler.dart';
import 'models.dart';  // 包含 AppMode 枚举
import 'prompt_provider.dart';  // 单元词汇高亮列表
import 'services/tts_service.dart';  // 录音前释放音频会话

class InsightNote {
  final String id;
  String summary;
  String transcript;
  String? translatedContent;
  final DateTime timestamp;
  bool isProcessing;
  final String? clusterId;
  final bool isSummary;

  InsightNote({
    String? id,
    required this.summary,
    required this.transcript,
    this.translatedContent,
    required this.timestamp,
    this.isProcessing = false,
    this.clusterId,
    this.isSummary = false,
  }) : id = id ?? "note_${DateTime.now().microsecondsSinceEpoch}_${transcript.hashCode}";

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'transcript': transcript,
    'translatedContent': translatedContent,
    'timestamp': timestamp.toIso8601String(),
    'clusterId': clusterId,
    'isSummary': isSummary,
  };

  factory InsightNote.fromJson(Map<String, dynamic> json) => InsightNote(
    summary: json['summary'],
    transcript: json['transcript'],
    translatedContent: json['translatedContent'],
    timestamp: DateTime.parse(json['timestamp']),
    clusterId: json['clusterId'],
    isSummary: json['isSummary'] ?? false,
  );
}


class StitchData {
  final Uint8List tail;
  final String path;
  final int tailSize;
  StitchData(this.tail, this.path, this.tailSize);
}

int _findDataChunkOffset(Uint8List bytes) {
  if (bytes.length < 12) return 44;
  if (bytes[0] != 0x52 || bytes[1] != 0x49 || bytes[2] != 0x46 || bytes[3] != 0x46) return 44; // "RIFF"
  if (bytes[8] != 0x57 || bytes[9] != 0x41 || bytes[10] != 0x56 || bytes[11] != 0x45) return 44; // "WAVE"
  
  int offset = 12;
  while (offset + 8 <= bytes.length) {
    final c0 = bytes[offset];
    final c1 = bytes[offset + 1];
    final c2 = bytes[offset + 2];
    final c3 = bytes[offset + 3];
    
    // Check if it is "data" chunk
    if (c0 == 0x64 && c1 == 0x61 && c2 == 0x74 && c3 == 0x61) {
      return offset + 8;
    }
    
    final chunkSize = bytes[offset + 4] | 
                    (bytes[offset + 5] << 8) | 
                    (bytes[offset + 6] << 16) | 
                    (bytes[offset + 7] << 24);
    offset += 8 + chunkSize;
  }
  return 44;
}

Future<Map<String, dynamic>> _backgroundStitchTask(StitchData data) async {
  try {
    final currentFile = File(data.path);
    if (!currentFile.existsSync()) return {'path': data.path, 'newTail': data.tail};
    final currentBytes = await currentFile.readAsBytes();
    
    final dataOffset = _findDataChunkOffset(currentBytes);
    
    if (currentBytes.length < dataOffset) return {'path': data.path, 'newTail': data.tail};
    final currentPcm = currentBytes.sublist(dataOffset);
    final List<int> combinedPcm = [...data.tail, ...currentPcm];
    final header = _generateWavHeaderStatic(combinedPcm.length);
    final stitchedBytes = Uint8List.fromList([...header, ...combinedPcm]);
    final stitchedPath = "${data.path}_stitched.wav";
    await File(stitchedPath).writeAsBytes(stitchedBytes);
    Uint8List nextTail = Uint8List(0);
    if (currentBytes.length > data.tailSize + dataOffset) {
      nextTail = currentBytes.sublist(currentBytes.length - data.tailSize);
    }
    return {'path': stitchedPath, 'newTail': nextTail};
  } catch (e) {
    return {'path': data.path, 'newTail': data.tail};
  }
}

Uint8List _generateWavHeaderStatic(int pcmLength) {
  final header = ByteData(44);
  
  // RIFF identifier
  header.setUint8(0, 0x52); header.setUint8(1, 0x49); header.setUint8(2, 0x46); header.setUint8(3, 0x46); // "RIFF"
  header.setUint32(4, 36 + pcmLength, Endian.little); // File size - 8
  
  // WAVE identifier
  header.setUint8(8, 0x57); header.setUint8(9, 0x41); header.setUint8(10, 0x56); header.setUint8(11, 0x45); // "WAVE"
  
  // fmt chunk
  header.setUint8(12, 0x66); header.setUint8(13, 0x6D); header.setUint8(14, 0x74); header.setUint8(15, 0x20); // "fmt "
  header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
  header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
  header.setUint16(22, 1, Endian.little); // NumChannels (1 for Mono)
  header.setUint32(24, 16000, Endian.little); // SampleRate (16kHz)
  header.setUint32(28, 16000 * 2, Endian.little); // ByteRate (SampleRate * 2)
  header.setUint16(32, 2, Endian.little); // BlockAlign (Channels * 2)
  header.setUint16(34, 16, Endian.little); // BitsPerSample (16-bit)
  
  // data chunk
  header.setUint8(36, 0x64); header.setUint8(37, 0x61); header.setUint8(38, 0x74); header.setUint8(39, 0x61); // "data"
  header.setUint32(40, pcmLength, Endian.little); // Subchunk2Size
  
  return header.buffer.asUint8List();
}

class RecordingProvider extends ChangeNotifier {
  final AudioRecorder _audioRecorder = AudioRecorder();
  OpenAIService? _aiService;
  OpenAIService? _fastAiService;
  OpenAIService? _groqService;
  OpenAIService? _fallbackTranslationService;
  AIOrchestratorService? _orchestrator;
  final StreamController<String> _sessionReadyController = StreamController<String>.broadcast();

  
  StreamSubscription? _fastSub;
  StreamSubscription? _accurateSub;
  
  AIProvider _selectedProvider = AIProvider.groq;
  int _sliceDuration = 5;
  bool _isDarkMode = false;
  bool _enableFinalRecap = false;
  bool _enableLectureDiscovery = false;
  AppMode _currentMode = AppMode.exam;
  PathwaysUnit _currentUnit = PathwaysUnit.none;
  int _autoScrollPauseDuration = 60;
  
  final Map<AIProvider, String> _apiKeys = {
    AIProvider.siliconFlow: "",
    AIProvider.groq: "",
    AIProvider.gemini: "",
  };

  
  String? _lastTranscript;
  Uint8List _lastAudioTail = Uint8List(0);
  Timer? _sliceTimer;
  bool _isRecording = false;
  bool _isPaused = false;   // 暂停录音标志（仅在 _isRecording=true 时有意义）
  bool _isPending = false;
  static const int kTailSize = 25600;

  final List<InsightNote> _allNotes = [];
  String? _statusMessage;

  String? _finalReviewContent;
  bool _isGeneratingFinalReview = false;
  String? _lastExportedPath;
  // 40秒分段 AI 摘要
  int _segmentSummaryCounter = 0;
  final List<String> _segmentTranscriptBuffer = [];
  final List<String> _segmentSummaries = [];
  bool _isGeneratingSegmentSummary = false;
  static const int _kSlicesPerSegment = 8; // 8 * 5s = 40s
  String? _identifiedLectureContext;
  bool _hasRecoveredCache = false;
  String _openRouterKey = '';
  final List<String> _sessionAudioPaths = []; // 保存当次 session 所有录音切片路径

  List<InsightNote> get notes => _allNotes.reversed.toList();
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get isPending => _isPending;
  AIProvider get selectedProvider => _selectedProvider;
  int get sliceDuration => _sliceDuration;
  bool get isDarkMode => _isDarkMode;
  bool get enableFinalRecap => _enableFinalRecap;
  bool get enableLectureDiscovery => _enableLectureDiscovery;
  AppMode get currentMode => _currentMode;
  PathwaysUnit get currentUnit => _currentUnit;
  int get autoScrollPauseDuration => _autoScrollPauseDuration;
  String? get statusMessage => _statusMessage;
  String? get finalReviewContent => _finalReviewContent;
  bool get isGeneratingFinalReview => _isGeneratingFinalReview;
  String? get lastExportedPath => _lastExportedPath;
  String? get identifiedLectureContext => _identifiedLectureContext;
  bool get hasRecoveredCache => _hasRecoveredCache;
  
  // 添加缺失的getter方法
  Stream<String> get sessionReadyStream => _sessionReadyController.stream;
  AppMode get appMode => currentMode;
  AppMode get currentSessionMode => currentMode;

  String get groqKey => _apiKeys[AIProvider.groq] ?? '';
  String get siliconFlowKey => _apiKeys[AIProvider.siliconFlow] ?? '';
  String get geminiKey => _apiKeys[AIProvider.gemini] ?? '';
  String get openRouterKey => _openRouterKey;

  String _prevGroqKey = "";


  RecordingProvider() { _init(); }

  Future<void> _init() async {
    await _loadSettings();
    await _initializeAudioSession();
    await _checkRecoveryCache();
  }


  /// Returns clean Chinese + English full transcript for TTS playback.
  /// Only includes actual spoken content — no markdown headers, bullets or AI summaries.
  String get bilingualTtsText {
    final transcripts = _allNotes.where((n) => !n.isSummary).toList();
    if (transcripts.isEmpty) return "";

    final chineseParts = <String>[];
    final englishParts = <String>[];

    for (final note in transcripts) {
      final en = note.transcript.trim();
      if (en.isNotEmpty && en != '...' && !en.startsWith('[')) {
        englishParts.add(en);
      }
      final zh = note.translatedContent?.trim();
      if (zh != null && zh.isNotEmpty && !zh.startsWith('[')) {
        chineseParts.add(zh);
      }
    }

    final buffer = StringBuffer();
    if (chineseParts.isNotEmpty) {
      buffer.write("中文全文：");
      buffer.write(chineseParts.join("。"));
    }
    if (englishParts.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write("  英文全文：");
      buffer.write(englishParts.join(" "));
    }
    return buffer.toString();
  }

    Future<void> updateSettings({
    String? groqKey,
    String? siliconFlowKey,
    String? openRouterKey,
    String? geminiKey,

    int? duration,
    bool? isDarkMode,
    bool? enableFinalRecap,
    bool? enableLectureDiscovery,
    AppMode? mode,
    PathwaysUnit? unit,
    int? autoScrollPauseDuration,

  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (duration != null) {
      final clamped = duration.clamp(5, 8);
      await prefs.setInt('slice_duration', clamped);
      _sliceDuration = clamped;
    }
    if (isDarkMode != null) { await prefs.setBool('is_dark_mode', isDarkMode); _isDarkMode = isDarkMode; }
    if (enableFinalRecap != null) { await prefs.setBool('enableFinalRecap', enableFinalRecap); _enableFinalRecap = enableFinalRecap; }
    if (enableLectureDiscovery != null) { await prefs.setBool('enableLectureDiscovery', enableLectureDiscovery); _enableLectureDiscovery = enableLectureDiscovery; }
    if (mode != null) { await prefs.setInt('app_mode', mode.index); _currentMode = mode; }
    if (unit != null) {
      await prefs.setInt('current_unit', unit.index);
      _currentUnit = unit;
    }
    if (autoScrollPauseDuration != null) {
      await prefs.setInt('autoScrollPauseDuration', autoScrollPauseDuration);
      _autoScrollPauseDuration = autoScrollPauseDuration;
    }
    
    if (groqKey != null) {
      final trimmedKey = groqKey.trim();
      await prefs.setString('api_key_${AIProvider.groq.name}', trimmedKey);
      _apiKeys[AIProvider.groq] = trimmedKey;
      debugPrint("保存 Groq API Key 成功，前几位: ${trimmedKey.isNotEmpty ? trimmedKey.substring(0, trimmedKey.length.clamp(0, 10)) : ''}...");
    }
    if (siliconFlowKey != null) {
      final trimmedKey = siliconFlowKey.trim();
      await prefs.setString('api_key_${AIProvider.siliconFlow.name}', trimmedKey);
      _apiKeys[AIProvider.siliconFlow] = trimmedKey;
      debugPrint("保存 SiliconFlow API Key 成功，前几位: ${trimmedKey.isNotEmpty ? trimmedKey.substring(0, trimmedKey.length.clamp(0, 10)) : ''}...");
    }
    if (geminiKey != null) {
      final trimmedKey = geminiKey.trim();
      await prefs.setString('api_key_${AIProvider.gemini.name}', trimmedKey);
      _apiKeys[AIProvider.gemini] = trimmedKey;
      debugPrint("保存 Gemini API Key 成功，前几位: ${trimmedKey.isNotEmpty ? trimmedKey.substring(0, trimmedKey.length.clamp(0, 10)) : ''}...");
    }
    if (openRouterKey != null) {
      final trimmedKey = openRouterKey.trim();
      await prefs.setString('api_key_openrouter', trimmedKey);
      _openRouterKey = trimmedKey;
      debugPrint("保存 OpenRouter API Key 成功，前几位: ${trimmedKey.isNotEmpty ? trimmedKey.substring(0, trimmedKey.length.clamp(0, 10)) : ''}...");
    }

    _updateService();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _sliceDuration = (prefs.getInt('slice_duration') ?? 5).clamp(5, 8);
    _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    _enableFinalRecap = prefs.getBool('enableFinalRecap') ?? false;
    _enableLectureDiscovery = prefs.getBool('enableLectureDiscovery') ?? false;
    _autoScrollPauseDuration = prefs.getInt('autoScrollPauseDuration') ?? 60;
    final modeIndex = prefs.getInt('app_mode') ?? AppMode.exam.index;
    _currentMode = AppMode.values[modeIndex];
    _currentUnit = PathwaysUnit.values[prefs.getInt('current_unit') ?? 0];
    final pIndex = prefs.getInt('selected_provider') ?? 0;
    _selectedProvider = AIProvider.values[pIndex];
    _openRouterKey = prefs.getString('api_key_openrouter') ?? '';
    for (var p in AIProvider.values) {
      _apiKeys[p] = prefs.getString('api_key_${p.name}') ?? '';
    }
    _updateService();
  }

  void _updateService() {
    final groqKey = _apiKeys[AIProvider.groq] ?? "";
    final groqChanged = groqKey != _prevGroqKey;

    if (!groqChanged && _orchestrator != null) {
      return;
    }

    _fastSub?.cancel();
    _accurateSub?.cancel();
    _orchestrator?.dispose();

    _prevGroqKey = groqKey;

    
    // 1. 初始化 Groq 服务（STT 专用，独立实例避免并发干扰）
    OpenAIService? groqSTT;
    if (groqKey.isNotEmpty) {
      groqSTT = OpenAIService(
        apiKey: groqKey,
        baseUrl: "https://api.groq.com/openai/v1",
        defaultModel: "openai/gpt-oss-120b",
        whisperModel: "whisper-large-v3",
      );
      _groqService = OpenAIService(
        apiKey: groqKey,
        baseUrl: "https://api.groq.com/openai/v1",
        defaultModel: "openai/gpt-oss-120b",
        whisperModel: "whisper-large-v3",
      );
      debugPrint("Groq 服务创建完成 (STT + Chat 各一个独立实例)");
    } else {
      groqSTT = null;
      _groqService = null;
    }

    // 2. 全量服务使用 Groq
    if (_groqService != null) {
      _aiService = _groqService;                      // 翻译/复盘
      _fastAiService = groqSTT;                       // STT 独立实例
      _fallbackTranslationService = _groqService;      // 备用翻译
      debugPrint("全部 AI 服务绑定为: Groq (openai/gpt-oss-120b)");
    } else {
      _aiService = null;
      _fastAiService = null;
      _fallbackTranslationService = null;
      debugPrint("警告：Groq 服务不可用，AI 功能将不可用");
    }
    
    if (_aiService != null && _fastAiService != null) {
      _orchestrator = AIOrchestratorService(
        sttService: _fastAiService!,
        translationService: _aiService!,
        translationFallbackService: _fallbackTranslationService,
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      
      _fastSub = _orchestrator!.fastEnglishStream.listen((result) {
        final index = _allNotes.indexWhere((n) => n.id == result.noteId);
        if (index != -1) {
          _allNotes[index].transcript = result.content;
          if (result.content != "[Silence/Empty]" && !result.content.startsWith("[")) {
            _lastTranscript = result.content;
          }
          notifyListeners();
        }
      });
      
      _accurateSub = _orchestrator!.accurateChineseStream.listen((result) {
        final index = _allNotes.indexWhere((n) => n.id == result.noteId);
        if (index != -1) {
          _allNotes[index].translatedContent = result.content;
          _saveShadowCache();
          notifyListeners();
        }
      });
    }
  }

  Future<void> _initializeAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      ));
      // setActive may fail if another app holds the session; safe to ignore at init
      await session.setActive(true);
    } catch (e) {
      debugPrint('[AudioSession] init setActive failed (will retry on record): $e');
    }
  }

  /// 录音结束后重置会话：先 deactivate 释放麦克风独占，再 reactivate 准备下次录音。
  Future<void> _resetAudioSessionAfterRecording() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
      await Future.delayed(const Duration(milliseconds: 150));
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      ));
      await session.setActive(true);
      debugPrint('[AudioSession] Session reset after recording — ready for next session');
    } catch (e) {
      debugPrint('[AudioSession] resetAfterRecording error: $e');
    }
  }

  Future<void> toggleRecording() async {
    if (_isPending) return;
    _isPending = true; notifyListeners();
    if (_isRecording) await stopRecording(); else await startRecording();
    _isPending = false; notifyListeners();
  }

  Future<void> startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      // 修复 Bug 1: 先停止任何 TTS 播放并重置音频会话，防止麦克风被锁死
      await TtsService().releaseForRecording();
      _updateService();
      if (_orchestrator == null) {
        _statusMessage = "Please configure your API Keys in Settings first";
        notifyListeners();
        return;
      }
      _isRecording = true;
      _isPaused = false;   // 新录音时重置暂停状态
      _lastAudioTail = Uint8List(0);
      _sessionAudioPaths.clear(); // 清空上次 session 的音频切片路径
      _allNotes.clear();
      _lastTranscript = null;
      _segmentSummaryCounter = 0;
      _segmentTranscriptBuffer.clear();
      _segmentSummaries.clear();
      _isGeneratingSegmentSummary = false;

      _finalReviewContent = null;
      _statusMessage = null;
      notifyListeners();
      final path = await _getTempPath();
      await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
      _startSmartSliceTimer();
    }
  }

  void _startSmartSliceTimer() {
    _sliceTimer?.cancel();
    _sliceTimer = Timer.periodic(Duration(seconds: _sliceDuration), (timer) async {
      try {
        if (!_isRecording || _isPaused) { timer.cancel(); return; }
        final path = await _audioRecorder.stop();
        if (path != null) unawaited(_processAudio(path));

        await Future.delayed(const Duration(milliseconds: 100));
        if (_isRecording && !_isPaused) {
          final nextPath = await _getTempPath();
          await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: nextPath);
        }
      } catch (e) {
        debugPrint("Slice timer error: $e");
      }
    });
  }

  Future<void> stopRecording() async {
    _isRecording = false;
    _sliceTimer?.cancel();
    final path = await _audioRecorder.stop();
    if (path != null) await _processAudio(path);
    if (_orchestrator != null) {
      await _orchestrator!.flush(onStatus: (msg) {
        _statusMessage = msg;
        notifyListeners();
      });
    }

    // 闲谈模式无摘要故跳过
    if (_currentMode == AppMode.freeTalk) {
      _statusMessage = "Finalizing free talk...";
      notifyListeners();
      await ApiScheduler().untilIdle();
      await _exportFreeTalkMarkdown();
      if (_lastExportedPath != null) {
        _sessionReadyController.add(_lastExportedPath!);
      }
      await _resetAudioSessionAfterRecording();
      return;
    }

    // 先刷新最后一段未满40秒的缓冲
    if (_segmentTranscriptBuffer.isNotEmpty) {
      await _generateSegmentSummary();
    }
    // 等待后台正在生成的摘要完成
    while (_isGeneratingSegmentSummary) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // ★ 立即用分段摘要组合成即时总结（不等待完整 AI review）
    if (_segmentSummaries.isNotEmpty) {
      _finalReviewContent = _segmentSummaries.join("\n\n");
      _sessionReadyController.add(_finalReviewContent!);
    }

    // 立即导出 MD 文件（含分段摘要），确保存档立即可见
    await _exportToMarkdown();

    // 后台继续生成完整 AI review（不阻塞弹窗），完成后会覆盖更新 MD 文件
    _statusMessage = "Finalizing full AI review...";
    notifyListeners();
    unawaited(_generateFinalReviewInBackground());

    // 修复 Bug 2: 录音结束后重置音频会话，让下次录音可立即开始
    await _resetAudioSessionAfterRecording();
  }

  /// 后台任务：生成完整 AI 总结并导出最终 MD 文件（不阻塞弹窗）
  Future<void> _generateFinalReviewInBackground() async {
    try {
      await ApiScheduler().untilIdle();

      if (_enableFinalRecap) {
        await generateFinalAcademicReview();
        // generateFinalAcademicReview 的 finally 中已调用 _exportToMarkdown，覆盖更新
      } else {
        // _exportToMarkdown 已在 stopRecording() 中同步执行，无需重复
      }

      if (_lastExportedPath != null && _finalReviewContent == null) {
        _sessionReadyController.add(_lastExportedPath!);
      } else if (_finalReviewContent != null) {
        _sessionReadyController.add(_finalReviewContent!);
      }
    } catch (e) {
      debugPrint("[Background Final Review Error] $e");
    }
  }

  /// 暂停录音：停止当前切片计时器和录音器，保留所有已有笔记，不做任何导出。
  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused || _isPending) return;
    _isPaused = true;
    _sliceTimer?.cancel();
    // 处理暂停前的最后一段音频切片
    final path = await _audioRecorder.stop();
    if (path != null) unawaited(_processAudio(path));
    _statusMessage = "⏸ Paused";
    notifyListeners();
  }

  /// 继续录音：重启录音器和切片计时器，无缝衔接上次内容。
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused || _isPending) return;
    _isPaused = false;
    _statusMessage = null;
    final nextPath = await _getTempPath();
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: nextPath,
    );
    _startSmartSliceTimer();
    notifyListeners();
  }

  /// 切换暂停/继续。
  Future<void> togglePause() async {
    if (_isPaused) {
      await resumeRecording();
    } else {
      await pauseRecording();
    }
  }

  Future<String> _getTempPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
  }

  /// 有效性判断：过滤静音/填充词
  bool _isValidTranscript(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty || t == '...') return false;
    final fillerWords = ['嗯', '呃', '那个', 'um', 'uh', 'like', 'so'];
    if (fillerWords.contains(t)) return false;
    return true;
  }

  /// FreeTalk 翻译（使用硅基流动 Qwen）
  Future<String> _translateFreeTalk(String englishText) async {
    // Try Gemini first
    final geminiResult = await _callGemini(
      'You are a professional translator. Translate the following English text to Chinese. Output ONLY the Chinese translation, no explanations.',
      englishText,
    );
    if (geminiResult != null && geminiResult.isNotEmpty && !geminiResult.startsWith('[')) return geminiResult;

    // Fallback: Groq
    try {
      final result = await _translateViaSiliconFlow(englishText)
          .timeout(const Duration(seconds: 10));
      if (result.isNotEmpty && !result.startsWith('[')) return result;
    } catch (e) {
      debugPrint("FreeTalk translation failed: $e");
    }
    return '[Translation failed]';
  }

  /// 硅基流动 Qwen（复用现有翻译能力）
  Future<String> _translateViaSiliconFlow(String text) async {
    if (_aiService == null) throw Exception('SiliconFlow service not ready');
    // 注意：_aiService 的 summarize 方法可能不适合直接翻译，但原架构中使用它做翻译
    // 这里直接调用原翻译逻辑，假设 OpenAIService 提供了 translate 方法。
    // 如果没有，可以临时使用 summarize 并指定 prompt。
    final translation = await _aiService!.translate(text);
    return translation;
  }


  Future<void> _processAudio(String path) async {
    if (_orchestrator == null) return;
    if (path.isEmpty) return;
    try {
      final stitchResult = await compute(_backgroundStitchTask, StitchData(_lastAudioTail, path, kTailSize));
      final processedPath = stitchResult['path'] as String;
      _lastAudioTail = Uint8List.fromList(stitchResult['newTail'] as List<int>);
      _sessionAudioPaths.add(processedPath); // 收集当次 session 切片路径

      final currentNote = InsightNote(summary: '', transcript: '...', timestamp: DateTime.now(), isProcessing: true);
      final noteId = currentNote.id;
      _allNotes.add(currentNote);
      notifyListeners();

      // 提取最近两次的翻译历史作为上下文
      final List<Map<String, String>> historyList = [];
      final List<InsightNote> nonSummaryNotes = _allNotes
          .where((n) => !n.isSummary && 
                        n.transcript.isNotEmpty && 
                        n.transcript != '...' && 
                        n.translatedContent != null && 
                        n.translatedContent!.isNotEmpty &&
                        !n.translatedContent!.startsWith('['))
          .toList();
      
      if (nonSummaryNotes.length >= 2) {
        for (var i = nonSummaryNotes.length - 2; i < nonSummaryNotes.length; i++) {
          historyList.add({
            'english': nonSummaryNotes[i].transcript,
            'chinese': nonSummaryNotes[i].translatedContent!,
          });
        }
      } else if (nonSummaryNotes.isNotEmpty) {
        historyList.add({
          'english': nonSummaryNotes.first.transcript,
          'chinese': nonSummaryNotes.first.translatedContent!,
        });
      }

      await _orchestrator!.processAudioSegment(
        noteId,
        processedPath,
        context: _lastTranscript,
        translationHistory: historyList,
        onStatus: (msg) {
          _statusMessage = msg;
          notifyListeners();
        },
      );
      
      final index = _allNotes.indexWhere((n) => n.id == noteId);
      if (index != -1) {
        _allNotes[index].isProcessing = false;
        // 闲谈模式：对每个有效 STT 结果进行实时多平台翻译
        if (_currentMode == AppMode.freeTalk && _isValidTranscript(_allNotes[index].transcript)) {
          final translated = await _translateFreeTalk(_allNotes[index].transcript);
          _allNotes[index].translatedContent = translated;
          _saveShadowCache();
        }
        notifyListeners();

        // 每40秒分段 AI 摘要积累
        if (_currentMode != AppMode.freeTalk) {
          final transcript = _allNotes[index].transcript;
          if (_isValidTranscript(transcript)) {
            _segmentTranscriptBuffer.add(transcript);
            _segmentSummaryCounter++;
            if (_segmentSummaryCounter >= _kSlicesPerSegment && !_isGeneratingSegmentSummary) {
              _segmentSummaryCounter = 0;
              unawaited(_generateSegmentSummary());
            }
          }
        }
      }


    } catch (e) {
      debugPrint("Pipeline Error: $e");
    }
  }

  /// 对当前积累的 40 秒切片文本生成分段 AI 摘要
  /// Gemini 通用调用（用于 Groq 兜底）
  Future<String?> _callGemini(String systemPrompt, String userMessage) async {
    final key = _apiKeys[AIProvider.gemini] ?? '';
    if (key.isEmpty) return null;
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$key',
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'system_instruction': {'parts': [{'text': systemPrompt}]},
          'contents': [{'parts': [{'text': userMessage}]}],
          'generationConfig': {'temperature': 0.5},
        }),
      ).timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String?;
            if (text != null && text.trim().isNotEmpty) return text.trim();
          }
        }
      }
    } catch (e) {
      debugPrint('[Gemini Fallback] Error: $e');
    }
    return null;
  }

  Future<void> _generateSegmentSummary() async {
    if (_isGeneratingSegmentSummary) return;
    if (_segmentTranscriptBuffer.isEmpty) return;
    if (_aiService == null) return;
    _isGeneratingSegmentSummary = true;

    try {
      final material = _segmentTranscriptBuffer.join(" ");
      _segmentTranscriptBuffer.clear();

      final recapPrompt = PromptProvider.getSystemPrompt(PromptStrategy.recap, AIProvider.groq, mode: _currentMode, unit: _currentUnit);

      String? summary;
      // Try Groq first
      try {
        summary = await _aiService!.summarize(
          material,
          strategy: PromptStrategy.recap,
          mode: _currentMode,
          unit: _currentUnit,
        );
      } catch (e) {
        debugPrint("[40s Segment Summary] Groq failed, trying Gemini: $e");
        summary = await _callGemini(recapPrompt, material);
      }

      if (summary != null && summary.isNotEmpty && !summary.startsWith('[')) {
        _segmentSummaries.add(summary);
        debugPrint("[40s Segment Summary] ✅ ${summary.substring(0, summary.length.clamp(0, 80))}");
      }
    } catch (e) {
      debugPrint("[40s Segment Summary Error] $e");
    } finally {
      _isGeneratingSegmentSummary = false;
    }
  }

  Future<void> _checkRecoveryCache() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/shadow_draft.json');
    if (await file.exists()) { _hasRecoveredCache = true; notifyListeners(); }
  }

  Future<void> recoverFromCache() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/shadow_draft.json');
    if (await file.exists()) {
      final content = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);
      _allNotes.clear();
      _allNotes.addAll((data['notes'] as List).map((i) => InsightNote.fromJson(i)).toList());
      _hasRecoveredCache = false;
      notifyListeners();
    }
  }

  Future<void> dismissRecovery() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/shadow_draft.json');
    if (await file.exists()) await file.delete();
    _hasRecoveredCache = false;
    notifyListeners();
  }

  Future<void> _saveShadowCache() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/shadow_draft.json');
    final data = {'notes': _allNotes.map((n) => n.toJson()).toList()};
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> generateFinalAcademicReview() async {
    // ⚠️ Bug fix: 即使 _aiService 为 null 或 AI 调用失败，也必须保证 _exportToMarkdown()
    // 被执行（用 try/finally），否则 Discussion/Lecture 模式在开启 Final Recap 时将
    // 因服务未就绪而导致 MD 文件永远无法生成。
    _isGeneratingFinalReview = true; notifyListeners();
    try {
      if (_aiService == null) {
        _finalReviewContent = "[AI service not ready — recap skipped]";
        debugPrint("[Final Academic Review] _aiService is null, skipping recap.");
      } else {
        final material = _allNotes.where((n) => !n.isSummary).map((n) => n.transcript).join(" ");
        if (material.isEmpty) {
          _finalReviewContent = "Not enough material.";
        } else {
          final recapPrompt = PromptProvider.getSystemPrompt(PromptStrategy.recap, AIProvider.groq, mode: _currentMode, unit: _currentUnit);
          try {
            final recap = await _aiService!.summarize(material, strategy: PromptStrategy.recap, mode: _currentMode, unit: _currentUnit);
            _finalReviewContent = recap;
          } catch (mainError) {
            debugPrint("[Final Academic Review] Main service failed, trying Gemini: $mainError");
            final geminiRecap = await _callGemini(recapPrompt, material);
            if (geminiRecap != null) {
              _finalReviewContent = geminiRecap;
            } else if (_fallbackTranslationService != null) {
              try {
                debugPrint("[Final Academic Review] Gemini also failed, trying Groq fallback...");
                final recap = await _fallbackTranslationService!.summarize(material, strategy: PromptStrategy.recap, mode: _currentMode, unit: _currentUnit);
                _finalReviewContent = recap;
              } catch (fallbackError) {
                _finalReviewContent = "Recap failed both primary and fallback service.";
              }
            } else {
              _finalReviewContent = "Recap failed and no fallback configured.";
            }
          }
        }
      }
    } finally {
      // 无论 AI 是否成功，始终执行导出，确保 MD 文件一定被写入磁盘。
      _isGeneratingFinalReview = false;
      notifyListeners();
      await _exportToMarkdown();
    }
  }

  /// 闲谈模式专用导出：无任何标题/日期/分隔线，先中文后英文
  Future<void> _exportFreeTalkMarkdown() async {
    try {
      final now = DateTime.now();
      final filename = "Jeff_FreeTalk_${DateFormat('yyyyMMdd_HHmmss').format(now)}.md";
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');

      final notes = _allNotes.where((n) => !n.isSummary).toList();
      // 收集有效中文和英文（按顺序）
      final chineseSentences = <String>[];
      final englishSentences = <String>[];
      for (final note in notes) {
        final en = note.transcript.trim();
        if (en.isNotEmpty && en != '...' && !en.startsWith('[')) {
          englishSentences.add(en);
        }
        final zh = note.translatedContent?.trim();
        if (zh != null && zh.isNotEmpty && !zh.startsWith('[')) {
          chineseSentences.add(zh);
        }
      }

      final buffer = StringBuffer();
      for (final zh in chineseSentences) {
        buffer.writeln(zh);
      }
      if (chineseSentences.isNotEmpty && englishSentences.isNotEmpty) {
        buffer.writeln();
      }
      for (final en in englishSentences) {
        buffer.writeln(en);
      }

      await file.writeAsString(buffer.toString());
      debugPrint("\x1B[32m[FreeTalk Export OK] ${file.absolute.path}\x1B[0m");
      _uploadToSupabase(file, 'freetalk');
      _lastExportedPath = file.absolute.path;
      notifyListeners();
    } catch (e) {
      debugPrint("[FreeTalk Export Error] $e");
    }
  }

  String _highlightText(String text) {
    String result = text;
    // Numbers / statistics
    result = result.replaceAllMapped(
      RegExp(r'(\d+(?:\.\d+)?\s*(?:%|percent|million|billion|thousand|trillion))', caseSensitive: false),
      (m) => '==${m[1]}==',
    );
    // Academic signal words
    const signalWords = [
      'however', 'therefore', 'because of', 'as a result', 'consequently',
      'in contrast', 'on the other hand', 'for example', 'for instance',
      'in addition', 'moreover', 'furthermore', 'nevertheless',
      'notably', 'importantly', 'specifically', 'in particular',
    ];
    for (final word in signalWords) {
      result = result.replaceAllMapped(
        RegExp('(?<![=])\\b${RegExp.escape(word)}\\b(?![=])', caseSensitive: false),
        (m) => '==${m[0]}==',
      );
    }
    return result;
  }

  /// Wraps Pathways 3 Target Vocabulary words with ==word== in the English script.
  /// Skips words that are already highlighted. Only runs when a unit is selected.
  String _applyVocabularyHighlight(String text, PathwaysUnit unit) {
    if (unit == PathwaysUnit.none) return text;
    final vocab = PromptProvider.getUnitVocabularyList(unit);
    String result = text;
    for (final word in vocab) {
      // Match whole word only, case-insensitive, skip if already inside ==...==
      final pattern = RegExp(
        '(?<!==)(?<![A-Za-z])${RegExp.escape(word)}(?![A-Za-z])(?!==)',
        caseSensitive: false,
      );
      result = result.replaceAllMapped(pattern, (m) => '==${m[0]}==');
    }
    return result;
  }

  Future<void> _exportToMarkdown() async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
      final isDiscussion = _currentMode == AppMode.discussion;
      final isExam = _currentMode == AppMode.exam;
      final prefix = isDiscussion ? "Jeff_Discussion" : isExam ? "Jeff_Exam" : "Jeff_Notes";
      final filename = "${prefix}_$dateStr.md";
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');

      final StringBuffer sb = StringBuffer();

      if (isDiscussion) {
        sb.writeln("# Group Discussion Session");
        sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}");
        sb.writeln("**Context:** ${_identifiedLectureContext ?? 'Group Discussion'}");
      } else if (isExam) {
        sb.writeln("# Exam Listening Session");
        sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}");
        sb.writeln("**Context:** ${_identifiedLectureContext ?? 'Exam Listening'}");
      } else {
        sb.writeln("# Academic Lecture Session");
        sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}");
        sb.writeln("**Context:** ${_identifiedLectureContext ?? 'General Academic Lecture'}");
      }
      sb.writeln();

      // ── Part 1: AI Review ──────────────────────────────────
      if (_finalReviewContent != null && _finalReviewContent!.isNotEmpty) {
        sb.writeln("---");
        sb.writeln();
      if (isDiscussion) {
        sb.writeln("## Part 1 · AI Discussion Recap");
      } else if (isExam) {
        sb.writeln("## Part 1 · Exam Answer Card");
      } else {
        sb.writeln("## Part 1 · AI Academic Review");
      }
        sb.writeln();
        sb.writeln(_finalReviewContent);
        sb.writeln();
      }

      // ── Part 2: Full Script ────────────────────────────────
      final transcripts = _allNotes.where((n) => !n.isSummary).toList();
      if (transcripts.isNotEmpty) {
        sb.writeln("---");
        sb.writeln();
        sb.writeln("## Part 2 · Full Script");
        sb.writeln();

        final List<String> chineseSegments = [];
        final List<String> englishSegments = [];

        for (int i = 0; i < transcripts.length; i++) {
          final note = transcripts[i];
          final engText = note.transcript.trim();
          if (engText.isEmpty ||
              engText == '...' ||
              engText.startsWith('[Silence') ||
              engText.startsWith('[Error')) continue;

          englishSegments.add(engText);

          final zhText = note.translatedContent?.trim();
          if (zhText != null && zhText.isNotEmpty && !zhText.startsWith('[')) {
            chineseSegments.add(zhText);
          }
        }

        sb.writeln("### 中文全文 (Chinese Transcript)");
        sb.writeln();
        sb.writeln(chineseSegments.join(" "));
        sb.writeln();
        sb.writeln();

        sb.writeln("### 英文全文 (English Transcript)");
        sb.writeln();
        sb.writeln(_highlightText(_applyVocabularyHighlight(englishSegments.join(" "), _currentUnit)));
        sb.writeln();
      }


      await file.writeAsString(sb.toString());
      debugPrint("\x1B[32m[Export OK] ${file.absolute.path}\x1B[0m");

      // ── 缝合当次 session 所有的真实录音切片，导出为同名的 .wav 录音文件 ──
      if (_sessionAudioPaths.isNotEmpty) {
        final wavFilename = filename.replaceAll('.md', '.wav');
        final wavPath = '${directory.path}/$wavFilename';
        await _stitchSessionAudioFiles(_sessionAudioPaths, wavPath);
      }

      final module = isDiscussion ? 'discussion' : isExam ? 'exam' : 'listening';
      _uploadToSupabase(file, module);
      _lastExportedPath = file.absolute.path;
      notifyListeners();
    } catch (e) {
      debugPrint("[Export Error] $e");
    }
  }

  Future<void> _stitchSessionAudioFiles(List<String> paths, String outputPath) async {
    try {
      final List<int> allPcm = [];
      for (final p in paths) {
        final f = File(p);
        if (!await f.exists()) continue;
        final bytes = await f.readAsBytes();
        final offset = _findDataChunkOffset(bytes);
        if (bytes.length > offset) {
          allPcm.addAll(bytes.sublist(offset));
        }
      }
      if (allPcm.isNotEmpty) {
        final header = _generateWavHeaderStatic(allPcm.length);
        final stitchedBytes = Uint8List.fromList([...header, ...allPcm]);
        await File(outputPath).writeAsBytes(stitchedBytes);
        debugPrint('[SessionAudio] Successfully stitched ${paths.length} audio slices to $outputPath');
      }
    } catch (e) {
      debugPrint('[SessionAudio] Stitch error: $e');
    }
  }

  Future<void> _uploadToSupabase(File file, String module) async {
    try {
      var userId = '';
      try { userId = SupabaseConfig.currentUserId; } catch (_) {}
      final bytes = await file.readAsBytes();
      final hash = md5.convert(bytes).toString();
      final title = file.path.split('/').last;
      final map = {
        'file_hash': hash,
        'module': module,
        'title': title,
        'content_md': utf8.decode(bytes),
        'file_size': bytes.length,
      };
      if (userId.isNotEmpty) {
        map['user_id'] = userId;
      }
      await SupabaseConfig.client.from('archives').insert(map);
      debugPrint('[Supabase Upload OK] $title ($module)');
    } catch (e) {
      debugPrint('[Supabase Upload Error] $e');
    }
  }

  Future<String> generateEssayMatrix(String finalTopic, {String essayType = 'Argumentative'}) async {
    const systemPrompt = """You are a simple, accessible English essay generator for English learners.
Your task is to generate a standardized 5-paragraph essay based on the user's provided topic, followed by its precise Chinese translation.

### CORE CONCEPT (THE THREE CORE ASPECTS):
Every essay must cover three practical perspectives: Cost (money/expenses), Happiness (mental state/feelings), and Time (convenience/efficiency). 
You have FULL FLEXIBILITY to assign these three aspects across Body 1, Body 2, and Body 3 in whichever order best fits the topic!

### CRITICAL RULES (MUST FOLLOW STRICTLY):
1. PARAGRAPH COUNT: EXACTLY 5 PARAGRAPHS.
2. SENTENCE COUNT: 4 TO 5 SENTENCES PER PARAGRAPH (Maximum 5 sentences per paragraph). Never exceed 5 sentences!
3. PERSPECTIVE: Objective 3rd-person.
4. VOCABULARY: Very simple, everyday English (Junior High / High School level). NEVER use complex academic words (e.g., avoid "indispensable", "crucial", "facilitate", "paramount", "furthermore", "moreover").
5. TRANSITIONS: Paragraphs 2 to 5 MUST include highlighted transitions wrapped in ==double equals== (e.g., ==First==, ==Second==, ==For example==, ==On the other hand==, ==However==, ==In conclusion==).

### FLEXIBLE 5-PARAGRAPH SKELETON (4-5 SENTENCES EACH):

- Paragraph 1 (Intro - Standard 4-Step Structure):
  Sentence 1 [Hook]: [Topic] is more than just [a simple topic]; it is a vital part of a student's daily life.
  Sentence 2 [Background Info]: Explain simply why people care about this topic in daily life.
  Sentence 3 [Controversy/Problem]: Recently, the topic of [Topic] has sparked a discussion among schools and families.
  Sentence 4 [Thesis Statement]: Obviously, [Main position] is the best choice, because this decision is highly beneficial in terms of saving money, improving happiness, and saving time (adjust order to match your body paragraphs).

- Paragraph 2 (Body 1 - Support Aspect A):
  Choose whichever aspect (Cost, Happiness, or Time) is easiest and most direct to argue first.
  Sentence 1: ==First==, [Topic] affects [Aspect A].
  Sentence 2-5: Use 3 to 4 simple sentences to explain why or how, ending with a clean summary sentence.

- Paragraph 3 (Body 2 - Support Aspect B + Example):
  Choose a second aspect (Cost, Happiness, or Time) that naturally fits a real-life example.
  Sentence 1: ==Second==, [Topic] also impacts [Aspect B].
  Sentence 2: Explain the main point simply.
  Sentence 3-4 [Concrete Example]: Introduce a short, everyday example using ==For example==,.
  Sentence 5 (Optional): Summarize the benefit.

- Paragraph 4 (Body 3 - Flexible Concession & Refutation on Aspect C):
  Use the remaining aspect (Cost, Happiness, or Time) to show a slight opposing view, then counter it.
  Sentence 1: Mention a weak point or opposite argument regarding [Aspect C] (e.g., "==On the other hand==, ==some people argue...==" or "==Although== [Topic] is not perfect...").
  Sentences 2-5: Use 2 to 4 simple sentences (incorporating ==However==, or similar natural transition) to counter this idea or show why our main choice is still better in terms of [Aspect C].
  Tone: Natural, flexible, and simple. Do NOT force complex academic refutation logic.

- Paragraph 5 (Conclusion):
  Sentence 1: ==In conclusion==, [Topic] brings clear benefits to our lives.
  Sentences 2-4: Reiterate the three aspects (Cost, Happiness, Time) in simple sentences to close the essay smoothly.

### OUTPUT FORMAT REQUIREMENT:
The output MUST strictly contain two parts separated by ---:

Part 1: The English Essay with == highlighters.
---
Part 2: The sentence-by-sentence Chinese translation.""";

    // Try Gemini 2.5 Flash first
    final geminiKey = this.geminiKey.trim();
    if (geminiKey.isNotEmpty) {
      try {
        final url = Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiKey",
        );

        final response = await http.post(
          url,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "system_instruction": {
              "parts": [{"text": systemPrompt}],
            },
            "contents": [
              {
                "parts": [
                  {"text": "Type: $essayType\nTopic: $finalTopic"},
                ],
              },
            ],
            "generationConfig": {
              "temperature": 0.7,
            },
          }),
        ).timeout(const Duration(seconds: 120));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final text = parts[0]['text'] as String?;
              if (text != null && text.trim().isNotEmpty) {
                return text.trim();
              }
            }
          }
        }
        debugPrint("[Essay] Gemini failed (${response.statusCode}), falling back to SiliconFlow Qwen...");
      } catch (e) {
        debugPrint("[Essay] Gemini exception: $e, falling back to SiliconFlow Qwen...");
      }
    } else {
      debugPrint("[Essay] No Gemini key configured, using SiliconFlow Qwen...");
    }

    // Fallback: SiliconFlow Qwen via OpenAI-compatible API
    final siliconKey = siliconFlowKey.trim();
    if (siliconKey.isEmpty) {
      throw Exception("Gemini API Key not configured and no SiliconFlow key available. Please add a key in Settings.");
    }

    final url = Uri.parse("https://api.siliconflow.cn/v1/chat/completions");
    final response = await http.post(
      url,
      headers: {
        "Authorization": "Bearer $siliconKey",
        "Content-Type": "application/json",
      },
      body: jsonEncode({
        "model": "Qwen/Qwen2.5-7B-Instruct",
        "messages": [
          {"role": "system", "content": systemPrompt},
          {"role": "user", "content": "Type: $essayType\nTopic: $finalTopic"},
        ],
        "temperature": 0.7,
        "max_tokens": 4096,
      }),
    ).timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception("SiliconFlow Qwen error ${response.statusCode}: ${response.body}");
    }

    final data = jsonDecode(response.body);
    final text = data['choices']?[0]?['message']?['content'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception("SiliconFlow Qwen returned empty essay");
    }
    return text.trim();
  }

  @override
  void dispose() {
    _fastSub?.cancel();
    _accurateSub?.cancel();
    _orchestrator?.dispose();
    _sliceTimer?.cancel();
    _audioRecorder.dispose();
    _sessionReadyController.close();
    super.dispose();
  }
}
