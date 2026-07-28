import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/academic_markdown.dart';
import '../services/reading_quiz_service.dart';
import '../services/supabase_config.dart';

class ReadingDetailScreen extends StatefulWidget {
  final String id;
  final String title;
  final String contentMd;

  const ReadingDetailScreen({
    super.key,
    required this.id,
    required this.title,
    required this.contentMd,
  });

  @override
  State<ReadingDetailScreen> createState() => _ReadingDetailScreenState();
}

class _ReadingDetailScreenState extends State<ReadingDetailScreen> {
  String? _quizResult;
  String? _summaryResult;
  String? _vocabResult;
  String? _translationResult;
  String? _paraphraseResult;

  bool _loadingQuiz = false;
  bool _loadingSummary = false;
  bool _loadingVocab = false;
  bool _loadingTranslation = false;
  bool _loadingParaphrase = false;
  bool _showRendered = false;
  final _textController = TextEditingController();
  String _selectedPlainText = '';

  late String _title;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _textController.text = widget.contentMd;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// 提取课文正文（去掉练习部分），确保 AI 只处理课文
  String get _readingText {
    final idx = widget.contentMd.indexOf('\n## 📝 练习');
    if (idx == -1) {
      // 也可能以 --- 或 ## 分隔
      final fallback = widget.contentMd.indexOf('\n---\n');
      return fallback == -1 ? widget.contentMd : widget.contentMd.substring(0, fallback);
    }
    return widget.contentMd.substring(0, idx);
  }

  Future<void> _generateQuiz() async {
    setState(() {
      _loadingQuiz = true;
      _quizResult = null;
    });
    final result = await ReadingQuizService.generateQuiz(_readingText);
    if (mounted) setState(() {
      _quizResult = result;
      _loadingQuiz = false;
    });
  }

  Future<void> _getSummary() async {
    setState(() {
      _loadingSummary = true;
      _summaryResult = null;
    });
    final result = await ReadingQuizService.getSummary(_readingText);
    if (mounted) setState(() {
      _summaryResult = result;
      _loadingSummary = false;
    });
  }

  Future<void> _getVocabulary() async {
    setState(() {
      _loadingVocab = true;
      _vocabResult = null;
    });
    final result = await ReadingQuizService.getVocabulary(_readingText);
    if (mounted) setState(() {
      _vocabResult = result;
      _loadingVocab = false;
    });
  }

  void _openTranslateSheet() {
    _openTextSheet(
      title: '翻译',
      hint: '编辑要翻译的文本（默认课文正文）',
      initialText: _readingText,
      onConfirm: (text) async {
        setState(() {
          _loadingTranslation = true;
          _translationResult = null;
        });
        final result = await ReadingQuizService.getTranslation(text);
        if (mounted) setState(() {
          _translationResult = result;
          _loadingTranslation = false;
        });
      },
    );
  }

  void _openParaphraseSheet() {
    _openTextSheet(
      title: '转述',
      hint: '编辑要转述的文本（默认课文正文）',
      initialText: _readingText,
      onConfirm: (text) async {
        setState(() {
          _loadingParaphrase = true;
          _paraphraseResult = null;
        });
        final result = await ReadingQuizService.getParaphrase(text);
        if (mounted) setState(() {
          _paraphraseResult = result;
          _loadingParaphrase = false;
        });
      },
    );
  }

