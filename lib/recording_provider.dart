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
  OpenAIService? _summaryService;
  OpenAIService? _fallbackTranslationService;
  AIOrchestratorService? _orchestrator;
  final StreamController<String> _sessionReadyController = StreamController<String>.broadcast();

  
  StreamSubscription? _fastSub;
  StreamSubscription? _accurateSub;
  
  AIProvider _selectedProvider = AIProvider.groq;
  int _sliceDuration = 5;
  bool _useBluetooth = false;
  bool _isDarkMode = false;
  bool _enableFinalRecap = false;
  bool _enableLectureDiscovery = false;
  AppMode _currentMode = AppMode.lecture;  // 新增模式
  PathwaysUnit _currentUnit = PathwaysUnit.none;
  
  final Map<AIProvider, String> _apiKeys = {
    AIProvider.siliconFlow: "",
    AIProvider.groq: "",
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
  int _lastSummaryTotalCount = 0;
  String? _finalReviewContent;
  bool _isGeneratingFinalReview = false;
  String? _lastExportedPath;
  String? _identifiedLectureContext;
  bool _hasRecoveredCache = false;
  String _openRouterKey = '';

  List<InsightNote> get notes => _allNotes.reversed.toList();
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get isPending => _isPending;
  AIProvider get selectedProvider => _selectedProvider;
  int get sliceDuration => _sliceDuration;
  bool get useBluetooth => _useBluetooth;
  bool get isDarkMode => _isDarkMode;
  bool get enableFinalRecap => _enableFinalRecap;
  bool get enableLectureDiscovery => _enableLectureDiscovery;
  AppMode get currentMode => _currentMode;
  PathwaysUnit get currentUnit => _currentUnit;
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


  // Track previously initialized keys to avoid redundant recreation
  String _prevSiliconKey = "";
  String _prevGroqKey = "";


  RecordingProvider() { _init(); }

  Future<void> _init() async {
    await _loadSettings();
    await _initializeAudioSession();
    await _checkRecoveryCache();
  }

  String get groqKey => _apiKeys[AIProvider.groq] ?? "";
  String get siliconFlowKey => _apiKeys[AIProvider.siliconFlow] ?? "";
  String get openRouterKey => _openRouterKey;

  Future<void> updateSettings({
    String? groqKey,
    String? siliconFlowKey,
    String? openRouterKey,

    int? duration,
    bool? useBluetooth,
    bool? isDarkMode,
    bool? enableFinalRecap,
    bool? enableLectureDiscovery,
    AppMode? mode,
    PathwaysUnit? unit,

  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (duration != null) {
      final clamped = duration.clamp(5, 8);
      await prefs.setInt('slice_duration', clamped);
      _sliceDuration = clamped;
    }
    if (useBluetooth != null) { await prefs.setBool('use_bluetooth', useBluetooth); _useBluetooth = useBluetooth; }
    if (isDarkMode != null) { await prefs.setBool('is_dark_mode', isDarkMode); _isDarkMode = isDarkMode; }
    if (enableFinalRecap != null) { await prefs.setBool('enableFinalRecap', enableFinalRecap); _enableFinalRecap = enableFinalRecap; }
    if (enableLectureDiscovery != null) { await prefs.setBool('enableLectureDiscovery', enableLectureDiscovery); _enableLectureDiscovery = enableLectureDiscovery; }
    if (mode != null) { await prefs.setInt('app_mode', mode.index); _currentMode = mode; }
    if (unit != null) {
      await prefs.setInt('current_unit', unit.index);
      _currentUnit = unit;
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
    if (openRouterKey != null) {
      final trimmedKey = openRouterKey.trim();
      await prefs.setString('api_key_openrouter', trimmedKey);
      _openRouterKey = trimmedKey;
      debugPrint("保存 OpenRouter API Key 成功，前几位: ${trimmedKey.isNotEmpty ? trimmedKey.substring(0, trimmedKey.length.clamp(0, 10)) : ''}...");
    }
    if (siliconFlowKey != null) {
      final trimmedKey = siliconFlowKey.trim();
      await prefs.setString('api_key_${AIProvider.siliconFlow.name}', trimmedKey);
      _apiKeys[AIProvider.siliconFlow] = trimmedKey;
      debugPrint("保存 SiliconFlow API Key 成功，前几位: ${trimmedKey.isNotEmpty ? trimmedKey.substring(0, trimmedKey.length.clamp(0, 10)) : ''}...");
    }

    _updateService();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _sliceDuration = (prefs.getInt('slice_duration') ?? 5).clamp(5, 8);
    _useBluetooth = prefs.getBool('use_bluetooth') ?? false;
    _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    _enableFinalRecap = prefs.getBool('enableFinalRecap') ?? false;
    _enableLectureDiscovery = prefs.getBool('enableLectureDiscovery') ?? false;
    final modeIndex = prefs.getInt('app_mode') ?? 0;
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


    // 只在 key 变化时重新创建服务，避免重复初始化导致红屏
    final bool siliconChanged = siliconKey != _prevSiliconKey;
    final bool groqChanged = groqKey != _prevGroqKey;
    if (!siliconChanged && !groqChanged && _orchestrator != null) {
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
    // - 翻译/复盘 (主服务) 使用硅基流动 Qwen，备用硅基 Qwen-72B
    // - 滑动窗口摘要 (辅助AI服务) 使用硅基流动 Qwen-72B 以保障极佳的指令执行力，避免抢占主通道并发
    
    OpenAIService? mainTranslationService;
    OpenAIService? fallbackTranslationService;
    OpenAIService? summaryService;

    // 使用硅基流动的 Qwen 2.5 32B 作为主翻译/复盘服务 (极速且性价比高)
    if (siliconKey.isNotEmpty) {
      debugPrint("正在创建硅基流动 Qwen-2.5-32B 主翻译/复盘服务");
      mainTranslationService = OpenAIService(
        apiKey: siliconKey,
        baseUrl: "https://api.siliconflow.cn/v1",
        defaultModel: "Qwen/Qwen2.5-32B-Instruct",
        whisperModel: "FunAudioLLM/SenseVoiceSmall",
      );
    }

    // 初始化硅基流动 72B 辅助服务（用于 60s 摘要和备用翻译/降级）
    OpenAIService? silicon72BService;
    if (siliconKey.isNotEmpty) {
      debugPrint("正在创建硅基流动 Qwen-2.5-72B 辅助总结/兜底服务");
      silicon72BService = OpenAIService(
        apiKey: siliconKey,
        baseUrl: "https://api.siliconflow.cn/v1",
        defaultModel: "Qwen/Qwen2.5-72B-Instruct",
        whisperModel: "FunAudioLLM/SenseVoiceSmall",
      );
      fallbackTranslationService = silicon72BService;
      summaryService = silicon72BService;
    }

    // 确定最终绑定的服务对象
    if (mainTranslationService != null) {
      _aiService = mainTranslationService;
      debugPrint("主翻译/复盘服务绑定为: 硅基流动 (Qwen-32B)");
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

    // 绑定备用翻译服务（硅基流动 Qwen），以便在主通道超时/故障时平滑切换
    _fallbackTranslationService = fallbackTranslationService;
    debugPrint("备用翻译服务绑定为: ${_fallbackTranslationService != null ? '硅基流动 (Qwen-72B)' : '无'}");
    
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

  Future<void> toggleRecording() async {
    if (_isPending) return;
    _isPending = true; notifyListeners();
    if (_isRecording) await stopRecording(); else await startRecording();
    _isPending = false; notifyListeners();
  }

  Future<void> startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      _updateService();
      if (_orchestrator == null) {
        _statusMessage = "Please configure your API Keys in Settings first";
        notifyListeners();
        return;
      }
      _isRecording = true;
      _isPaused = false;   // 新录音时重置暂停状态
      _lastAudioTail = Uint8List(0);
      _allNotes.clear();
      _lastTranscript = null;
      _lastSummaryTotalCount = 0;
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
    
    // 即时汇总弹出：停止后立即将缓存中所有的每分钟 block 总结整合成 MD 弹出
    // 讲座模式与小组讨论模式均支持，闲谈模式无摘要故跳过
    if (_currentMode != AppMode.freeTalk) {
      final summaries = _allNotes.where((n) => n.isSummary).toList();
      if (summaries.isNotEmpty) {
        final buffer = StringBuffer();
        if (_currentMode == AppMode.lecture) {
          buffer.writeln("# 📝 讲座实时小结汇总 (Live Session Summaries)");
          buffer.writeln("> 此处为您点击停止后，立即从本地缓存还原的每分钟核心小结。系统正在后台为您生成深度的 AI 学术复盘报告，请稍候...");
        } else {
          buffer.writeln("# 💬 讨论实时要点汇总 (Live Discussion Summaries)");
          buffer.writeln("> 此处为您点击停止后，立即从本地缓存还原的讨论要点。系统正在后台为您生成深度讨论复盘，请稍候...");
        }
        buffer.writeln();
        for (int i = 0; i < summaries.length; i++) {
          buffer.writeln("### ⏰ 第 ${i + 1} 分钟要点");
          buffer.writeln(summaries[i].summary);
          buffer.writeln();
        }
        // 即刻激发 UI 模态弹出展示，消除用户等待焦虑
        _sessionReadyController.add(buffer.toString());
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
    try {
      final summary = await _summaryService!.summarize(text, mode: _currentMode, unit: _currentUnit);
      final summaryNote = InsightNote(summary: summary, transcript: '', timestamp: DateTime.now(), isSummary: true, clusterId: clusterId);
      _allNotes.add(summaryNote);
      _saveShadowCache();
      notifyListeners();
    } catch (e) {
      debugPrint("Batch summary error: $e");
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
        final material = _allNotes.where((n) => n.isSummary).map((n) => n.summary).join("\n\n");
        if (material.isEmpty) {
          _finalReviewContent = "Not enough material.";
        } else {
          try {
            final recap = await _aiService!.summarize(material, strategy: PromptStrategy.recap, mode: _currentMode, unit: _currentUnit);
            _finalReviewContent = recap;
          } catch (mainError) {
            debugPrint("[Final Academic Review] Main service failed, trying fallback: $mainError");
            if (_fallbackTranslationService != null) {
              try {
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
    if (text.contains('==')) return text;
    String result = text;
    result = result.replaceAllMapped(
      RegExp(r'(\d+(?:\.\d+)?\s*(?:%|percent|million|billion|thousand|trillion))', caseSensitive: false),
      (m) => '==${m[1]}==',
    );
    const signalWords = [
      'however', 'therefore', 'because of', 'as a result', 'consequently',
      'in contrast', 'on the other hand', 'for example', 'for instance',
      'in addition', 'moreover', 'furthermore', 'nevertheless',
      'notably', 'importantly', 'specifically', 'in particular',
    ];
    for (final word in signalWords) {
      result = result.replaceAllMapped(
        RegExp('\\b$word\\b', caseSensitive: false),
        (m) => '==${m[0]}==',
      );
    }
    return result;
  }

  Future<void> _exportToMarkdown() async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
      final isDiscussion = _currentMode == AppMode.discussion;
      final prefix = isDiscussion ? "Jeff_Discussion" : "Jeff_Notes";
      final filename = "${prefix}_$dateStr.md";
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');

      final StringBuffer sb = StringBuffer();

      if (isDiscussion) {
        sb.writeln("# Group Discussion Session");
        sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}");
        sb.writeln("**Context:** ${_identifiedLectureContext ?? 'Group Discussion'}");
      } else {
        sb.writeln("# Academic Lecture Session");
        sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}");
        sb.writeln("**Context:** ${_identifiedLectureContext ?? 'General Academic Lecture'}");
      }
      sb.writeln();

      if (_finalReviewContent != null && _finalReviewContent!.isNotEmpty) {
        sb.writeln("---");
        sb.writeln();
        if (isDiscussion) {
          sb.writeln("## Part 1 · AI Discussion Recap");
        } else {
          sb.writeln("## Part 1 · AI Academic Review");
        }
        sb.writeln();
        sb.writeln(_finalReviewContent);
        sb.writeln();
      }

      final summaries = _allNotes.where((n) => n.isSummary).toList();
      if (summaries.isNotEmpty) {
        sb.writeln("---");
        sb.writeln();
        if (isDiscussion) {
          sb.writeln("## Part 2 · Discussion Block Summaries");
        } else {
          sb.writeln("## Part 2 · 60s Block Summaries");
        }
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
        sb.writeln("## Part 3 · Full Script");
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
        sb.writeln(_highlightText(englishSegments.join(" ")));
        sb.writeln();
      }

      await file.writeAsString(sb.toString());
      debugPrint("\x1B[32m[Export OK] ${file.absolute.path}\x1B[0m");
      final module = isDiscussion ? 'discussion' : 'listening';
      _uploadToSupabase(file, module);
      _lastExportedPath = file.absolute.path;
      notifyListeners();
    } catch (e) {
      debugPrint("[Export Error] $e");
    }
  }

  Future<void> _uploadToSupabase(File file, String module) async {
    try {
      final bytes = await file.readAsBytes();
      final hash = md5.convert(bytes).toString();
      final title = file.path.split('/').last;
      await SupabaseConfig.client.from('archives').insert({
        'file_hash': hash,
        'module': module,
        'title': title,
        'content_md': utf8.decode(bytes),
        'file_size': bytes.length,
      });
      debugPrint('[Supabase Upload OK] $title ($module)');
    } catch (e) {
      debugPrint('[Supabase Upload Error] $e');
    }
  }

  Future<String> generateEssayMatrix(String topicA, String topicB, String level, {String? model}) async {
    OpenAIService? service;
    if (model == 'llama70b') {
      service = _groqService;
    } else if (model == 'qwen32b') {
      service = _aiService;
    } else if (model == 'qwen72b') {
      service = _summaryService;
    }
    
    // 兜底逻辑：如果选定的服务未初始化，按照 70B -> 32B -> 72B 顺序选择可用服务
    service ??= _groqService ?? _aiService ?? _summaryService;
    
    if (service == null) {
      throw Exception("AI service not ready. Please configure API Keys in settings.");
    }
    
    final prompt = """# Role: Jeff Notes 钢铁模板学术写作架构师 (Strict EAL Essay Architect)

# Inputs:
Subject A: "$topicA"
Subject B: "$topicB"
Complexity Level: "$level"

# Task:
根据输入的两个主体对象（Subject A 和 Subject B），严格按照下方给出的【钢铁模板】结构，同时产出两篇完全独立的学术对比范文（一篇纯相同点，一篇纯不同点），并提取对应的双级词组笔记。

# Critical Constraints (最高死命令):
1. **结构绝对锁死**：必须一字不差地使用【钢铁模板】中的 Introduction, Body 1, Body 2, Body 3, 和 Conclusion 的通用骨架句式。你的任务是根据具体的主体（如 "$topicA" 与 "$topicB"）去替换括号中的主体名，并构思 3 个核心对比维度来填满细节，严禁修改任何模板万能连接词！
2. **语域限制 (EAL-Friendly)**：生成的细节扩充部分（Meat）严禁使用极度偏门、晦涩的大词。必须分为“朴素版词组（想得起、用着顺）”和“高级版词组（拿 A+、惊艳教授）”两层，且高级词组必须自然融入到范文的细节描写中。
3. **彻底单向单篇**：篇章 1 必须 100% 纯写相同点；篇章 2 必须 100% 纯写不同点。绝不允许在同一篇章内混写！
4. **语言要求 (中英对照与纯英范文)**：
   - 范文（Introduction, Body 1/2/3, Conclusion）的段落内容必须**完全为英文**。
   - 只有在模板中明确标注有“中文”的括号里（例如：[相同点1中文]、[不同点1中文]），才使用中文进行归纳。
   - 专属词组笔记中，中文意思部分使用中文，词组使用英文。
   - 严禁将范文的英文模板翻译成中文！范文必须是可直接提交的高质量英文学术写作。

---

# 📐 核心参考与输出钢骨模板 (The Bible Templates):

你必须严格按照以下格式回传数据：

# 📊 TRACK 1: THE SIMILARITIES ESSAY
### 🧱 篇章 1：纯 3 个相同点（Similarity）全套范文
**Introduction**
In the modern world, $topicA and $topicB are two very important concepts that many people talk about. Although they look quite different at first, they actually share a lot of common ground. In my opinion, they have three major similarities, including [相同点1核心词], [相同点2核心词], and [相同点3核心词].

**Body 1 (相同点 1：[相同点1中文])**
First, $topicA and $topicB are very similar in terms of [相同点1核心词]. Specifically, $topicA focuses heavily on [针对Subject A的细节展开]. Similarly, $topicB also cares a lot about [针对Subject B的细节展开]. Therefore, this first similarity shows that they are closer than we think in this area.

**Body 2 (相同点 2：[相同点2中文])**
Second, there is a strong common ground between $topicA and $topicB when it comes to [相同点2核心词]. This means they face the exact same situation. For instance, $topicA is deeply driven by [针对Subject A的细节展开], and $topicB is also influenced by [针对Subject B的细节展开]. As a result, we can see that their developments in this field are highly matched.

**Body 3 (相同点 3：[相同点3中文])**
Third, $topicA and $topicB are also identical because of [相同点3核心词]. On one hand, the growth of $topicA relies on [针对Subject A of the details]. On the other hand, the success of $topicB also comes from [针对Subject B of the details]. Consequently, this final point clearly demonstrates that these two subjects share the same path.

**Conclusion**
In conclusion, although $topicA and $topicB have their own characteristics, their similarities are very obvious. As mentioned above, they both focus on [相同点1核心词], share a common ground in [相同点2核心词], and are driven by [相同点3核心词]. Therefore, it is clear that these two subjects share the same path in many ways.

---

# 📊 TRACK 2: THE DIFFERENCES ESSAY
### 🧱 篇章 2：纯 3 个不同点（Differences）全套范文
**Introduction**
In the modern world, $topicA and $topicB are two very important concepts that many people talk about. Although they share some common goals at first, they actually have many huge differences. In my opinion, they have three major differences, including [不同点1核心词], [不同点2核心词], and [不同点3核心词].

**Body 1 (不同点 1：[不同点1中文])**
First, $topicA and $topicB have a major difference in terms of [不同点1核心词]. Specifically, $topicA focuses heavily on [针对Subject A的差异展开]. In contrast, $topicB cares more about [针对Subject B的差异展开]. Therefore, this first difference shows that they are very distinct in this area.

**Body 2 (不同点 2：[不同点2中文])**
Second, there is a huge gap between $topicA and $topicB when it comes to [不同点2核心词]. This means they face entirely different situations. For instance, $topicA is known for [针对Subject A的差异展开], while $topicB is driven by [针对Subject B的差异展开]. As a result, we can see that their developments in this field are not the same.

**Body 3 (不同点 3：[不同点3中文])**
Third, $topicA and $topicB are very different because of [不同点3核心词]. On one hand, the growth of $topicA relies on [针对Subject A的差异展开]. On the other hand, the success of $topicB comes from [针对Subject B的差异展开]. Consequently, this final point clearly demonstrates that these two subjects have different paths.

**Conclusion**
In conclusion, although $topicA and $topicB have some connections, their differences are very obvious. As mentioned above, they have different focus on [不同点1核心词], have a huge gap in [不同点2核心词], and are driven by different choices in [不同点3核心词]. Therefore, it is clear that these two subjects have different paths in many ways.

---

# 📂 EXCLUSIVE LEXICAL NOTES
### 📂 专属词组笔记【生成的场景标签】
提取你在上述两篇文章的 Body 段细节描述中所使用的核心词组。

💡 **朴素版词组（想得起、用着顺）**
- 中文意思 1：[英文朴素词组 1]
- 中文意思 2：[英文朴素词组 2]
- 中文意思 3：[英文朴素词组 3]

💎 **高级版词组（拿 A+、惊艳教授）**
(高级学术替代词组必须在范文里实际使用过，并且必须使用 ==双等号== 将其包裹起来，例如 ==adhere to==，以便进行前端高亮显示)
- 中文意思 1：[对应的高级学术替代词组 1]
- 中文意思 2：[对应的高级学术替代词组 2]
- 中文意思 3：[对应的高级学术替代词组 3]
""";
 
    return await service.summarize(prompt, strategy: PromptStrategy.essay, mode: _currentMode, unit: _currentUnit);
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
