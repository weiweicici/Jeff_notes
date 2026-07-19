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
import '../services/tts_service.dart';

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
  bool _contentLoaded = false;
  String? _chineseOnlyText;
  String? _englishOnlyText;
  bool _showRendered = true; // true = MarkdownBody（可见高亮），false = TextField（原始文字）

  @override
  void dispose() {
    TtsService().stop();
    _textController.dispose();
    super.dispose();
  }

  /// 提取 MD 文件中的纯中文部分，供 TTS 播放。
  /// 策略 1：逐行解析——找到 '### 中文全文' 后开始收集，遇到下一个 ### 或 ## 标题时停止。
  ///         这比正则可靠得多，不受换行数量影响。
  /// 策略 2：FreeTalk 模式 — 第一个 \n\n 之前的内容（中文块在前）
  /// 策略 3：兜底 — 提取含 >=3 个汉字的行
  String _extractChineseOnly(String fullText) {
    // 策略 1：逐行解析（讲座/讨论模式）
    final lines = fullText.split('\n');
    bool inChineseSection = false;
    final capturedLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();

      // 找到中文全文标题 → 开始收集
      if (trimmed.startsWith('### 中文全文')) {
        inChineseSection = true;
        continue;
      }

      // 遇到任意下一个标题 → 停止收集（精确截断，不受换行数量影响）
      if (inChineseSection &&
          (trimmed.startsWith('### ') ||
           trimmed.startsWith('## ') ||
           trimmed.startsWith('# '))) {
        break;
      }

      if (inChineseSection && trimmed.isNotEmpty) {
        capturedLines.add(trimmed);
      }
    }

    if (capturedLines.isNotEmpty) return capturedLines.join(' ');

    // 策略 2：FreeTalk 模式 — 中文块在前，\n\n 后是英文块
    final fileName = widget.file.path.split('/').last;
    if (fileName.contains('FreeTalk')) {
      final firstBlank = fullText.indexOf('\n\n');
      if (firstBlank > 0) {
        return fullText.substring(0, firstBlank).trim();
      }
    }

    // 策略 3：兜底 — 按行提取含足够汉字的内容
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

    if (chineseLines.isNotEmpty) return chineseLines.join(' ');
    return fullText; // 最终兜底
  }

  /// 提取 MD 文件中的纯英文部分，供 AI TTS 播放。
  String _extractEnglishOnly(String fullText) {
    final lines = fullText.split('\n');
    bool inEnglishSection = false;
    final capturedLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.contains('英文全文') || trimmed.contains('English Transcript')) {
        inEnglishSection = true;
        continue;
      }

      if (inEnglishSection &&
          (trimmed.startsWith('### ') ||
           trimmed.startsWith('## ') ||
           trimmed.startsWith('# '))) {
        break;
      }

      if (inEnglishSection && trimmed.isNotEmpty) {
        capturedLines.add(trimmed);
      }
    }

    if (capturedLines.isNotEmpty) return capturedLines.join(' ');

    // 策略 2：FreeTalk 模式 — \n\n 之后的内容
    final fileName = widget.file.path.split('/').last;
    if (fileName.contains('FreeTalk')) {
      final firstBlank = fullText.indexOf('\n\n');
      if (firstBlank > 0 && firstBlank + 2 < fullText.length) {
        return fullText.substring(firstBlank + 2).trim();
      }
    }

    // 策略 3：兜底 — 严格过滤掉所有含汉字的行，绝不退回包含中文的全文本
    final purelyEnglish = lines.where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('**') ||
          trimmed.startsWith('---')) return false;
      final cjkCount =
          RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]').allMatches(trimmed).length;
      return cjkCount == 0 && trimmed.contains(RegExp(r'[a-zA-Z]'));
    }).join(' ');

    return purelyEnglish;
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
        ],
      ),
      body: FutureBuilder<String>(
        future: widget.file.readAsString(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error loading file: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          if (!_contentLoaded) {
            _textController.text = snapshot.data!;
            _chineseOnlyText = _extractChineseOnly(snapshot.data!);
            _englishOnlyText = _extractEnglishOnly(snapshot.data!);
            _contentLoaded = true;
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
                  child: _showRendered
                      // ── 渲染模式：==keyword== 显示为黄色高亮 ──
                      ? MarkdownBody(
                          data: _textController.text,
                          selectable: true,
                          softLineBreak: true,
                          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                            p: const TextStyle(fontFamily: 'Menlo', fontSize: 15, height: 1.6),
                            h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.8),
                            h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.8),
                            h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.8),
                          ),
                          extensionSet: md.ExtensionSet(
                            [const md.FencedCodeBlockSyntax()],
                            [md.EmojiSyntax(), HighlightSyntax()],
                          ),
                          builders: {'highlight': HighlightBuilder(context)},
                        )
                      // ── 原始模式：显示原始 Markdown 文字 ──
                      : TextField(
                          controller: _textController,
                          readOnly: true,
                          maxLines: null,
                          style: const TextStyle(fontFamily: 'Menlo', fontSize: 15, height: 1.6),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          contextMenuBuilder: (context, editableTextState) {
                            final text = editableTextState.textEditingValue.text;
                            final sel = editableTextState.textEditingValue.selection;
                            final selectedText = sel.isValid && sel.start != sel.end
                                ? text.substring(sel.start, sel.end)
                                : '';
                            return AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: editableTextState.contextMenuAnchors,
                              buttonItems: [
                                if (selectedText.isNotEmpty) ...[
                                  ContextMenuButtonItem(
                                    label: '翻译',
                                    onPressed: () {
                                      editableTextState.hideToolbar();
                                      _handleTranslateSelection(selectedText);
                                    },
                                  ),
                                  ContextMenuButtonItem(
                                    label: '转述',
                                    onPressed: () {
                                      editableTextState.hideToolbar();
                                      _handleParaphraseSelection(selectedText);
                                    },
                                  ),
                                ],
                                ...editableTextState.contextMenuButtonItems,
                              ],
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
