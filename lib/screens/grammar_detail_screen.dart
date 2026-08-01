import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../models.dart';
import '../services/grammar_service.dart';
import '../widgets/academic_markdown.dart';
import '../widgets/tap_page_turn_region.dart';
import 'grammar_writing_screen.dart';

class GrammarDetailScreen extends StatefulWidget {
  final GrammarUnit unit;
  const GrammarDetailScreen({super.key, required this.unit});

  @override
  State<GrammarDetailScreen> createState() => _GrammarDetailScreenState();
}

class _GrammarDetailScreenState extends State<GrammarDetailScreen> {
  bool _isLoading = false;
  String _result = '';
  String _resultTitle = '';
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _generateExercise() async {
    setState(() {
      _isLoading = true;
      _result = '';
      _resultTitle = '📝 练习题';
    });
    final result = await GrammarService.generateExercise(widget.unit);
    if (mounted)
      setState(() {
        _result = result;
        _isLoading = false;
      });
    if (mounted && !context.mounted) return;
    if (mounted) _showResult();
  }

  void _showAskQuestion() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('💬 提问'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '输入你的语法问题...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final q = controller.text.trim();
              if (q.isEmpty) return;
              Navigator.pop(ctx);
              setState(() {
                _isLoading = true;
                _result = '';
                _resultTitle = '💬 回答';
              });
              final result = await GrammarService.askQuestion(widget.unit, q);
              if (mounted)
                setState(() {
                  _result = result;
                  _isLoading = false;
                });
              if (mounted) _showResult();
            },
            child: const Text('提问'),
          ),
        ],
      ),
    );
  }

  void _showCorrectSentence() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('✏️ 句子批改'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '粘贴你要检查的英文句子...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final s = controller.text.trim();
              if (s.isEmpty) return;
              Navigator.pop(ctx);
              setState(() {
                _isLoading = true;
                _result = '';
                _resultTitle = '✏️ 批改结果';
              });
              final result = await GrammarService.correctSentence(s);
              if (mounted)
                setState(() {
                  _result = result;
                  _isLoading = false;
                });
              if (mounted) _showResult();
            },
            child: const Text('检查'),
          ),
        ],
      ),
    );
  }

  void _showResult() {
    if (!mounted || _result.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(_resultTitle, style: const TextStyle(fontSize: 18)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: MarkdownBody(
            data: _result,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unit = widget.unit;

    return Scaffold(
      appBar: AppBar(
        title: Text(unit.title, style: const TextStyle(fontSize: 16)),
      ),
      body: TapPageTurnRegion(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Outcomes
              _sectionHeader('🎯 学习目标', isDark),
              _markdownBlock(unit.outcomes, isDark),
              const SizedBox(height: 12),
              _actionButton(
                icon: Icons.edit,
                label: '✍️ 写作练习',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          GrammarWritingScreen(unit: widget.unit),
                    ),
                  );
                },
                color: Colors.green,
                isDark: isDark,
              ),
              const SizedBox(height: 24),

              // Grammar Chart
              _sectionHeader('📊 语法形式表', isDark),
              _markdownBlock(unit.chart, isDark),
              const SizedBox(height: 24),

              // Chinese Guide
              _sectionHeader('🇨🇳 中文对比解析', isDark),
              _markdownBlock(unit.chineseGuide, isDark),
              const SizedBox(height: 24),

              // Key Rules
              _sectionHeader('⚡ 核心规则', isDark),
              _markdownBlock(unit.keyRules, isDark),
              const SizedBox(height: 24),

              // Common Mistakes
              _sectionHeader('❌ 常犯错误', isDark),
              _markdownBlock(unit.commonMistakes, isDark),
              const SizedBox(height: 24),

              // Vocabulary
              _sectionHeader('📝 本节词汇', isDark),
              _markdownBlock(unit.vocabulary, isDark),
              const SizedBox(height: 32),

              // AI Action Buttons
              _sectionHeader('🤖 AI 辅助', isDark),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      icon: Icons.edit_note,
                      label: '生成练习',
                      onTap: _generateExercise,
                      color: Colors.blue,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _actionButton(
                      icon: Icons.help_outline,
                      label: '提问',
                      onTap: _showAskQuestion,
                      color: Colors.deepPurpleAccent,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _actionButton(
                  icon: Icons.spellcheck,
                  label: '句子批改',
                  onTap: _showCorrectSentence,
                  color: Colors.teal,
                  isDark: isDark,
                ),
              ),
              if (_isLoading) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
    );
  }

  Widget _markdownBlock(String data, bool isDark) {
    return MarkdownBody(
      data: data,
      softLineBreak: true,
      selectable: true,
      styleSheet: getAcademicMarkdownStyle(context),
      extensionSet: md.ExtensionSet(
        [const md.FencedCodeBlockSyntax()],
        [md.EmojiSyntax(), HighlightSyntax()],
      ),
      builders: {'highlight': HighlightBuilder(context)},
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    required bool isDark,
  }) {
    return TapPageTurnIgnore(
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: isDark ? 0.2 : 0.1),
          foregroundColor: color.withValues(alpha: isDark ? 0.8 : 1.0),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
