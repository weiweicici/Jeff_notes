import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'openai_service.dart';
import 'ai_orchestrator_service.dart';
import 'api_scheduler.dart';
import 'prompt_provider.dart';
import 'models.dart';

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

Future<Map<String, dynamic>> _backgroundStitchTask(StitchData data) async {
  try {
    final currentFile = File(data.path);
    if (!currentFile.existsSync()) return {'path': data.path, 'newTail': data.tail};
    final currentBytes = await currentFile.readAsBytes();
    if (currentBytes.length < 44) return {'path': data.path, 'newTail': data.tail};
    final currentPcm = currentBytes.sublist(44);
    final List<int> combinedPcm = [...data.tail, ...currentPcm];
    final header = _generateWavHeaderStatic(combinedPcm.length);
    final stitchedBytes = Uint8List.fromList([...header, ...combinedPcm]);
    final stitchedPath = "${data.path}_stitched.wav";
    await File(stitchedPath).writeAsBytes(stitchedBytes);
    List<int> nextTail = [];
    if (currentBytes.length > data.tailSize + 44) {
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

class LectureSession {
  final String id;
  final List<InsightNote> notes = [];
  AIOrchestratorService? orchestrator;
  StreamSubscription? fastSub;
  StreamSubscription? accurateSub;
  String? finalReviewContent;
  String? statusMessage;
  int lastSummaryTotalCount = 0;
  bool isFinalizing = false;
  String? lectureContext;
  final AppMode mode;
  final DateTime startTime;

  LectureSession({required this.id, required this.mode, this.lectureContext}) : startTime = DateTime.now();

  void dispose() {
    fastSub?.cancel();
    accurateSub?.cancel();
    orchestrator?.dispose();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'notes': notes.map((n) => n.toJson()).toList(),
    'finalReviewContent': finalReviewContent,
    'lectureContext': lectureContext,
    'mode': mode.index,
    'startTime': startTime.toIso8601String(),
  };
}

class RecordingProvider extends ChangeNotifier {
  final AudioRecorder _audioRecorder = AudioRecorder();
  OpenAIService? _aiService;
  OpenAIService? _fastAiService;
  OpenAIService? _groqService;
  OpenAIService? _summaryService;
  
  LectureSession? _activeSession;
  final List<LectureSession> _finalizingSessions = [];
  final _sessionReadyController = StreamController<String>.broadcast();
  Stream<String> get sessionReadyStream => _sessionReadyController.stream;
  
  AIProvider _selectedProvider = AIProvider.groq;
  AppMode _appMode = AppMode.lecture;
  int _sliceDuration = 5; 
  bool _useBluetooth = false;
  bool _isDarkMode = false;
  bool _enableFinalRecap = false;
  bool _enableLectureDiscovery = false;
  final Map<AIProvider, String> _apiKeys = {
    AIProvider.siliconFlow: "sk-ovsutjuybcrndvdxfskcooqsfwpwgtxlqcnolnbssrzzaszi",
    AIProvider.groq: "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",
  };
  
  String? _lastTranscript;
  List<int> _lastAudioTail = []; 
  Timer? _sliceTimer;
  bool _isRecording = false;
  bool _isPending = false;
  static const int kTailSize = 25600;

  String? _lastExportedPath;
  bool _hasRecoveredCache = false;

  // UI Delegates
  List<InsightNote> get notes {
    if (_activeSession != null) return _activeSession!.notes.reversed.toList();
    if (_finalizingSessions.isNotEmpty) return _finalizingSessions.first.notes.reversed.toList();
    return [];
  }
  bool get isRecording => _isRecording;
  bool get isPending => _isPending;
  AIProvider get selectedProvider => _selectedProvider;
  AppMode get appMode => _appMode;
  int get sliceDuration => _sliceDuration;
  bool get useBluetooth => _useBluetooth;
  bool get isDarkMode => _isDarkMode;
  bool get enableFinalRecap => _enableFinalRecap;
  bool get enableLectureDiscovery => _enableLectureDiscovery;
  String? get statusMessage => _activeSession?.statusMessage;
  AppMode get currentSessionMode => _activeSession?.mode ?? _appMode;
  
  // 返回当前正在生成的或最近完成的复盘
  String? get finalReviewContent {
    if (_activeSession?.finalReviewContent != null) return _activeSession!.finalReviewContent;
    for (var s in _finalizingSessions) {
      if (s.finalReviewContent != null) return s.finalReviewContent;
    }
    return null;
  }

  bool get isGeneratingFinalReview => 
      (_activeSession?.isFinalizing ?? false) || 
      _finalizingSessions.any((s) => s.isFinalizing);

  String? get lastExportedPath => _lastExportedPath;
  String? get identifiedLectureContext => _activeSession?.lectureContext ?? _finalizingSessions.firstOrNull?.lectureContext;
  bool get hasRecoveredCache => _hasRecoveredCache;

  RecordingProvider() { _init(); }

  Future<void> _init() async {
    await _loadSettings();
    await _initializeAudioSession();
    await _checkRecoveryCache();
  }

  String getApiKeyFor(AIProvider provider) => _apiKeys[provider] ?? "";

  Future<void> updateSettings({
    AIProvider? provider, AppMode? mode, String? key, int? duration, bool? useBluetooth, bool? isDarkMode, bool? enableFinalRecap, bool? enableLectureDiscovery,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (duration != null) { await prefs.setInt('slice_duration', duration); _sliceDuration = duration; }
    if (useBluetooth != null) { await prefs.setBool('use_bluetooth', useBluetooth); _useBluetooth = useBluetooth; }
    if (isDarkMode != null) { await prefs.setBool('is_dark_mode', isDarkMode); _isDarkMode = isDarkMode; }
    if (enableFinalRecap != null) { await prefs.setBool('enableFinalRecap', enableFinalRecap); _enableFinalRecap = enableFinalRecap; }
    if (enableLectureDiscovery != null) { await prefs.setBool('enableLectureDiscovery', enableLectureDiscovery); _enableLectureDiscovery = enableLectureDiscovery; }
    if (mode != null) { await prefs.setInt('app_mode', mode.index); _appMode = mode; }
    if (provider != null) {
      _selectedProvider = provider;
      await prefs.setInt('selected_provider', provider.index);
      if (key != null) { await prefs.setString('api_key_${provider.name}', key); _apiKeys[provider] = key; }
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
    _appMode = AppMode.values[prefs.getInt('app_mode') ?? 0];
    final pIndex = prefs.getInt('selected_provider') ?? 0;
    _selectedProvider = AIProvider.values[pIndex];
    for (var p in AIProvider.values) {
      final key = prefs.getString('api_key_${p.name}');
      if (key != null && key.isNotEmpty) _apiKeys[p] = key;
    }
    _updateService();
  }

  void _updateService() {
    final siliconKey = _apiKeys[AIProvider.siliconFlow];
    final groqKey = _apiKeys[AIProvider.groq];

    if (groqKey != null && groqKey.isNotEmpty) {
      _groqService = OpenAIService(
        apiKey: groqKey, 
        baseUrl: "https://api.groq.com/openai/v1", 
        defaultModel: "llama-3.3-70b-versatile",
        whisperModel: "whisper-large-v3"
      );
      _fastAiService = _groqService;
    }

    if (siliconKey != null && siliconKey.isNotEmpty) {
      _aiService = OpenAIService(
        apiKey: siliconKey, 
        baseUrl: "https://api.siliconflow.cn/v1", 
        defaultModel: "Qwen/Qwen2.5-72B-Instruct", 
        whisperModel: "FunAudioLLM/SenseVoiceSmall"
      );
      _summaryService = OpenAIService(
        apiKey: siliconKey, 
        baseUrl: "https://api.siliconflow.cn/v1", 
        defaultModel: "deepseek-ai/DeepSeek-V3"
      );
      _fastAiService ??= _aiService;
    } else if (_groqService != null) {
      _aiService = _groqService;
    }
  }

  void _setupSessionOrchestrator(LectureSession session) {
    if (_aiService != null && _fastAiService != null) {
      session.orchestrator = AIOrchestratorService(
        sttService: _fastAiService!,
        translationService: _aiService!,
        sessionId: session.id,
      );
      
      session.fastSub = session.orchestrator!.fastEnglishStream.listen((result) {
        final index = session.notes.indexWhere((n) => n.id == result.noteId);
        if (index != -1) {
          session.notes[index].transcript = result.content;
          if (result.content != "[Silence/Empty]" && !result.content.startsWith("[")) {
            _lastTranscript = result.content;
          }
          if (_activeSession == session) notifyListeners();
        }
      });
      
      session.accurateSub = session.orchestrator!.accurateChineseStream.listen((result) {
        final index = session.notes.indexWhere((n) => n.id == result.noteId);
        if (index != -1) {
          session.notes[index].translatedContent = result.content;
          if (_activeSession == session) {
            _saveShadowCache();
            notifyListeners();
          }
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
    if (_isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
    _isPending = false; notifyListeners();
  }

  Future<void> startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      _updateService(); 
      _isRecording = true;
      _lastAudioTail = [];
      _lastTranscript = null;
      
      // 创建新会话
      final sessionId = "sess_${DateTime.now().millisecondsSinceEpoch}";
      _activeSession = LectureSession(id: sessionId, mode: _appMode);
      _setupSessionOrchestrator(_activeSession!);
      
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

    final sessionToFinalize = _activeSession;
    if (sessionToFinalize == null) return;

    // 立即解绑 activeSession，允许用户开始新录音
    _activeSession = null; 
    _finalizingSessions.insert(0, sessionToFinalize);
    notifyListeners();

    // 后台静默处理
    unawaited(_finalizeSession(sessionToFinalize));
  }

  Future<void> _finalizeSession(LectureSession session) async {
    session.isFinalizing = true;
    session.statusMessage = "Flushing buffer...";
    notifyListeners();

    if (session.orchestrator != null) {
      await session.orchestrator!.flush(onStatus: (msg) {
        session.statusMessage = msg;
        notifyListeners();
      });
    }

    // 强制结算最后一段小结 (讨论模式不需要)
    if (session.mode != AppMode.discussion) {
      final currentTranscripts = session.notes.where((n) => !n.isSummary).toList();
      if (currentTranscripts.length > session.lastSummaryTotalCount) {
        final remainingText = currentTranscripts
            .skip(session.lastSummaryTotalCount)
            .map((e) => e.transcript)
            .join(" ");
        if (remainingText.trim().isNotEmpty) {
          await _performBatchSummary(session, remainingText, "final_flush_${DateTime.now().millisecondsSinceEpoch}");
        }
      }
    }
    
    session.statusMessage = "Finalizing AI tasks...";
    notifyListeners();
    
    // [Fix: Reliable Wait] 主动轮询，等待所有 note 的 STT 和翻译结果全部落盘
    // 确保导出时中英文脚本都是完整的
    const maxWaitMs = 30000;
    const pollIntervalMs = 500;
    int waitedMs = 0;
    while (waitedMs < maxWaitMs) {
      final pendingSTT = session.notes.where((n) =>
        !n.isSummary && (n.transcript == '...' || n.transcript.isEmpty)
      ).length;
      
      // 检查翻译：如果 transcript 已经有了且不是标记位，但翻译还是空的，说明还在翻译中
      final pendingTrans = session.notes.where((n) =>
        !n.isSummary && 
        n.transcript != '...' && 
        n.transcript.isNotEmpty && 
        !n.transcript.startsWith('[') && 
        (n.translatedContent == null || n.translatedContent!.isEmpty)
      ).length;

      if (pendingSTT == 0 && pendingTrans == 0) break;
      
      debugPrint("[Finalize] Waiting: STT=$pendingSTT, Trans=$pendingTrans (${waitedMs}ms)");
      await Future.delayed(const Duration(milliseconds: pollIntervalMs));
      waitedMs += pollIntervalMs;
    }
    debugPrint("[Finalize] All tasks settled after ${waitedMs}ms.");
    session.finalReviewContent = "*(Diagnostic: Buffer wait loop took ${waitedMs / 1000} seconds)*\n\n";

    if (_enableFinalRecap) {
      await _generateFinalReviewForSession(session);
    } else {
      await _exportSessionToMarkdown(session);
    }

    session.isFinalizing = false;
    session.statusMessage = "Exported";
    session.dispose(); 
    notifyListeners();
    
    final content = session.finalReviewContent;
    if (content != null && content.isNotEmpty) {
      _sessionReadyController.add(content);
    }
  }

  Future<String> _getTempPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
  }

  Future<void> _processAudio(String path) async {
    final session = _activeSession;
    if (session == null || session.orchestrator == null) return;
    String? processedPath;
    try {
      final stitchResult = await compute(_backgroundStitchTask, StitchData(_lastAudioTail, path, kTailSize));
      processedPath = stitchResult['path'] as String;
      _lastAudioTail = List<int>.from(stitchResult['newTail']);

      final currentNote = InsightNote(summary: '', transcript: '...', timestamp: DateTime.now(), isProcessing: true);
      final noteId = currentNote.id;
      session.notes.add(currentNote);
      notifyListeners();

      await session.orchestrator!.processAudioSegment(
        noteId, 
        processedPath, 
        context: _lastTranscript,
        onStatus: (msg) {
          session.statusMessage = msg;
          notifyListeners();
        },
      );
      
      final index = session.notes.indexWhere((n) => n.id == noteId);
      if (index != -1) {
        session.notes[index].isProcessing = false;
        notifyListeners();
      }

      final totalCount = session.notes.where((n) => !n.isSummary).length;
      // ✅ 只在非讨论模式下生成中间小结
      if (session.mode != AppMode.discussion && totalCount > 0 && totalCount % 12 == 0) {
        final combinedText = session.notes.where((n) => !n.isSummary).skip(session.lastSummaryTotalCount).map((e) => e.transcript).join(" ");
        session.lastSummaryTotalCount = totalCount;
        unawaited(_performBatchSummary(session, combinedText, "cluster_${DateTime.now().millisecondsSinceEpoch}"));
      }
    } catch (e) {
      debugPrint("Pipeline Error: $e");
    } finally {
      // [Architect: Storage Hygiene] 处理完成后清理原始和拼接后的临时文件
      final filesToDelete = [path];
      if (processedPath != null && processedPath != path) {
        filesToDelete.add(processedPath);
      }
      _cleanupTempFiles(filesToDelete);
    }
  }

  void _cleanupTempFiles(List<String> paths) {
    for (final p in paths) {
      try {
        final f = File(p);
        if (f.existsSync()) {
          f.deleteSync();
          debugPrint("[Cleanup] Deleted temp file: $p");
        }
      } catch (e) {
        debugPrint("[Cleanup] Failed to delete $p: $e");
      }
    }
  }

  Future<void> _performBatchSummary(LectureSession session, String text, String? clusterId) async {
    if (_aiService == null) return;
    final strategy = session.mode == AppMode.discussion ? PromptStrategy.discussion : PromptStrategy.general;
    final summary = await _aiService!.summarize(text, strategy: strategy, provider: AIProvider.siliconFlow, mode: session.mode);
    final summaryNote = InsightNote(summary: summary, transcript: '', timestamp: DateTime.now(), isSummary: true, clusterId: clusterId);
    session.notes.add(summaryNote);
    if (_activeSession == session) _saveShadowCache();
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
      _activeSession = LectureSession(
        id: "recovered_${DateTime.now().millisecondsSinceEpoch}",
        mode: AppMode.values[data['mode'] ?? 0]
      );
      _activeSession!.notes.addAll((data['notes'] as List).map((i) => InsightNote.fromJson(i)).toList());
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
    if (_activeSession == null) return;
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/shadow_draft.json');
    await file.writeAsString(jsonEncode(_activeSession!.toJson()));
  }

  Future<void> _generateFinalReviewForSession(LectureSession session) async {
    if (_aiService == null) return;
    
    String material;
    if (session.mode == AppMode.discussion) {
      // 讨论模式：提供中英文对照给 AI 以便生成更好的双语总结
      material = session.notes.where((n) =>
        !n.isSummary &&
        n.transcript.isNotEmpty &&
        n.transcript != '...' &&
        !n.transcript.startsWith('[')
      ).map((n) => "English: ${n.transcript}\nChinese: ${n.translatedContent ?? ''}").join("\n\n");
    } else {
      // 讲座模式有中间小结，基于小结生成
      material = session.notes.where((n) => n.isSummary).map((n) => n.summary).join("\n\n");
    }
    
    if (material.trim().isEmpty) { 
      session.finalReviewContent = "Not enough material."; 
    } else {
      // ✅ 使用专门的总结服务 (DeepSeek-V3)
      final service = _summaryService ?? _aiService!;
      final stopwatch = Stopwatch()..start();
      final recap = await service.summarize(material, strategy: PromptStrategy.recap, provider: AIProvider.siliconFlow, mode: session.mode);
      stopwatch.stop();
      session.finalReviewContent = (session.finalReviewContent ?? "") + recap + "\n\n*(Diagnostic: Summary API took \${stopwatch.elapsed.inSeconds} seconds)*";
    }
    notifyListeners();
    await _exportSessionToMarkdown(session);
  }

  Future<void> _exportSessionToMarkdown(LectureSession session) async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
      final isDiscussion = session.mode == AppMode.discussion;
      final filename = isDiscussion
          ? "Jeff_Discussion_$dateStr.md"
          : "Jeff_Notes_$dateStr.md";
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');

      final StringBuffer sb = StringBuffer();

      // ✅ Bug Fix: 根据 session.mode 动态切换文件头，彻底消灭硬编码讲座标题
      if (isDiscussion) {
        sb.writeln("# Group Discussion Session");
        sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(session.startTime)}");
        sb.writeln();
      } else {
        sb.writeln("# Academic Lecture Session");
        sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(session.startTime)}");
        sb.writeln("**Context:** ${session.lectureContext ?? 'General Academic Lecture'}");
        sb.writeln();
      }

      if (session.finalReviewContent != null && session.finalReviewContent!.isNotEmpty) {
        sb.writeln("---");
        sb.writeln(isDiscussion
            ? "\n## Pathways Group Discussion (Parts 1–2)\n"
            : "\n## Pathways Academic Analysis (Parts 1–4)\n");
        sb.writeln(session.finalReviewContent);
        sb.writeln();
      }

      // ✅ Bug Fix: 讨论模式下，彻底跳过 "Part 2 · 60s Block Summaries" 输出
      if (!isDiscussion) {
        final summaries = session.notes.where((n) => n.isSummary).toList();
        if (summaries.isNotEmpty) {
          sb.writeln("---\n\n## Part 2 · 60s Block Summaries\n");
          for (int i = 0; i < summaries.length; i++) {
            sb.writeln("### Block ${i + 1}");
            sb.writeln(summaries[i].summary);
            sb.writeln();
          }
        }
      }

      final transcripts = session.notes.where((n) => !n.isSummary).toList();
      if (transcripts.isNotEmpty) {
        if (isDiscussion) {
          // 讨论模式：英文稿在前 (Part 3)，中文稿在后 (Part 4)
          sb.writeln("---\n\n## Part 3: 英文全文原稿 (Full English Script)\n");
          for (final note in transcripts) {
            final transcript = note.transcript;
            if (transcript.isNotEmpty && transcript != '...' && !transcript.startsWith('[')) {
              sb.write("$transcript ");
            }
          }
          sb.writeln("\n\n---\n");
          sb.writeln("## Part 4: 中文全文翻译 (Full Chinese Translation)\n");
          for (final note in transcripts) {
            final content = note.translatedContent;
            if (content != null && content.isNotEmpty && !content.startsWith('[') && content != '...') {
              sb.write("$content ");
            }
          }
          sb.writeln();
        } else {
          // 讲座模式：原有结构保持不变
          sb.writeln("---\n\n## Part 3 · Full Chinese Transcript\n");
          for (final note in transcripts) {
            final content = note.translatedContent;
            if (content != null && content.isNotEmpty && !content.startsWith('[') && content != '...') {
              sb.write("$content ");
            }
          }
          sb.writeln("\n\n## Part 4 · Full English Transcript\n");
          for (final note in transcripts) {
            final transcript = note.transcript;
            if (transcript.isNotEmpty && transcript != '...' && !transcript.startsWith('[')) {
              sb.write("$transcript ");
            }
          }
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
    _activeSession?.dispose();
    for (var s in _finalizingSessions) { s.dispose(); }
    _sliceTimer?.cancel();
    _sessionReadyController.close();
    _audioRecorder.dispose();
    super.dispose();
  }
}
