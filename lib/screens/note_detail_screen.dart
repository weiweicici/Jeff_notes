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
import '../widgets/tap_page_turn_region.dart';
import '../services/supabase_config.dart';
import '../services/tts_service.dart';
import '../services/vocab_service.dart';
import '../services/vocab_extractor_service.dart';
import 'smart_vocab_screen.dart';

enum _NoteMenuAction { toggleRendered, extractVocab, exportPdf, delete }

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
  final _scrollController = ScrollController();
  String? _lastLoadedContent;
  String? _chineseOnlyText;
  String? _englishOnlyText;
  bool _showRendered = true;

  Timer? _autoScrollTimer;
  bool _isAutoScrolling = false;
  int _secondsPerPage = 30;
  bool _autoScrollTimerStarted = false;
  bool _readerPreferencesLoaded = false;
  bool _readingPositionRestored = false;
  bool _playerExpanded = false;
  Timer? _playerAutoHideTimer;
  late RecordingProvider _recordingProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recordingProvider = context.read<RecordingProvider>();
    if (!_readerPreferencesLoaded) {
      _readerPreferencesLoaded = true;
      _isAutoScrolling = _recordingProvider.autoScrollEnabled;
      _secondsPerPage = _recordingProvider.autoScrollSecondsPerPage;
    }
  }

  File _recordedAudioFile() {
    final direct = File(widget.file.path.replaceAll('.md', '.wav'));
    if (direct.existsSync()) return direct;

    final name = widget.file.uri.pathSegments.last;
    if (name.startsWith('Jeff_速记_')) {
      final suffix = name.substring('Jeff_速记_'.length);
      return File(
        '${widget.file.parent.path}/Jeff_Exam_${suffix.replaceAll(RegExp(r'\.md$'), '.wav')}',
      );
    }
    return direct;
  }

  File? _companionMarkdownFile() {
    final name = widget.file.uri.pathSegments.last;
    if (name.startsWith('Jeff_速记_')) {
      final suffix = name.substring('Jeff_速记_'.length);
      return File('${widget.file.parent.path}/Jeff_Exam_$suffix');
    }
    if (name.startsWith('Jeff_Exam_')) {
      final suffix = name.substring('Jeff_Exam_'.length);
      return File('${widget.file.parent.path}/Jeff_速记_$suffix');
    }
    return null;
  }

  void _stopAutoScrollTimer() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _toggleAutoScroll() {
    setState(() {
      _isAutoScrolling = !_isAutoScrolling;
      if (_isAutoScrolling) {
        _startAutoScrollTimer();
      } else {
        _stopAutoScrollTimer();
      }
    });
    unawaited(
      _recordingProvider.updateReadingPreferences(
        autoScrollEnabled: _isAutoScrolling,
      ),
    );
  }

  void _setSecondsPerPage(int value) {
    setState(() => _secondsPerPage = value.clamp(10, 120));
    if (_isAutoScrolling) _startAutoScrollTimer();
    unawaited(
      _recordingProvider.updateReadingPreferences(
        secondsPerPage: _secondsPerPage,
      ),
    );
  }

  void _saveCurrentReadingOffset() {
    if (!_scrollController.hasClients) return;
    unawaited(
      _recordingProvider.saveReadingOffset(
        widget.file.path,
        _scrollController.position.pixels,
      ),
    );
  }

  void _startAutoScrollTimer() {
    if (!_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _startAutoScrollTimer();
      });
      return;
    }
    if (!_isAutoScrolling) return;
    _stopAutoScrollTimer();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (
      timer,
    ) {
      if (!_scrollController.hasClients) {
        timer.cancel();
        return;
      }
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;
      final ticksPerScreen = _secondsPerPage * 1000 ~/ 50;
      final increment =
          _scrollController.position.viewportDimension / ticksPerScreen;
      final currentScroll = _scrollController.position.pixels;
      if (currentScroll >= maxScroll) {
        timer.cancel();
        _autoScrollTimer = null;
        if (mounted) setState(() => _isAutoScrolling = false);
        return;
      }
      _scrollController.jumpTo(
        (currentScroll + increment).clamp(0.0, maxScroll),
      );
    });
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      unawaited(
        _recordingProvider.saveReadingOffset(
          widget.file.path,
          _scrollController.position.pixels,
        ),
      );
    }
    _stopAutoScrollTimer();
    _playerAutoHideTimer?.cancel();
    if (!TtsService().playbackBlockedForRecording) {
      unawaited(TtsService().stop());
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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

      // Compact shorthand documents use bracket labels instead of Markdown
      // headings so the page stays dense. Stop before the English transcript.
      if (inChineseSection &&
          (trimmed.contains('英文全文') ||
              trimmed.contains('English Transcript'))) {
        break;
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
      if (trimmed.startsWith('---') ||
          trimmed.startsWith('===') ||
          trimmed.startsWith('━━━')) {
        continue;
      }

      if (inChineseSection && trimmed.isNotEmpty) {
        capturedLines.add(trimmed);
      }
    }

    if (capturedLines.isNotEmpty) return capturedLines.join('\n\n');

    // 策略 2：FreeTalk 模式（文件名区分大小写不敏感）
    final fileName = widget.file.path.split('/').last.toLowerCase();
    if (fileName.contains('freetalk')) {
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
          trimmed.startsWith('---'))
        return false;
      final cjkCount = RegExp(
        r'[\u4e00-\u9fff\u3400-\u4dbf]',
      ).allMatches(trimmed).length;
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
          trimmed.contains('English Essay')) {
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
            trimmed.contains('English Essay');
        if (!isContinuationHeader) break;
        continue;
      }

      // 过滤分隔线
      if (trimmed.startsWith('---') ||
          trimmed.startsWith('===') ||
          trimmed.startsWith('━━━')) {
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
          trimmed.startsWith('---'))
        return false;
      final cjkCount = RegExp(
        r'[\u4e00-\u9fff\u3400-\u4dbf]',
      ).allMatches(trimmed).length;
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

  Future<void> _extractSmartVocab(BuildContext context) async {
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
              child: Text(
                '正在使用 AI 提炼文本中的高频学术词汇与长难句剖析...',
                style: TextStyle(fontSize: 13),
              ),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('⚠️ 未能提取到有效的生词卡片，请重试')));
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
            builder: (_) =>
                SmartVocabScreen(initialCards: cards, sourceTitle: title),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 提炼失败: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _copyFullText() async {
    try {
      final content = await widget.file.readAsString();
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('✅ 已复制到剪贴板')));
      }
    } catch (e) {
      debugPrint('Copy Error: $e');
    }
  }

  Future<void> _deleteNote() async {
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
            child: const Text(
              '删除',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final title = widget.file.path.split('/').last;
      final sharedWav = _recordedAudioFile();
      final companion = _companionMarkdownFile();
      if (await widget.file.exists()) await widget.file.delete();
      if ((companion == null || !await companion.exists()) &&
          await sharedWav.exists()) {
        await sharedWav.delete();
      }
      await SupabaseConfig.client
          .from('archives')
          .delete()
          .eq('title', title)
          .eq('user_id', SupabaseConfig.currentUserId);
      await _recordingProvider.forgetReadyNote(widget.file.path);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('✅ 笔记已完全删除')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Delete Note Error: $e');
    }
  }

  Future<void> _handleMenuAction(_NoteMenuAction action) async {
    switch (action) {
      case _NoteMenuAction.toggleRendered:
        setState(() => _showRendered = !_showRendered);
        return;
      case _NoteMenuAction.extractVocab:
        await _extractSmartVocab(context);
        return;
      case _NoteMenuAction.exportPdf:
        if (!_isExporting) await _exportPdf();
        return;
      case _NoteMenuAction.delete:
        await _deleteNote();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.file.path.split('/').last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制全文',
            onPressed: _copyFullText,
          ),
          PopupMenuButton<_NoteMenuAction>(
            key: _pdfButtonKey,
            tooltip: '更多操作',
            onSelected: (action) => unawaited(_handleMenuAction(action)),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _NoteMenuAction.toggleRendered,
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    _showRendered ? Icons.code : Icons.auto_awesome,
                  ),
                  title: Text(_showRendered ? '查看MD源码' : '渲染Markdown'),
                ),
              ),
              const PopupMenuItem(
                value: _NoteMenuAction.extractVocab,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.style_outlined),
                  title: Text('AI提炼词汇'),
                ),
              ),
              PopupMenuItem(
                value: _NoteMenuAction.exportPdf,
                enabled: !_isExporting,
                child: ListTile(
                  dense: true,
                  leading: _isExporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  title: const Text('导出PDF'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _NoteMenuAction.delete,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text(
                    '删除文档',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: widget.file.readAsString(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text("Error loading file: ${snapshot.error}"));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final currentContent = snapshot.data!;
          if (_lastLoadedContent != currentContent) {
            _textController.text = currentContent;
            _chineseOnlyText = _extractChineseOnly(currentContent);
            _englishOnlyText = _extractEnglishOnly(currentContent);
            _lastLoadedContent = currentContent;
          }
          final allParagraphs = currentContent
              .split(RegExp(r'\n{2,}'))
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList();

          if (!_autoScrollTimerStarted) {
            _autoScrollTimerStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scrollController.hasClients) return;
              if (!_readingPositionRestored) {
                _readingPositionRestored = true;
                final saved = _recordingProvider.readingOffsetFor(
                  widget.file.path,
                );
                _scrollController.jumpTo(
                  saved.clamp(0.0, _scrollController.position.maxScrollExtent),
                );
              }
              if (_isAutoScrolling) _startAutoScrollTimer();
            });
          }

          final wavFile = _recordedAudioFile();
          final hasWav = wavFile.existsSync();

          return Column(
            children: [
              if (context.watch<RecordingProvider>().isRecording)
                Material(
                  color: Colors.redAccent.withOpacity(0.12),
                  child: InkWell(
                    onTap: () => Navigator.of(context).popUntil(
                      (route) =>
                          route.settings.name == '/notes-recording' ||
                          route.isFirst,
                    ),
                    child: const SizedBox(
                      width: double.infinity,
                      height: 34,
                      child: Center(
                        child: Text(
                          '🔴 录音进行中 · 点击返回实时字幕',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _playerExpanded = !_playerExpanded;
                    if (_playerExpanded) {
                      _playerAutoHideTimer?.cancel();
                      _playerAutoHideTimer = Timer(
                        const Duration(seconds: 10),
                        () {
                          if (mounted) setState(() => _playerExpanded = false);
                        },
                      );
                    } else {
                      _playerAutoHideTimer?.cancel();
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _playerExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.headphones,
                        size: 14,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _playerExpanded ? '点击收起播放器' : '🎧 TTS 播放器',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_playerExpanded) ...[
                const SizedBox(height: 8),
                TtsPlayerBar(
                  chineseText: _chineseOnlyText ?? '',
                  englishText: _englishOnlyText ?? '',
                  recordedAudioPath: hasWav ? wavFile.path : null,
                  siliconFlowKey: context
                      .read<RecordingProvider>()
                      .siliconFlowKey,
                ),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(left: 8, right: 4),
                color: _isAutoScrolling
                    ? Colors.blue.withOpacity(0.08)
                    : Colors.grey.withOpacity(0.07),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: _isAutoScrolling ? '停止自动滚屏' : '开始自动滚屏',
                      onPressed: _toggleAutoScroll,
                      icon: Icon(
                        _isAutoScrolling
                            ? Icons.pause_circle_outline
                            : Icons.touch_app_outlined,
                        size: 19,
                        color: _isAutoScrolling
                            ? Colors.blueAccent
                            : Colors.grey[600],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _isAutoScrolling
                            ? '自动滚屏 · $_secondsPerPage秒/页'
                            : '手动翻页 · 点击正文下一页',
                        style: TextStyle(
                          fontSize: 11,
                          color: _isAutoScrolling
                              ? Colors.blueAccent
                              : Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PopupMenuButton<int>(
                      tooltip: '设置自动滚屏速度',
                      initialValue: _secondsPerPage,
                      onSelected: _setSecondsPerPage,
                      icon: const Icon(Icons.speed_rounded, size: 19),
                      itemBuilder: (_) => const [10, 20, 30, 45, 60, 90]
                          .map(
                            (seconds) => PopupMenuItem<int>(
                              value: seconds,
                              child: Text('$seconds 秒/页'),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _showRendered
                    ? TapPageTurnRegion(
                        controller: _scrollController,
                        onPageChanged: _saveCurrentReadingOffset,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
                          itemCount: allParagraphs.length,
                          itemBuilder: (context, index) {
                            final paragraph = allParagraphs[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onLongPress: () {
                                  Clipboard.setData(
                                    ClipboardData(text: paragraph),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('📋 已复制当前段落文字到剪贴板'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                child: MarkdownBody(
                                  data: paragraph,
                                  selectable: false,
                                  softLineBreak: true,
                                  styleSheet: getAcademicMarkdownStyle(context),
                                  extensionSet: md.ExtensionSet(
                                    [const md.FencedCodeBlockSyntax()],
                                    [md.EmojiSyntax(), HighlightSyntax()],
                                  ),
                                  builders: {
                                    'highlight': HighlightBuilder(context),
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : TapPageTurnRegion(
                        controller: _scrollController,
                        onPageChanged: _saveCurrentReadingOffset,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
                          child: TextField(
                            controller: _textController,
                            readOnly: true,
                            maxLines: null,
                            style: const TextStyle(
                              fontFamily: 'Menlo',
                              fontSize: 15,
                              height: 1.6,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
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
