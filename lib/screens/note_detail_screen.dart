import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import '../recording_provider.dart';
import '../utils/pdf_service.dart';
import '../services/reading_quiz_service.dart';
import '../widgets/academic_markdown.dart';
import '../widgets/tts_player_bar.dart';
import '../services/supabase_config.dart';
import '../services/tts_service.dart';
import '../models/vocab_card.dart';
import '../services/vocab_service.dart';
import '../services/vocab_extractor_service.dart';
import 'smart_vocab_screen.dart';
import '../services/wakelock_service.dart';
import '../main.dart';

class NoteDetailScreen extends StatefulWidget {
  final File file;
  const NoteDetailScreen({super.key, required this.file});
  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  bool _isExporting = false;
  final GlobalKey _pdfButtonKey = GlobalKey();
  final _textController = TextEditingController();
  final _karaokeScrollController = ScrollController();
  final List<GlobalKey> _paragraphKeys = [];
  int _lastActiveIndex = -1;
  String? _lastLoadedContent;
  String? _chineseOnlyText;
  String? _englishOnlyText;
  bool _showRendered = true; // true = MarkdownBody（可见高亮），false = TextField（原始文字）
  bool _userIsInteracting = false;
  Timer? _resumeAutoScrollTimer;
  int _lastLockscreenKaraokeIdx = -1;


  void _onUserInteractionStart() {
    _resumeAutoScrollTimer?.cancel();
    if (!_userIsInteracting) {
      _userIsInteracting = true;
    }
  }