  void _handleTranslateSelection(String text) async {
    debugPrint('[ReadingDetail] _handleTranslateSelection called, text length=${text.length}, preview="${text.length > 50 ? text.substring(0, 50) : text}"');
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
    debugPrint('[ReadingDetail] _handleParaphraseSelection called, text length=${text.length}, preview="${text.length > 50 ? text.substring(0, 50) : text}"');
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

  void _openTextSheet({
    required String title,
    required String hint,
    required String initialText,
    required Future<void> Function(String text) onConfirm,
  }) {
    final controller = TextEditingController(text: initialText);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16, right: 16, top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(hint, style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                onConfirm(controller.text);
              },
              child: const Text('确认'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _exportMarkdown() async {
    final buffer = StringBuffer();
    buffer.writeln('# $_title');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('## 原文');
    buffer.writeln();
    buffer.writeln(widget.contentMd);

    void appendSection(String title, String? content) {
      if (content != null && content.isNotEmpty && !content.startsWith('[')) {
        buffer.writeln();
        buffer.writeln('---');
        buffer.writeln();
        buffer.writeln('## $title');
        buffer.writeln();
        buffer.writeln(content);
      }
    }

    appendSection('阅读理解题', _quizResult);
    appendSection('全文摘要', _summaryResult);
    appendSection('核心词汇', _vocabResult);
    appendSection('中文翻译', _translationResult);
    appendSection('转述', _paraphraseResult);

    final now = DateTime.now();
    final filename = 'Jeff_Reading_${DateFormat('yyyyMMdd_HHmm').format(now)}.md';
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(buffer.toString());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出: $filename')),
      );
    }
  }

  Future<void> _delete() async {
    await SupabaseConfig.client.from('archives').delete().eq('id', widget.id).eq('user_id', SupabaseConfig.currentUserId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () async {
            final controller = TextEditingController(text: _title);
            final newTitle = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('修改标题'),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: const Text('确定'),
                  ),
                ],
              ),
            );
            if (newTitle != null && newTitle.isNotEmpty) {
              await SupabaseConfig.client.from('archives').update({'title': newTitle}).eq('id', widget.id).eq('user_id', SupabaseConfig.currentUserId);
              if (mounted) setState(() => _title = newTitle);
            }
          },
          child: Text(_title, style: const TextStyle(fontSize: 18)),
        ),
        actions: [
          IconButton(
            icon: Icon(_showRendered ? Icons.code : Icons.article),
            onPressed: () => setState(() => _showRendered = !_showRendered),
            tooltip: _showRendered ? '查看原文' : 'Markdown 渲染',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportMarkdown,
            tooltip: '导出',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 原文
            if (_showRendered)
              SelectionArea(
                onSelectionChanged: (content) {
                  _selectedPlainText = content?.plainText ?? '';
                },
                contextMenuBuilder: (context, selectableRegionState) {
                  // ✅ 关键：在此处立即捕获选中文本。
                  // contextMenuBuilder 在选中状态仍然有效时被调用；
                  // 而 onPressed 触发时 iOS 已清空选中（onSelectionChanged 会把
                  // _selectedPlainText 置空），所以必须在这里用 final 固定住文本。
                  final capturedText = _selectedPlainText;

                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: selectableRegionState.contextMenuAnchors,
                    buttonItems: [
                      if (capturedText.isNotEmpty) ...[
                        ContextMenuButtonItem(
                          label: '翻译',
                          onPressed: () {
                            selectableRegionState.clearSelection();
                            _handleTranslateSelection(capturedText);
                          },
                        ),
                        ContextMenuButtonItem(
                          label: '转述',
                          onPressed: () {
                            selectableRegionState.clearSelection();
                            _handleParaphraseSelection(capturedText);
                          },
                        ),
                      ],
                      ...selectableRegionState.contextMenuButtonItems,
                    ],
                  );
                },
                child: MarkdownBody(
                  data: widget.contentMd,
                  softLineBreak: true,
                  selectable: false,
                  styleSheet: getAcademicMarkdownStyle(context),
                  extensionSet: md.ExtensionSet(
                    [const md.FencedCodeBlockSyntax()],
                    [md.EmojiSyntax(), HighlightSyntax()],
                  ),
                  builders: {
                    'highlight': HighlightBuilder(context),
                  },
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      controller: _textController,
                      readOnly: true,
                      maxLines: null,
                      style: const TextStyle(fontFamily: 'Menlo', fontSize: 13, height: 1.5),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                contextMenuBuilder: (context, editableTextState) {
                  final text = editableTextState.textEditingValue.text;
                  final sel = editableTextState.textEditingValue.selection;
                  final selectedText = sel.isValid && sel.start != sel.end
                      ? text.substring(sel.start, sel.end)
                      : '';
                  debugPrint('[ReadingDetail] TextField contextMenuBuilder, selectedText length=${selectedText.length}');
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
                ],
              ),
            const SizedBox(height: 24),
            // 第一行按钮
            Row(
              children: [
                Expanded(child: _actionBtn(
                  icon: Icons.quiz,
                  label: 'AI 出题',
                  loading: _loadingQuiz,
                  onPressed: _generateQuiz,
                )),
                const SizedBox(width: 8),
                Expanded(child: _actionBtn(
                  icon: Icons.summarize,
                  label: '摘要',
                  loading: _loadingSummary,
                  onPressed: _getSummary,
                )),
                const SizedBox(width: 8),
                Expanded(child: _actionBtn(
                  icon: Icons.book,
                  label: '生词',
                  loading: _loadingVocab,
                  onPressed: _getVocabulary,
                )),
              ],
            ),
            const SizedBox(height: 8),
            // 第二行按钮
            Row(
              children: [
                Expanded(child: _actionBtn(
                  icon: Icons.translate,
                  label: '翻译',
                  loading: _loadingTranslation,
                  onPressed: _openTranslateSheet,
                )),
                const SizedBox(width: 8),
                Expanded(child: _actionBtn(
                  icon: Icons.replay,
                  label: '转述',
                  loading: _loadingParaphrase,
                  onPressed: _openParaphraseSheet,
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _exportMarkdown,
                  icon: const Icon(Icons.file_download, size: 18),
                  label: const Text('导出', style: TextStyle(fontSize: 13)),
                )),
              ],
            ),
            const SizedBox(height: 24),
            // 结果区域
            if (_translationResult != null) ...[
              const Divider(),
              _sectionHeader('中文翻译', Icons.translate, () => setState(() => _translationResult = null)),
              const SizedBox(height: 8),
              MarkdownBody(
                data: _translationResult!,
                softLineBreak: true,
                selectable: true,
                styleSheet: getAcademicMarkdownStyle(context),
                extensionSet: md.ExtensionSet(
                  [const md.FencedCodeBlockSyntax()],
                  [md.EmojiSyntax(), HighlightSyntax()],
                ),
                builders: {
                  'highlight': HighlightBuilder(context),
                },
              ),
              const SizedBox(height: 16),
            ],
            if (_paraphraseResult != null) ...[
              const Divider(),
              _sectionHeader('转述', Icons.replay, () => setState(() => _paraphraseResult = null)),
              const SizedBox(height: 8),
              MarkdownBody(
                data: _paraphraseResult!,
                softLineBreak: true,
                selectable: true,
                styleSheet: getAcademicMarkdownStyle(context),
                extensionSet: md.ExtensionSet(
                  [const md.FencedCodeBlockSyntax()],
                  [md.EmojiSyntax(), HighlightSyntax()],
                ),
                builders: {
                  'highlight': HighlightBuilder(context),
                },
              ),
              const SizedBox(height: 16),
            ],
            if (_quizResult != null) ...[
              const Divider(),
              _sectionHeader('阅读理解题', Icons.quiz, () => setState(() => _quizResult = null)),
              const SizedBox(height: 8),
              MarkdownBody(
                data: _quizResult!,
                softLineBreak: true,
                selectable: true,
                styleSheet: getAcademicMarkdownStyle(context),
                extensionSet: md.ExtensionSet(
                  [const md.FencedCodeBlockSyntax()],
                  [md.EmojiSyntax(), HighlightSyntax()],
                ),
                builders: {
                  'highlight': HighlightBuilder(context),
                },
              ),
              const SizedBox(height: 16),
            ],
            if (_summaryResult != null) ...[
              const Divider(),
              _sectionHeader('全文摘要', Icons.summarize, () => setState(() => _summaryResult = null)),
              const SizedBox(height: 8),
              MarkdownBody(
                data: _summaryResult!,
                softLineBreak: true,
                selectable: true,
                styleSheet: getAcademicMarkdownStyle(context),
                extensionSet: md.ExtensionSet(
                  [const md.FencedCodeBlockSyntax()],
                  [md.EmojiSyntax(), HighlightSyntax()],
                ),
                builders: {
                  'highlight': HighlightBuilder(context),
                },
              ),
              const SizedBox(height: 16),
            ],
            if (_vocabResult != null) ...[
              const Divider(),
              _sectionHeader('核心词汇', Icons.book, () => setState(() => _vocabResult = null)),
              const SizedBox(height: 8),
              MarkdownBody(
                data: _vocabResult!,
                softLineBreak: true,
                selectable: true,
                styleSheet: getAcademicMarkdownStyle(context),
                extensionSet: md.ExtensionSet(
                  [const md.FencedCodeBlockSyntax()],
                  [md.EmojiSyntax(), HighlightSyntax()],
                ),
                builders: {
                  'highlight': HighlightBuilder(context),
                },
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return FilledButton.tonalIcon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(loading ? '...' : label, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _sectionHeader(String title, IconData icon, VoidCallback onDismiss) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: onDismiss,
          tooltip: '关闭',
        ),
      ],
    );
  }
}
