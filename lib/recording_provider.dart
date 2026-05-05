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

enum AIProvider { groq, siliconFlow }

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

class RecordingProvider extends ChangeNotifier {
  final AudioRecorder _audioRecorder = AudioRecorder();
  OpenAIService? _aiService;
  OpenAIService? _fastAiService;
  OpenAIService? _groqService;
  AIOrchestratorService? _orchestrator;
  
  StreamSubscription? _fastSub;
  StreamSubscription? _accurateSub;
  
  AIProvider _selectedProvider = AIProvider.groq;
  int _sliceDuration = 5; 
  bool _useBluetooth = false;
  bool _isDarkMode = false;
  bool _enableFinalRecap = false;
  bool _enableLectureDiscovery = false;
  final Map<AIProvider, String> _apiKeys = {
    AIProvider.siliconFlow: "",
    AIProvider.groq: "",
  };
  
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
  String? get statusMessage => _statusMessage;
  String? get finalReviewContent => _finalReviewContent;
  bool get isGeneratingFinalReview => _isGeneratingFinalReview;
  String? get lastExportedPath => _lastExportedPath;
  String? get identifiedLectureContext => _identifiedLectureContext;
  bool get hasRecoveredCache => _hasRecoveredCache;

  RecordingProvider() { _init(); }

  Future<void> _init() async {
    await _loadSettings();
    await _initializeAudioSession();
    await _checkRecoveryCache();
  }

  String getApiKeyFor(AIProvider provider) => _apiKeys[provider] ?? "";