  void _onUserInteractionEnd() {
    _resumeAutoScrollTimer?.cancel();
    _resumeAutoScrollTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() {
          _userIsInteracting = false;
        });
        _scrollToActiveParagraph();
      }
    });
  }

  void _scrollToActiveParagraph() {
    if (_userIsInteracting) return;
    if (_lastActiveIndex >= 0 && _lastActiveIndex < _paragraphKeys.length) {
      final keyContext = _paragraphKeys[_lastActiveIndex].currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.3,
        );
      }
    }
  }

  void _updateParagraphKeys(int count) {
    if (_paragraphKeys.length != count) {
      _paragraphKeys.clear();
      for (int i = 0; i < count; i++) {
        _paragraphKeys.add(GlobalKey());
      }
    }
  }

  /// 将一段文本按句子切分为卡拉OK展示单元。
  /// 支持中文（。！？）和英文（. ! ?)句尾，每个展示单元最多 maxLen 个字符。
  /// 如果文本足够短则直接返回原内容。
  List<String> _splitIntoSentences(String text, {int maxLen = 120}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return [];
    if (trimmed.length <= maxLen) return [trimmed];

    // 中文句尾切分：保留切分符
    final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed);
    final splitter = hasChinese
        ? RegExp(r'(?<=[\u3002\uff01\uff1f\u2026])')
        : RegExp(r'(?<=[.!?])\s+');

    final rawSentences = trimmed.split(splitter)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (rawSentences.length <= 1) return [trimmed]; // 没有句尾符号，原文返回

    // 将句子分组：每组长度不超过 maxLen
    final chunks = <String>[];
    var buf = '';
    for (final sentence in rawSentences) {
      if (buf.isEmpty) {
        buf = sentence;
      } else if ((buf + sentence).length <= maxLen) {
        buf += sentence; // 中文直接拼，英文加空格
      } else {
        chunks.add(buf);
        buf = sentence;
      }
    }
    if (buf.isNotEmpty) chunks.add(buf);
    return chunks.isEmpty ? [trimmed] : chunks;
  }

  /// 根据微软 Neural TTS 发音特性与标点停顿估算语音朗读权重时长。
  /// 微软 Edge Neural TTS 会在句尾标点 (。！？.!?) 停顿 ~600ms，在句中逗号 (，；:) 停顿 ~300ms。
  /// 给予标点符号权重可精确补齐朗读与自然停顿时间，彻底解决字幕提前 1.5 秒跳下一个卡片的问题。
  double _getSpeechWeight(String text) {
    double w = 0.0;
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (RegExp(r'[。！？!?…\n]').hasMatch(char)) {
        w += 6.0; // 句尾标点/换行：相当于约 600ms 自然停顿
      } else if (RegExp(r'[，；：,;:]').hasMatch(char)) {
        w += 3.0; // 句中逗号/分号：相当于约 300ms 停顿
      } else if (RegExp(r'[\u4e00-\u9fff]').hasMatch(char)) {
        w += 1.0; // 单个汉字发音基准
      } else if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
        w += 0.4; // 英文字母发音基准
      } else {
        w += 0.5;
      }
    }
    return w > 0 ? w : 1.0;
  }

  @override
  void dispose() {
    _resumeAutoScrollTimer?.cancel();
    TtsService().stop();
    WakelockService.disable();
    _textController.dispose();
    _karaokeScrollController.dispose();
    super.dispose();
  }

  /// 提取 MD 文件中的纯中文部分，供 TTS 播放。
  void _seekToSentenceIndex(int targetIdx, List<String> karaokeParas, Duration duration, double totalWeight, bool isChineseMode) {
    if (targetIdx < 0 || targetIdx >= karaokeParas.length || duration.inMilliseconds <= 0 || totalWeight <= 0) return;
    double cumulativeBefore = 0.0;
    for (int i = 0; i < targetIdx; i++) {
      cumulativeBefore += _getSpeechWeight(karaokeParas[i]);
    }
    final targetPosMs = (cumulativeBefore / totalWeight * duration.inMilliseconds).round();
    final targetPos = Duration(milliseconds: targetPosMs);
    final tts = TtsService();
    if (isChineseMode) {
      tts.seekChinese(targetPos);
    } else {
      globalAudioHandler.seek(targetPos);
    }
  }

  /// 策略 1：逐行解析——找到 '### 中文全文' 后开始收集，遇到下一个 ### 或 ## 标题时停止。
  ///         这比正则可靠得多，不受换行数量影响。
  /// 策略 2：FreeTalk 模式 — 第一个 \n\n 之前的内容（中文块在前）
  /// 策略 3：兜底 — 提取含 >=3 个汉字的行
  String _extractChineseOnly(String fullText) {
    final lines = fullText.split('\n');
    bool inChineseSection = false;
    final capturedLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();

      // 1. 找到中文全文 / 中文翻译 / Part 2 标题 → 开始收集
      if (trimmed.contains('中文全文') ||
          trimmed.contains('中文翻译') ||
          trimmed.contains('Part 2')) {
        inChineseSection = true;
        continue;
      }

      // 2. 遇到无关下一个主标题 → 停止收集
      if (inChineseSection &&
          (trimmed.startsWith('### ') ||
           trimmed.startsWith('## ') ||
           trimmed.startsWith('# '))) {
        final isContinuationHeader =
            trimmed.contains('中文全文') ||
            trimmed.contains('中文翻译') ||
            trimmed.contains('Part 2') ||
            trimmed.contains('翻译');
        if (!isContinuationHeader) break;
        continue;
      }

      // 3. 过滤掉纯分隔线行（如 --- / ===）
      if (trimmed.startsWith('---') || trimmed.startsWith('===')) {
        continue;
      }

      if (inChineseSection && trimmed.isNotEmpty) {
        capturedLines.add(trimmed);
      }
    }

    if (capturedLines.isNotEmpty) return capturedLines.join('\n\n');

    // 策略 2：FreeTalk 模式
    final fileName = widget.file.path.split('/').last;
    if (fileName.contains('FreeTalk')) {
      final firstBlank = fullText.indexOf('\n\n');
      if (firstBlank > 0) {
        return fullText.substring(0, firstBlank).trim();
      }
    }

    // 策略 3：兜底 — 提取含 >=3 个汉字的段落/行
    final chineseLines = lines.where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('**') ||
          trimmed.startsWith('---')) return false;
      final cjkCount =
          RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]').allMatches(trimmed).length;
      return cjkCount >= 3;
    }).toList();

    if (chineseLines.isNotEmpty) return chineseLines.join('\n\n');
    return '';
  }

  /// 提取 MD 文件中的纯英文部分，供 AI TTS 播放。
  String _extractEnglishOnly(String fullText) {
    final lines = fullText.split('\n');
    bool inEnglishSection = false;
    final capturedLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.contains('英文全文') ||
          trimmed.contains('English Transcript') ||
          trimmed.contains('English Essay') ||
          trimmed.contains('Part 1')) {
        inEnglishSection = true;
        continue;
      }

      if (inEnglishSection &&
          (trimmed.startsWith('### ') ||
           trimmed.startsWith('## ') ||
           trimmed.startsWith('# '))) {
        final isContinuationHeader =
            trimmed.contains('英文全文') ||
            trimmed.contains('English Transcript') ||
            trimmed.contains('English Essay') ||
            trimmed.contains('Part 1');
        if (!isContinuationHeader) break;
        continue;
      }

      // 过滤分隔线
      if (trimmed.startsWith('---') || trimmed.startsWith('===')) {
        continue;
      }

      if (inEnglishSection && trimmed.isNotEmpty) {
        capturedLines.add(trimmed);
      }
    }

    if (capturedLines.isNotEmpty) return capturedLines.join('\n\n');

    // 策略 2：FreeTalk 模式
    final fileName = widget.file.path.split('/').last;
    if (fileName.contains('FreeTalk')) {
      final firstBlank = fullText.indexOf('\n\n');
      if (firstBlank > 0 && firstBlank + 2 < fullText.length) {
        return fullText.substring(firstBlank + 2).trim();
      }
    }

    // 策略 3：兜底 — 严格过滤掉所有含汉字的行
    final purelyEnglishLines = lines.where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('---')) return false;
      final cjkCount =
          RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]').allMatches(trimmed).length;
      return cjkCount == 0 && trimmed.contains(RegExp(r'[a-zA-Z]'));
    }).toList();

    return purelyEnglishLines.join('\n\n');
  }



  Future<void> _exportPdf() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      final content = await widget.file.readAsString();
      final title = widget.file.path.split('/').last;

      // 获取按钮屏幕坐标，用于 iPad 上分享 Popover 的锚定位置
      Rect? bounds;
      final renderBox =
          _pdfButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final offset = renderBox.localToGlobal(Offset.zero);
        bounds = offset & renderBox.size;
      }

      await PdfService.exportToPdf(title, content, bounds: bounds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📄 PDF 已生成，请在分享面板中选择保存或分享'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint("PDF Export Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ PDF 导出失败: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _handleTranslateSelection(String text) async {
    final result = await ReadingQuizService.getTranslation(text);
    if (!mounted) return;
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.translate, size: 20),
            const SizedBox(width: 8),
            const Text('中文翻译'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: MarkdownBody(
            data: result,
            softLineBreak: true,
            selectable: true,
            styleSheet: getAcademicMarkdownStyle(context),
            extensionSet: md.ExtensionSet(
              [const md.FencedCodeBlockSyntax()],
              [md.EmojiSyntax(), HighlightSyntax()],
            ),
            builders: {'highlight': HighlightBuilder(context)},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _handleParaphraseSelection(String text) async {
    final result = await ReadingQuizService.getParaphrase(text);
    if (!mounted) return;
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.replay, size: 20),
            const SizedBox(width: 8),
            const Text('转述'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: MarkdownBody(
            data: result,
            softLineBreak: true,
            selectable: true,
            styleSheet: getAcademicMarkdownStyle(context),
            extensionSet: md.ExtensionSet(
              [const md.FencedCodeBlockSyntax()],
              [md.EmojiSyntax(), HighlightSyntax()],
            ),
            builders: {'highlight': HighlightBuilder(context)},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _extractSmartVocab(BuildContext context) async {
    final title = widget.file.path.split('/').last;
    final fullText = _textController.text;
    if (fullText.trim().isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(
              child: Text('正在使用 AI 提炼文本中的高频学术词汇与长难句剖析...', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );

    try {
      final cards = await VocabExtractorService.extractFromText(
        fullText,
        sourceTitle: title,
      );

      if (context.mounted) {
        Navigator.pop(context); // 关闭加载框
        if (cards.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ 未能提取到有效的生词卡片，请重试')),
          );
          return;
        }

        // 保存生词卡到持久化服务
        for (final card in cards) {
          await VocabService.instance.saveCard(card);
        }

        // 跳转到卡片复习界面
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SmartVocabScreen(
              initialCards: cards,
              sourceTitle: title,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 提炼失败: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.path.split('/').last),
        actions: [
          // 渲染模式切换按钮
          StatefulBuilder(
            builder: (context, setLocal) => IconButton(
              icon: Icon(
                _showRendered ? Icons.code : Icons.auto_awesome,
                size: 20,
              ),
              tooltip: _showRendered ? '查看原始 MD 文本' : '渲染 Markdown（高亮关键词）',
              onPressed: () => setState(() => _showRendered = !_showRendered),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.style_outlined, color: Colors.blueAccent),
            tooltip: '✨ AI 提炼生词与长难句',
            onPressed: () => _extractSmartVocab(context),
          ),
          _isExporting
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              : IconButton(
                  key: _pdfButtonKey,
                  icon: const Icon(Icons.picture_as_pdf),
                  tooltip: '导出 PDF',
                  onPressed: _exportPdf,
                ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制全文',
            onPressed: () async {
              try {
                final content = await widget.file.readAsString();
                Clipboard.setData(ClipboardData(text: content));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ 已复制到剪贴板')),
                  );
                }
              } catch (e) {
                debugPrint("Copy Error: $e");
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: '删除笔记',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('删除笔记'),
                  content: const Text('确定要删除这篇笔记吗？将同时清除本地文件与 Supabase 云端数据库记录。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                try {
                  final title = widget.file.path.split('/').last;
                  if (await widget.file.exists()) {
                    await widget.file.delete();
                  }
                  final wavFile = File(widget.file.path.replaceAll('.md', '.wav'));
                  if (await wavFile.exists()) {
                    await wavFile.delete();
                  }
                  await SupabaseConfig.client.from('archives').delete().eq('title', title);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ 笔记已完全删除')),
                    );
                    Navigator.pop(context, true);
                  }
                } catch (e) {
                  debugPrint("Delete Note Error: $e");
                }
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: widget.file.readAsString(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error loading file: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final currentContent = snapshot.data!;
          if (_lastLoadedContent != currentContent) {
            _textController.text = currentContent;
            _chineseOnlyText = _extractChineseOnly(currentContent);
            _englishOnlyText = _extractEnglishOnly(currentContent);
            _lastLoadedContent = currentContent;
          }

          final wavFile = File(widget.file.path.replaceAll('.md', '.wav'));
          final hasWav = wavFile.existsSync();

          return Column(
            children: [
              TtsPlayerBar(
                chineseText: _chineseOnlyText ?? '',
                englishText: _englishOnlyText ?? '',
                recordedAudioPath: hasWav ? wavFile.path : null,
                siliconFlowKey: context.read<RecordingProvider>().siliconFlowKey,
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: TtsService(),
                  builder: (context, _) => StreamBuilder<Duration>(
                  stream: TtsService().englishPositionStream,
                  builder: (context, posSnap) {
                    final tts = TtsService();
                    final isDark = Theme.of(context).brightness == Brightness.dark;

                    // 决定当前朗读的文本源和 seek 方法
                    final isChineseMode = tts.currentAudioType == ActiveAudioType.chinese;
                    final isEnglishMode = tts.currentAudioType == ActiveAudioType.english ||
                                         tts.currentAudioType == ActiveAudioType.recorded;

                    // 根据当前播放类型决定高亮用哪段文本
                    String displayText;
                    if (isChineseMode && _chineseOnlyText != null && _chineseOnlyText!.isNotEmpty) {
                      displayText = _chineseOnlyText!;
                    } else if (isEnglishMode && _englishOnlyText != null && _englishOnlyText!.isNotEmpty) {
                      displayText = _englishOnlyText!;
                    } else {
                      displayText = ''; // 未播放时不做卡拉OK高亮
                    }

                    // 计算卡拉OK句子切片（仅对抽取出的纯中/英文做句子切分，用于定位当前播放进度）
                    final List<String> karaokeParas = displayText.isNotEmpty
                        ? displayText
                            .split(RegExp(r'\n\n+'))
                            .where((p) => p.trim().isNotEmpty)
                            .expand((p) => _splitIntoSentences(p))
                            .toList()
                        : [];

                    // 全文段落（渲染用）—— 只按 \n\n 切分，绝不做句子级切分
                    // 保持原始 Markdown 格式完整，避免切断 **粗体** / ### 标题 等语法造成乱码
                    final allText = _textController.text;
                    final allParagraphs = allText
                        .split(RegExp(r'\n\n+'))
                        .where((p) => p.trim().isNotEmpty)
                        .toList();

                    _updateParagraphKeys(allParagraphs.length);

                    final position = tts.currentPosition;
                    final duration = tts.currentDuration ?? Duration.zero;
                    final isPlaying = tts.isPlaying;

                    // 归一化函数：折叠所有空白为单空格，便于跨换行格式匹配
                    String normalize(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

                    // 按语音发音特性与标点停顿加权定位当前句子：
                    // 精确估算微软 Neural TTS 句尾停顿(600ms)与句中逗号停顿(300ms)，消除提前 1.5 秒跳下句的偏差
                    int activeIndex = -1;
                    if (isPlaying && duration.inMilliseconds > 0 && karaokeParas.isNotEmpty) {
                      final ratio = (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
                      final totalWeight = karaokeParas.fold<double>(0.0, (sum, p) => sum + _getSpeechWeight(p));

                      int karaokeIdx = karaokeParas.length - 1;
                      if (totalWeight > 0) {
                        final targetWeight = ratio * totalWeight;
                        double cumulative = 0.0;
                        for (int i = 0; i < karaokeParas.length; i++) {
                          cumulative += _getSpeechWeight(karaokeParas[i]);
                          if (targetWeight <= cumulative) {
                            karaokeIdx = i;
                            break;
                          }
                        }
                      }

                      // 更新 iOS 锁屏/系统控制中心 字幕卡片与按键逻辑
                      if (karaokeIdx >= 0 && karaokeIdx < karaokeParas.length) {
                        final activeSentence = karaokeParas[karaokeIdx];
                        final upcomingSentences = karaokeParas.sublist(
                          (karaokeIdx + 1).clamp(0, karaokeParas.length),
                          (karaokeIdx + 3).clamp(0, karaokeParas.length),
                        );
                        final docTitle = widget.file.path.split('/').last;
                        final nextText = upcomingSentences.isNotEmpty ? '▶ 下句: ${upcomingSentences.first}' : 'Jeff Notes Academic';

                        if (_lastLockscreenKaraokeIdx != karaokeIdx) {
                          _lastLockscreenKaraokeIdx = karaokeIdx;

                          // 系统控制中心 Now Playing
                          globalAudioHandler.setPlaybackMetadata(
                            title: '[$activeSentence]',
                            artist: docTitle,
                            duration: duration,
                            position: position,
                            isPlaying: isPlaying,
                          );
                        }

                        globalAudioHandler.onSkipNext = () {
                          if (karaokeIdx < karaokeParas.length - 1) {
                            _seekToSentenceIndex(karaokeIdx + 1, karaokeParas, duration, totalWeight, isChineseMode);
                          }
                        };
                        globalAudioHandler.onSkipPrevious = () {
                          if (karaokeIdx > 0) {
                            _seekToSentenceIndex(karaokeIdx - 1, karaokeParas, duration, totalWeight, isChineseMode);
                          }
                        };
                      }

                      // 用包含关系（contains）在全文段落中找到含有当前句子的段落
                      final activeKaraNorm = normalize(karaokeParas[karaokeIdx]);
                      final foundIdx = allParagraphs.indexWhere(
                        (p) => normalize(p).contains(activeKaraNorm),
                      );
                      activeIndex = foundIdx >= 0 ? foundIdx : -1;
                    }


                    // 自动随朗读平滑滚动屏幕（仅在用户未手动滑动/触摸屏幕时跟随）
                    if (activeIndex >= 0) {
                      final indexChanged = activeIndex != _lastActiveIndex;
                      _lastActiveIndex = activeIndex;
                      if (!_userIsInteracting && (indexChanged || activeIndex >= 0)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _scrollToActiveParagraph();
                        });
                      }
                    }

                    return _showRendered
                        ? NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is ScrollStartNotification && notification.dragDetails != null) {
                                _onUserInteractionStart();
                              } else if (notification is ScrollEndNotification) {
                                _onUserInteractionEnd();
                              }
                              return false;
                            },
                            child: Listener(
                              onPointerDown: (_) => _onUserInteractionStart(),
                              onPointerUp: (_) => _onUserInteractionEnd(),
                              child: ListView.builder(
                                controller: _karaokeScrollController,
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
                                itemCount: allParagraphs.length,
                                itemBuilder: (context, index) {
                              final paragraph = allParagraphs[index];
                              final isActive = index == activeIndex;
                              final itemKey = _paragraphKeys[index];

                              return Container(
                                key: itemKey,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onLongPress: () {
                                    Clipboard.setData(ClipboardData(text: paragraph));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('📋 已复制当前段落文字到剪贴板'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                  onTap: () async {
                                    // 点击任意句子：自动定位该句子并确保开启播放
                                    _lastActiveIndex = index;
                                    _scrollToActiveParagraph();

                                    final List<String> seekParas = (() {
                                      if (tts.currentAudioType == ActiveAudioType.chinese &&
                                          _chineseOnlyText != null &&
                                          _chineseOnlyText!.isNotEmpty) {
                                        return _chineseOnlyText!
                                            .split(RegExp(r'\n\n+'))
                                            .where((p) => p.trim().isNotEmpty)
                                            .expand((p) => _splitIntoSentences(p))
                                            .toList();
                                      } else if ((tts.currentAudioType == ActiveAudioType.english ||
                                                  tts.currentAudioType == ActiveAudioType.recorded) &&
                                          _englishOnlyText != null &&
                                          _englishOnlyText!.isNotEmpty) {
                                        return _englishOnlyText!
                                            .split(RegExp(r'\n\n+'))
                                            .where((p) => p.trim().isNotEmpty)
                                            .expand((p) => _splitIntoSentences(p))
                                            .toList();
                                      }
                                      return <String>[];
                                    })();

                                    final clickedNorm = normalize(paragraph);
                                    int seekIdx = seekParas.indexWhere((p) => normalize(p).contains(clickedNorm) || clickedNorm.contains(normalize(p)));
                                    if (seekIdx < 0) {
                                      final allRatio = allParagraphs.length > 1 ? index / (allParagraphs.length - 1) : 0.0;
                                      seekIdx = (allRatio * (seekParas.length - 1)).round().clamp(0, seekParas.isEmpty ? 0 : seekParas.length - 1);
                                    }

                                    final totalDur = tts.currentDuration;
                                    if (totalDur != null && totalDur.inMilliseconds > 0 && seekParas.isNotEmpty) {
                                      final totalWeight = seekParas.fold<double>(0.0, (sum, p) => sum + _getSpeechWeight(p));
                                      double currentCumulative = 0.0;
                                      for (int i = 0; i < seekIdx; i++) {
                                        currentCumulative += _getSpeechWeight(seekParas[i]);
                                      }
                                      final targetRatio = totalWeight > 0 ? (currentCumulative / totalWeight).clamp(0.0, 1.0) : 0.0;
                                      final targetMs = (targetRatio * totalDur.inMilliseconds).round();
                                      final targetPos = Duration(milliseconds: targetMs);
                                      if (tts.currentAudioType == ActiveAudioType.chinese) {
                                        await tts.seekChinese(targetPos);
                                        if (!tts.isPlaying) await tts.playChinese();
                                      } else {
                                        await tts.seekEnglish(targetPos);
                                        if (!tts.isPlaying) await tts.playEnglish();
                                      }
                                    } else {
                                      // 若当前未开启播放，点击任意句子自动开启朗读并秒跳到该位置
                                      final isChineseMode = tts.currentAudioType == ActiveAudioType.chinese;
                                      try {
                                        final provider = context.read<RecordingProvider>();
                                        if (isChineseMode && _chineseOnlyText != null && _chineseOnlyText!.isNotEmpty) {
                                          await tts.speakChinese(
                                            _chineseOnlyText!,
                                            geminiKey: provider.geminiKey,
                                            siliconFlowKey: provider.siliconFlowKey,
                                          );
                                        } else if (_englishOnlyText != null && _englishOnlyText!.isNotEmpty) {
                                          await tts.speakEnglish(
                                            _englishOnlyText!,
                                            geminiKey: provider.geminiKey,
                                            siliconFlowKey: provider.siliconFlowKey,
                                          );
                                        }
                                        await Future.delayed(const Duration(milliseconds: 500));
                                        final newDur = tts.currentDuration;
                                        if (newDur != null && newDur.inMilliseconds > 0) {
                                          final totalWeight = seekParas.fold<double>(0.0, (sum, p) => sum + _getSpeechWeight(p));
                                          double currentCumulative = 0.0;
                                          for (int i = 0; i < seekIdx; i++) {
                                            currentCumulative += _getSpeechWeight(seekParas[i]);
                                          }
                                          final targetRatio = totalWeight > 0 ? (currentCumulative / totalWeight).clamp(0.0, 1.0) : 0.0;
                                          final targetMs = (targetRatio * newDur.inMilliseconds).round();
                                          final targetPos = Duration(milliseconds: targetMs);
                                          if (isChineseMode) {
                                            await tts.seekChinese(targetPos);
                                          } else {
                                            await tts.seekEnglish(targetPos);
                                          }
                                        }
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        if (e.toString().contains('NoHeadphones')) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('⚠️ 未检测到耳机 (${e.toString().replaceAll("Exception: ", "")})', style: const TextStyle(fontSize: 13)),
                                              backgroundColor: Colors.orange,
                                              duration: const Duration(seconds: 5),
                                            ),
                                          );
                                        }
                                      }
                                    }
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    margin: const EdgeInsets.symmetric(vertical: 6),
                                    padding: EdgeInsets.all(isActive ? 14 : 6),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? (isDark
                                              ? const Color(0xFF2A2A40)
                                              : const Color(0xFFEBF3FE))
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isActive
                                            ? Colors.blueAccent
                                            : Colors.transparent,
                                        width: isActive ? 1.5 : 0,
                                      ),
                                      boxShadow: isActive
                                        ? [
                                            BoxShadow(
                                              color: Colors.blueAccent.withOpacity(0.15),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : [],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (isActive)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 6),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.record_voice_over_rounded, size: 14, color: Colors.blueAccent),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '🎤 卡拉OK 实时歌词字幕同步',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isDark ? Colors.cyanAccent : Colors.blueAccent,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        MarkdownBody(
                                          data: paragraph,
                                          selectable: false,
                                          softLineBreak: true,
                                          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                            p: TextStyle(
                                              fontFamily: 'Menlo',
                                              fontSize: isActive ? 16 : 15,
                                              height: 1.6,
                                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                              color: isActive
                                                  ? (isDark ? Colors.white : Colors.black87)
                                                  : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                            h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.8),
                                            h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.8),
                                            h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.8),
                                          ),
                                          extensionSet: md.ExtensionSet(
                                            [const md.FencedCodeBlockSyntax()],
                                            [md.EmojiSyntax(), HighlightSyntax()],
                                          ),
                                          builders: {'highlight': HighlightBuilder(context)},
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
                            child: TextField(
                              controller: _textController,
                              readOnly: true,
                              maxLines: null,
                              style: const TextStyle(fontFamily: 'Menlo', fontSize: 15, height: 1.6),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          );
                   },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
