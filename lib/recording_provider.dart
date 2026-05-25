import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'openai_service.dart';
import 'ai_orchestrator_service.dart';
import 'api_scheduler.dart';
import 'prompt_provider.dart';
import 'models.dart';  // 包含 AppMode 枚举

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
  final List<int> tail;
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
    List<int> nextTail = [];
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
  OpenAIService? _summaryService;
  AIOrchestratorService? _orchestrator;
  final StreamController<String> _sessionReadyController = StreamController<String>.broadcast();
  String _geminiBaseUrl = "";
  
  StreamSubscription? _fastSub;
  StreamSubscription? _accurateSub;
  
  AIProvider _selectedProvider = AIProvider.groq;
  int _sliceDuration = 5;
  bool _useBluetooth = false;
  bool _isDarkMode = false;
  bool _enableFinalRecap = false;
  bool _enableLectureDiscovery = false;
  AppMode _currentMode = AppMode.lecture;  // 新增模式
  
  final Map<AIProvider, String> _apiKeys = {
    AIProvider.siliconFlow: "",
    AIProvider.groq: "",
  };
  String _openRouterKey = "";
  
  String? _lastTranscript;
  List<int> _lastAudioTail = [];
  Timer? _sliceTimer;
  bool _isRecording = false;
  bool _isPending = false;
  static const int kTailSize = 25600;

  final List<InsightNote> _allNotes = [];
  String? _statusMessage;
  int _lastSummaryTotalCount = 0;
  String? _finalReviewContent;
  bool _isGeneratingFinalReview = false;
  String? _lastExportedPath;
  String? _identifiedLectureContext;
  bool _hasRecoveredCache = false;

  List<InsightNote> get notes => _allNotes.reversed.toList();
  bool get isRecording => _isRecording;
  bool get isPending => _isPending;
  AIProvider get selectedProvider => _selectedProvider;
  int get sliceDuration => _sliceDuration;
  bool get useBluetooth => _useBluetooth;
  bool get isDarkMode => _isDarkMode;
  bool get enableFinalRecap => _enableFinalRecap;
  bool get enableLectureDiscovery => _enableLectureDiscovery;
  AppMode get currentMode => _currentMode;
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
  String get geminiBaseUrl => _geminiBaseUrl;

  // Track previously initialized keys to avoid redundant recreation
  String _prevSiliconKey = "";
  String _prevGroqKey = "";
  String _prevOpenRouterKey = "";

  RecordingProvider() { _init(); }

  Future<void> _init() async {
    await _loadSettings();
    await _initializeAudioSession();
    await _checkRecoveryCache();
  }

  String getApiKeyFor(AIProvider provider) => _apiKeys[provider] ?? "";

  Future<void> updateSettings({
    AIProvider? provider,
    String? key,
    int? duration,
    bool? useBluetooth,
    bool? isDarkMode,
    bool? enableFinalRecap,
    bool? enableLectureDiscovery,
    AppMode? mode,
    String? geminiBaseUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (duration != null) { await prefs.setInt('slice_duration', duration); _sliceDuration = duration; }
    if (useBluetooth != null) { await prefs.setBool('use_bluetooth', useBluetooth); _useBluetooth = useBluetooth; }
    if (isDarkMode != null) { await prefs.setBool('is_dark_mode', isDarkMode); _isDarkMode = isDarkMode; }
    if (enableFinalRecap != null) { await prefs.setBool('enableFinalRecap', enableFinalRecap); _enableFinalRecap = enableFinalRecap; }
    if (enableLectureDiscovery != null) { await prefs.setBool('enableLectureDiscovery', enableLectureDiscovery); _enableLectureDiscovery = enableLectureDiscovery; }
    if (mode != null) { await prefs.setInt('app_mode', mode.index); _currentMode = mode; }
    if (provider != null) {
      _selectedProvider = provider;
      await prefs.setInt('selected_provider', provider.index);
      if (key != null) { 
        await prefs.setString('api_key_${provider.name}', key); 
        _apiKeys[provider] = key;
        debugPrint("保存 ${provider.name} API Key 成功，前几位: ${key.substring(0, 10)}...");
      }
    }
    if (geminiBaseUrl != null) {
      _geminiBaseUrl = geminiBaseUrl;
      await prefs.setString('gemini_base_url', geminiBaseUrl);
    }
    _updateService();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _sliceDuration = prefs.getInt('slice_duration') ?? 5;
    _useBluetooth = prefs.getBool('use_bluetooth') ?? false;
    _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    _enableFinalRecap = prefs.getBool('enableFinalRecap') ?? false;
    _enableLectureDiscovery = prefs.getBool('enableLectureDiscovery') ?? false;
    final modeIndex = prefs.getInt('app_mode') ?? 0;
    _currentMode = AppMode.values[modeIndex];
    final pIndex = prefs.getInt('selected_provider') ?? 0;
    _selectedProvider = AIProvider.values[pIndex];
    _geminiBaseUrl = prefs.getString('gemini_base_url') ?? "https://generativelanguage.googleapis.com/v1beta/openai";
    // 默认 fallback Key（首次安装或 SharedPreferences 未存过时使用）
    const Map<String, String> _defaultKeys = {
      'groq': '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',
      'siliconFlow': 'sk-locbdesikzjxmpkserdenuqjvvuzcfccjxbubexcxyucyyvv',
    };
    for (var p in AIProvider.values) {
      _apiKeys[p] = prefs.getString('api_key_${p.name}') ?? _defaultKeys[p.name] ?? '';
    }
    _openRouterKey = prefs.getString('api_key_openrouter')
        ?? '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';
    _updateService();
  }

  void _updateService() {
    final siliconKey = _apiKeys[AIProvider.siliconFlow] ?? "";
    final groqKey = _apiKeys[AIProvider.groq] ?? "";

    // 调试日志：打印硅基流动 API Key 的前6位字符
    if (siliconKey.isNotEmpty) {
      final prefix = siliconKey.length >= 6 ? siliconKey.substring(0, 6) : siliconKey;
      debugPrint("硅基流动 API Key 读取成功，前6位: $prefix...");
    } else {
      debugPrint("硅基流动 API Key 为空或未找到");
    }

    // 调试日志：打印 Groq API Key 的前6位字符
    if (groqKey.isNotEmpty) {
      final prefix = groqKey.length >= 6 ? groqKey.substring(0, 6) : groqKey;
      debugPrint("Groq API Key 读取成功，前6位: $prefix...");
    } else {
      debugPrint("Groq API Key 为空或未找到");
    }

    // 调试日志：打印 OpenRouter API Key 的前6位字符
    if (_openRouterKey.isNotEmpty) {
      final prefix = _openRouterKey.length >= 6 ? _openRouterKey.substring(0, 6) : _openRouterKey;
      debugPrint("OpenRouter API Key 读取成功，前6位: $prefix...");
    } else {
      debugPrint("OpenRouter API Key 为空或未找到");
    }

    // 只在 key 变化时重新创建服务，避免重复初始化导致红屏
    final bool siliconChanged = siliconKey != _prevSiliconKey;
    final bool groqChanged = groqKey != _prevGroqKey;
    final bool openRouterChanged = _openRouterKey != _prevOpenRouterKey;
    if (!siliconChanged && !groqChanged && !openRouterChanged && _orchestrator != null) {
      // Keys 未变化且服务已初始化，直接返回，保持现有服务实例
      return;
    }

    // 只有在真正变化（或首次初始化）时，才清理并重新创建
    _fastSub?.cancel();
    _accurateSub?.cancel();
    _orchestrator?.dispose();

    // 更新记录的上一次键值
    _prevSiliconKey = siliconKey;
    _prevGroqKey = groqKey;
    _prevOpenRouterKey = _openRouterKey;
    
    // 1. 初始化 Groq 服务
    if (groqKey.isNotEmpty) {
      debugPrint("正在创建 Groq 服务，API Key 长度: ${groqKey.length}");
      _groqService = OpenAIService(
        apiKey: groqKey,
        baseUrl: "https://api.groq.com/openai/v1",
        defaultModel: "llama-3.3-70b-versatile",
        whisperModel: "whisper-large-v3",
      );
      debugPrint("Groq 服务创建完成");
    } else {
      _groqService = null;
    }

    // 2. 根据最速最省 Token 的多分配架构：
    // - STT (快车轨) 必须用 Groq (llama-3.3-70b-versatile/whisper) 以追求极致英文字幕速度
    // - 翻译/复盘 (主服务) 首选 OpenRouter 的 google/gemini-2.0-flash，如果不可用则向下兼容硅基 Qwen
    // - 滑动窗口摘要 (辅助AI服务) 使用硅基流动 Qwen-72B 以保障极佳的指令执行力，避免抢占主通道并发
    
    OpenAIService? mainTranslationService;
    OpenAIService? fallbackTranslationService;
    OpenAIService? summaryService;

    // 初始化 OpenRouter Gemini 服务作为首选翻译/复盘
    if (_openRouterKey.isNotEmpty) {
      debugPrint("正在创建 OpenRouter Gemini 服务");
      mainTranslationService = OpenAIService(
        apiKey: _openRouterKey,
        baseUrl: "https://openrouter.ai/api/v1",
        defaultModel: "google/gemini-2.0-flash",
        whisperModel: "whisper-large-v3",
      );
    }

    // 初始化硅基流动服务
    OpenAIService? siliconService;
    if (siliconKey.isNotEmpty) {
      debugPrint("正在创建硅基流动服务");
      siliconService = OpenAIService(
        apiKey: siliconKey,
        baseUrl: "https://api.siliconflow.cn/v1",
        defaultModel: "Qwen/Qwen2.5-72B-Instruct",
        whisperModel: "FunAudioLLM/SenseVoiceSmall",
      );
      fallbackTranslationService = siliconService;
      summaryService = siliconService;
    }

    // 确定最终绑定的服务对象
    if (mainTranslationService != null) {
      _aiService = mainTranslationService;
      debugPrint("主翻译/复盘服务绑定为: OpenRouter (Gemini-2.0-Flash)");
    } else if (siliconService != null) {
      _aiService = siliconService;
      debugPrint("无 OpenRouter Key，主服务 Fallback 绑定为: 硅基流动 (Qwen-72B)");
    } else if (_groqService != null) {
      _aiService = _groqService;
      debugPrint("主服务兜底绑定为: Groq");
    } else {
      _aiService = null;
      debugPrint("警告：未绑定任何可用的 AI 主服务");
    }

    // STT 固定使用 Groq
    if (_groqService != null) {
      _fastAiService = _groqService;
      debugPrint("STT (快轨转录) 固定绑定为: Groq Whisper");
    } else {
      _fastAiService = _aiService;
      debugPrint("警告：无 Groq 服务，STT 转录使用主服务替代");
    }

    // 绑定 Semantic 滑动窗口摘要服务（首选 Qwen/硅基，无则使用主 AI 服务）
    _summaryService = summaryService ?? _aiService;
    debugPrint("摘要服务绑定为: ${_summaryService?.baseUrl.contains('siliconflow') == true ? '硅基流动 (Qwen-72B)' : '主服务'}");
    
    if (_aiService != null && _fastAiService != null) {
      _orchestrator = AIOrchestratorService(
        sttService: _fastAiService!,
        translationService: _aiService!,
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
          _sessionReadyController.add(result.content); // Notify of new translation
          _saveShadowCache();
          notifyListeners();
        }
      });
    }
  }

  Future<void> _initializeAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
    ));
    await session.setActive(true);
  }

  Future<void> toggleRecording() async {
    if (_isPending) return;
    _isPending = true; notifyListeners();
    if (_isRecording) await stopRecording(); else await startRecording();
    _isPending = false; notifyListeners();
  }

  Future<void> startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      _updateService();
      _isRecording = true;
      _lastAudioTail = [];
      _allNotes.clear();
      _lastTranscript = null;
      _lastSummaryTotalCount = 0;
      _finalReviewContent = null;
      notifyListeners();
      final path = await _getTempPath();
      await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
      _startSmartSliceTimer();
    }
  }

  void _startSmartSliceTimer() {
    _sliceTimer?.cancel();
    _sliceTimer = Timer.periodic(Duration(seconds: _sliceDuration), (timer) async {
      if (!_isRecording) { timer.cancel(); return; }
      final path = await _audioRecorder.stop();
      if (path != null) unawaited(_processAudio(path));
      
      await Future.delayed(const Duration(milliseconds: 100));
      if (_isRecording) {
        final nextPath = await _getTempPath();
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: nextPath);
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

    final currentTranscripts = _allNotes.where((n) => !n.isSummary).toList();
    if (currentTranscripts.length > _lastSummaryTotalCount) {
      final remainingText = currentTranscripts
          .skip(_lastSummaryTotalCount)
          .map((e) => e.transcript)
          .join(" ");
      if (remainingText.trim().isNotEmpty) {
        await _performBatchSummary(remainingText, "final_flush_${DateTime.now().millisecondsSinceEpoch}");
      }
    }
    
    _statusMessage = "Finalizing AI tasks...";
    notifyListeners();
    await ApiScheduler().untilIdle();

    // 根据模式决定最终输出
    if (_currentMode == AppMode.freeTalk) {
      // 闲谈模式：跳过 AI 总结，直接导出纯双语文件
      await _exportFreeTalkMarkdown();
    } else {
      if (_enableFinalRecap) {
        await generateFinalAcademicReview();
      } else {
        await _exportToMarkdown();
      }
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

  /// 多平台翻译轮询（闲谈模式专用）
  Future<String> _translateFreeTalk(String englishText) async {
    // 定义平台顺序：首选极速高可用的 Gemini-2.0-Flash
    final providers = [
      () => _translateViaOpenRouter(englishText, model: 'google/gemini-2.0-flash'),
      () => _translateViaOpenRouter(englishText, model: 'glm-4-flash'),
      () => _translateViaOpenRouter(englishText, model: 'moonshot-v1-8k'),
      () => _translateViaSiliconFlow(englishText),
    ];
    for (var provider in providers) {
      try {
        final result = await provider().timeout(const Duration(seconds: 8));
        if (result.isNotEmpty && !result.startsWith('[')) {
          return result;
        }
      } catch (e) {
        debugPrint("Translation provider failed: $e");
        continue;
      }
    }
    return '[Translation failed]';
  }

  /// OpenRouter 调用 (智谱/月之暗面)
  Future<String> _translateViaOpenRouter(String text, {required String model}) async {
    final apiKey = _openRouterKey;
    final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': 'Translate the following English text to Simplified Chinese, output only the translation: $text'}
        ],
        'temperature': 0.2,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final translated = data['choices'][0]['message']['content'].trim();
      return translated;
    } else {
      throw Exception('OpenRouter error: ${response.statusCode}');
    }
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
    try {
      final stitchResult = await compute(_backgroundStitchTask, StitchData(_lastAudioTail, path, kTailSize));
      final processedPath = stitchResult['path'] as String;
      _lastAudioTail = List<int>.from(stitchResult['newTail']);

      final currentNote = InsightNote(summary: '', transcript: '...', timestamp: DateTime.now(), isProcessing: true);
      final noteId = currentNote.id;
      _allNotes.add(currentNote);
      notifyListeners();

      await _orchestrator!.processAudioSegment(
        noteId,
        processedPath,
        context: _lastTranscript,
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
      }

      final totalCount = _allNotes.where((n) => !n.isSummary).length;
      if (totalCount > 0 && totalCount % 12 == 0) {
        final combinedText = _allNotes.where((n) => !n.isSummary).skip(_lastSummaryTotalCount).map((e) => e.transcript).join(" ");
        _lastSummaryTotalCount = totalCount;
        unawaited(_performBatchSummary(combinedText, "cluster_${DateTime.now().millisecondsSinceEpoch}"));
      }
    } catch (e) {
      debugPrint("Pipeline Error: $e");
    }
  }

  Future<void> _performBatchSummary(String text, String? clusterId) async {
    if (_summaryService == null) return;
    final summary = await _summaryService!.summarize(text, mode: _currentMode);
    final summaryNote = InsightNote(summary: summary, transcript: '', timestamp: DateTime.now(), isSummary: true, clusterId: clusterId);
    _allNotes.add(summaryNote);
    _saveShadowCache();
    notifyListeners();
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
    if (_aiService == null) return;
    _isGeneratingFinalReview = true; notifyListeners();
    final material = _allNotes.where((n) => n.isSummary).map((n) => n.summary).join("\n\n");
    if (material.isEmpty) { _finalReviewContent = "Not enough material."; } else {
      final recap = await _aiService!.summarize(material, strategy: PromptStrategy.recap, mode: _currentMode);
      _finalReviewContent = recap;
    }
    _isGeneratingFinalReview = false;
    notifyListeners();
    await _exportToMarkdown();
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
      _lastExportedPath = file.absolute.path;
      notifyListeners();
    } catch (e) {
      debugPrint("[FreeTalk Export Error] $e");
    }
  }

  Future<void> _exportToMarkdown() async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
      final filename = "Jeff_Notes_$dateStr.md";
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');

      final StringBuffer sb = StringBuffer();

      sb.writeln("# Academic Lecture Session");
      sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}");
      sb.writeln("**Context:** ${_identifiedLectureContext ?? 'General Academic Lecture'}");
      sb.writeln();

      if (_finalReviewContent != null && _finalReviewContent!.isNotEmpty) {
        sb.writeln("---");
        sb.writeln();
        sb.writeln("## Part 1 · AI Academic Review");
        sb.writeln();
        sb.writeln(_finalReviewContent);
        sb.writeln();
      }

      final summaries = _allNotes.where((n) => n.isSummary).toList();
      if (summaries.isNotEmpty) {
        sb.writeln("---");
        sb.writeln();
        sb.writeln("## Part 2 · 60s Block Summaries");
        sb.writeln();
        for (int i = 0; i < summaries.length; i++) {
          sb.writeln("### Block ${i + 1}");
          sb.writeln(summaries[i].summary);
          sb.writeln();
        }
      }

      final transcripts = _allNotes.where((n) => !n.isSummary).toList();
      if (transcripts.isNotEmpty) {
        sb.writeln("---");
        sb.writeln();
        sb.writeln("## Part 3 · Full Bilingual Script");
        sb.writeln();
        
        List<String> pendingEng = [];
        int blockCount = 1;

        for (int i = 0; i < transcripts.length; i++) {
          final note = transcripts[i];
          if (note.transcript.isEmpty ||
              note.transcript == '...' ||
              note.transcript.startsWith('[Silence') ||
              note.transcript.startsWith('[Error')) continue;

          pendingEng.add(note.transcript);

          if (note.translatedContent != null && note.translatedContent!.isNotEmpty) {
            sb.writeln("**[$blockCount] ENG:** ${pendingEng.join(' ')}");
            sb.writeln("**[$blockCount] CHN:** ${note.translatedContent}");
            sb.writeln();
            pendingEng.clear();
            blockCount++;
          }
        }

        if (pendingEng.isNotEmpty) {
          sb.writeln("**[$blockCount] ENG:** ${pendingEng.join(' ')}");
          sb.writeln("**[$blockCount] CHN:** (Processing / End of Audio)");
          sb.writeln();
        }
      }

      await file.writeAsString(sb.toString());
      debugPrint("\x1B[32m[Export OK] ${file.absolute.path}\x1B[0m");
      _lastExportedPath = file.absolute.path;
      notifyListeners();
    } catch (e) {
      debugPrint("[Export Error] $e");
    }
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
