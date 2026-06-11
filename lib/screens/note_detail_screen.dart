import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../utils/pdf_service.dart';
import '../services/reading_quiz_service.dart';
import '../widgets/academic_markdown.dart';

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

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
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
            _contentLoaded = true;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
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
          );
        },
      ),
    );
  }
}