  Future<void> updateSettings({
    AIProvider? provider, String? key, int? duration, bool? useBluetooth, bool? isDarkMode, bool? enableFinalRecap, bool? enableLectureDiscovery,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (duration != null) { await prefs.setInt('slice_duration', duration); _sliceDuration = duration; }
    if (useBluetooth != null) { await prefs.setBool('use_bluetooth', useBluetooth); _useBluetooth = useBluetooth; }
    if (isDarkMode != null) { await prefs.setBool('is_dark_mode', isDarkMode); _isDarkMode = isDarkMode; }
    if (enableFinalRecap != null) { await prefs.setBool('enableFinalRecap', enableFinalRecap); _enableFinalRecap = enableFinalRecap; }
    if (enableLectureDiscovery != null) { await prefs.setBool('enableLectureDiscovery', enableLectureDiscovery); _enableLectureDiscovery = enableLectureDiscovery; }
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
    final pIndex = prefs.getInt('selected_provider') ?? 0;
    _selectedProvider = AIProvider.values[pIndex];
    for (var p in AIProvider.values) {
      final key = prefs.getString('api_key_${p.name}');
      if (key != null && key.isNotEmpty) _apiKeys[p] = key;
    }
    _updateService();
  }

  void _updateService() {
    _fastSub?.cancel();
    _accurateSub?.cancel();
    _orchestrator?.dispose();
    
    final siliconKey = _apiKeys[AIProvider.siliconFlow];
    final groqKey = _apiKeys[AIProvider.groq];

    // [Architect: Load Balancing Strategy]
    // 1. Groq 负责 STT (快轨)
    if (groqKey != null && groqKey.isNotEmpty) {
      _groqService = OpenAIService(
        apiKey: groqKey, 
        baseUrl: "https://api.groq.com/openai/v1", 
        defaultModel: "llama-3.3-70b-versatile",
        whisperModel: "whisper-large-v3"
      );
      _fastAiService = _groqService;
    }

    // 2. SiliconFlow 负责 翻译与总结 (慢轨)
    if (siliconKey != null && siliconKey.isNotEmpty) {
      final siliconService = OpenAIService(
        apiKey: siliconKey, 
        baseUrl: "https://api.siliconflow.cn/v1", 
        defaultModel: "Qwen/Qwen2.5-72B-Instruct", 
        whisperModel: "FunAudioLLM/SenseVoiceSmall"
      );
      _aiService = siliconService;
      // 如果没有 Groq，STT 也用 SiliconFlow
      _fastAiService ??= siliconService;
    } else if (_groqService != null) {
      // 如果没有 SiliconFlow，则全部使用 Groq (可能面临 Rate Limit)
      _aiService = _groqService;
    }
    
    if (_aiService != null && _fastAiService != null) {
      _orchestrator = AIOrchestratorService(
        sttService: _fastAiService!,
        translationService: _aiService!,
      );
      
      _fastSub = _orchestrator!.fastEnglishStream.listen((result) {
        final index = _allNotes.indexWhere((n) => n.id == result.noteId);
        if (index != -1) {
          _allNotes[index].transcript = result.content;
          // 仅在有有效内容时更新上下文
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

    // [Architect: Summary Flush] 强制结算最后一段小结素材（不足 60 秒的部分）
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
    
    // [Architect: Final Sync] 等待所有后台翻译/总结任务彻底完成
    _statusMessage = "Finalizing AI tasks...";
    notifyListeners();
    await ApiScheduler().untilIdle();

    notifyListeners();
    if (_enableFinalRecap) {
      await generateFinalAcademicReview();
    } else {
      await _exportToMarkdown();
    }
  }

  Future<String> _getTempPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
  }

  Future<void> _processAudio(String path) async {
    if (_orchestrator == null) return;
    try {
      final stitchResult = await compute(_backgroundStitchTask, StitchData(_lastAudioTail, path, kTailSize));
      final processedPath = stitchResult['path'] as String;
      _lastAudioTail = List<int>.from(stitchResult['newTail']);

      final currentNote = InsightNote(summary: '', transcript: '...', timestamp: DateTime.now(), isProcessing: true);
      final noteId = currentNote.id; // 提前获取 ID
      _allNotes.add(currentNote);
      notifyListeners();

      // 传入 ID 和状态回调进行任务绑定
      await _orchestrator!.processAudioSegment(
        noteId, 
        processedPath, 
        context: _lastTranscript,
        onStatus: (msg) {
          _statusMessage = msg;
          notifyListeners();
        },
      );
      
      // 更新该 ID 对应的笔记状态
      final index = _allNotes.indexWhere((n) => n.id == noteId);
      if (index != -1) {
        _allNotes[index].isProcessing = false;
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
    if (_aiService == null) return;
    final summary = await _aiService!.summarize(text, provider: AIProvider.siliconFlow);
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
      final recap = await _aiService!.summarize(material, strategy: PromptStrategy.recap, provider: AIProvider.siliconFlow);
      _finalReviewContent = recap;
    }
    _isGeneratingFinalReview = false; 
    notifyListeners();
    await _exportToMarkdown();
  }

  Future<void> _exportToMarkdown() async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
      final filename = "Jeff_Notes_$dateStr.md";
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');

      final StringBuffer sb = StringBuffer();

      // ── 标题 ──────────────────────────────────────────────
      sb.writeln("# Academic Lecture Session");
      sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}");
      sb.writeln("**Context:** ${_identifiedLectureContext ?? 'General Academic Lecture'}");
      sb.writeln();

      // ── 第一部分：AI 深度复盘 ─────────────────────────────
      if (_finalReviewContent != null && _finalReviewContent!.isNotEmpty) {
        sb.writeln("---");
        sb.writeln();
        sb.writeln("## Part 1 · AI Academic Review");
        sb.writeln();
        sb.writeln(_finalReviewContent);
        sb.writeln();
      }

      // ── 第二部分：分段小结 ───────────────────────────────
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

      // ── 第三部分：完整中英对照脚本 ───────────────────────
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
          // 跳过静音或空白片段
          if (note.transcript.isEmpty ||
              note.transcript == '...' ||
              note.transcript.startsWith('[Silence') ||
              note.transcript.startsWith('[Error')) continue;

          pendingEng.add(note.transcript);

          // 当遇到包含翻译的节点时，将积累的英文合并输出
          if (note.translatedContent != null && note.translatedContent!.isNotEmpty) {
            sb.writeln("**[$blockCount] ENG:** ${pendingEng.join(' ')}");
            sb.writeln("**[$blockCount] CHN:** ${note.translatedContent}");
            sb.writeln();
            pendingEng.clear();
            blockCount++;
          }
        }

        // 处理最后可能残留的未翻译英文
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
    super.dispose();
  }
}
