import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:intl/intl.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import '../models.dart';
import '../recording_provider.dart';
import '../services/grammar_service.dart';
import '../services/grammar_repository.dart';
import '../services/supabase_config.dart';
import '../services/tts_service.dart';
import '../widgets/academic_markdown.dart';
import 'history_screen.dart';

class GrammarWritingScreen extends StatefulWidget {
  final GrammarUnit? unit;
  const GrammarWritingScreen({super.key, this.unit});
  @override
  State<GrammarWritingScreen> createState() => _GrammarWritingScreenState();
}

class _GrammarWritingScreenState extends State<GrammarWritingScreen> {
  List<GrammarPart>? _parts;
  GrammarPart? _selectedPart;
  Set<GrammarUnit> _selectedUnits = {};
  Set<GrammarPart> _selectedParts = {};
  String? _selectedTheme;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _loadingParts = true;
  String _result = '';
  bool _combinedMode = false;

  static const _themes = [
    _ThemeOption(icon: Icons.place, label: '地点', value: 'a place'),
    _ThemeOption(icon: Icons.person, label: '人物', value: 'a person'),
    _ThemeOption(icon: Icons.event, label: '事件', value: 'an event'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.unit != null) {
      _selectedUnits = {widget.unit!};
      _selectedPart = _partContaining(widget.unit!);
    }
    _loadParts();
  }

  GrammarPart? _partContaining(GrammarUnit unit) {
    if (_parts == null) return null;
    for (final p in _parts!) {
      if (p.units.any((u) => u.id == unit.id)) return p;
    }
    return null;
  }

  Future<void> _loadParts() async {
    setState(() => _loadingParts = true);
    try {
      final parts = await GrammarRepository.loadParts();
      if (mounted) setState(() {
        _parts = parts;
        if (_selectedPart == null && parts.isNotEmpty) {
          _selectedPart = parts.first;
        }
        _loadingParts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingParts = false);
    }
  }

  bool get _canGenerate {
    if (_selectedTheme == null) return false;
    if (_combinedMode) return _selectedParts.length >= 2;
    return _selectedPart != null;
  }

  Future<void> _generate() async {
    if (!_canGenerate) return;
    setState(() { _isLoading = true; _result = ''; });
    try {
      if (_combinedMode) {
        final parts = _selectedParts.toList();
        final result = await GrammarService.generateCombinedSample(parts, _selectedTheme!);
        if (mounted) {
          setState(() { _result = result; _isLoading = false; });
          _showResultDialog();
          // 自动保存至存档中心（后台发起）
          if (mounted) _saveToArchive();
        }
      } else {
        final unit = _selectedUnits.isNotEmpty
            ? _selectedUnits.first
            : _selectedPart!.units.first;
        final unitTitles = _selectedUnits.isNotEmpty
            ? _selectedUnits.map((u) => u.title).join('、')
            : '';
        final result = await GrammarService.generateWritingSample(
          unit, _selectedTheme!,
          partId: _selectedPart!.id,
          focusUnits: unitTitles.isNotEmpty ? unitTitles : null,
        );
        if (mounted) {
          setState(() { _result = result; _isLoading = false; });
          _showResultDialog();
          // 自动保存至存档中心（后台发起）
          if (mounted) _saveToArchive();
        }
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _result = '生成失败: $e'; });
    }
  }

  void _showResultDialog() {
    if (_result.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Text('✍️ 写作范文', style: TextStyle(fontSize: 18)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📖 英文范文', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildEnglishSection(_result),
                const SizedBox(height: 24),
                const Text('🇨🇳 中文翻译', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildChineseSection(_result),
                const SizedBox(height: 24),
                const Text('🏷️ 语法标注', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                MarkdownBody(
                  data: _getAnnotationText(_result),
                  softLineBreak: true,
                  selectable: true,
                  styleSheet: getAcademicMarkdownStyle(context),
                  extensionSet: md.ExtensionSet([const md.FencedCodeBlockSyntax()], [md.EmojiSyntax(), HighlightSyntax()]),
                  builders: {'highlight': HighlightBuilder(context)},
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: '朗读英文',
            onPressed: () => _playEnglish(ctx),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveToArchive();
            },
            child: const Text('💾 保存'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _playEnglish(BuildContext dialogContext) {
    final englishContent = _getEnglishText(_result);
    if (englishContent.isEmpty) return;
    try {
      final tts = TtsService();
      final provider = context.read<RecordingProvider>();
      tts.speakEnglish(
        englishContent,
        geminiKey: provider.geminiKey,
        siliconFlowKey: provider.siliconFlowKey,
      );
    } catch (e) {
      if (dialogContext.mounted && e.toString().contains('NoHeadphones')) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('⚠️ 未检测到耳机 (${e.toString().replaceAll("Exception: ", "")})', style: const TextStyle(fontSize: 13)),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  String _getEnglishText(String full) {
    const startTag = '## 英文全文';
    const endTag = '## 中文翻译';
    final start = full.indexOf(startTag);
    if (start == -1) return '';
    final end = full.indexOf(endTag, start + startTag.length);
    return end > start
        ? full.substring(start + startTag.length, end).trim()
        : full.substring(start + startTag.length).trim();
  }

  // 构建英文全文部分
  Widget _buildEnglishSection(String full) {
    const startTag = '## 英文全文';
    const endTag = '## 中文翻译';
    final start = full.indexOf(startTag);
    if (start == -1) return const SizedBox();
    final end = full.indexOf(endTag, start + startTag.length);
    final content = end > start 
        ? full.substring(start + startTag.length, end).trim()
        : full.substring(start + startTag.length).trim();
    return MarkdownBody(
      data: content,
      softLineBreak: true,
      selectable: true,
      styleSheet: getAcademicMarkdownStyle(context),
      extensionSet: md.ExtensionSet([const md.FencedCodeBlockSyntax()], [md.EmojiSyntax(), HighlightSyntax()]),
      builders: {'highlight': HighlightBuilder(context)},
    );
  }

  // 构建中文翻译部分
  Widget _buildChineseSection(String full) {
    const chineseTag = '## 中文翻译';
    const annotationTag = '## 语法标注';
    final chineseStart = full.indexOf(chineseTag);
    if (chineseStart == -1) return const SizedBox();
    final chineseEnd = full.indexOf(annotationTag, chineseStart + chineseTag.length);
    final content = chineseEnd > chineseStart
        ? full.substring(chineseStart + chineseTag.length, chineseEnd).trim()
        : full.substring(chineseStart + chineseTag.length).trim();
    return MarkdownBody(
      data: content,
      softLineBreak: true,
      selectable: true,
      styleSheet: getAcademicMarkdownStyle(context),
      extensionSet: md.ExtensionSet(const [], const []),
      builders: {},
    );
  }

  // 获取语法标注文本
  String _getAnnotationText(String full) {
    const annotationTag = '## 语法标注';
    final start = full.indexOf(annotationTag);
    if (start == -1) return '';
    return full.substring(start).trim();
  }

  Future<void> _saveToArchive() async {
    if (_result.isEmpty || _isSaving) return;

    var userId = '';
    try {
      userId = SupabaseConfig.currentUserId;
    } catch (e) {
      // 未登录，user_id 留空
    }

    setState(() { _isSaving = true; });

    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
      final firstLine = _result.split('\n').firstOrNull ?? 'Grammar Writing';
      final safeTopic = firstLine.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').replaceAll(' ', '_').trim();
      final filename = safeTopic.isNotEmpty ? 'Jeff_Grammar_${safeTopic}_$dateStr.md' : 'Jeff_Grammar_$dateStr.md';
      final contentMd = _result;

      // 1. 保存到本地 .md 文件
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsString(contentMd);
      debugPrint('[Grammar Save] Saved to local file: ${file.path}');

      // 2. 同步到 Supabase
      final hash = md5.convert(utf8.encode('${contentMd}_${DateTime.now().microsecondsSinceEpoch}')).toString();
      final map = {
        'module': 'grammar',
        'title': filename,
        'content_md': contentMd,
        'file_hash': hash,
        'metadata': {'source': 'grammar_writing'},
        'file_size': contentMd.length,
      };
      if (userId.isNotEmpty) {
        map['user_id'] = userId;
      }

      await SupabaseConfig.client.from('archives').insert(map);

      if (mounted && userId.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 已保存到本地 .md 文件与存档中心'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('[Grammar Save Error] $e');
      if (mounted && !e.toString().contains('Not authenticated')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loadingParts) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('✍️ 写作练习'),
          actions: [
            IconButton(
              icon: const Icon(Icons.history_edu),
              tooltip: '查看存档',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen(initialModuleFilter: 'grammar'))),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('✍️ 写作练习'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_edu),
            tooltip: '查看存档',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen(initialModuleFilter: 'grammar'))),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode Toggle
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('单章练习'), icon: Icon(Icons.article_outlined)),
                ButtonSegment(value: true, label: Text('综合练习'), icon: Icon(Icons.auto_stories)),
              ],
              selected: {_combinedMode},
              onSelectionChanged: (s) => setState(() => _combinedMode = s.first),
            ),
            const SizedBox(height: 24),

            if (widget.unit != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '📌 当前语法单元: ${widget.unit!.title}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.green[200] : Colors.green[800],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Part Selection
            if (_combinedMode) ...[
              Text(
                '选择要综合练习的章节',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '已选 ${_selectedParts.length} 个章节（至少选 2 个）',
                style: TextStyle(fontSize: 14, color: isDark ? Colors.white54 : Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              ...?_parts?.map((p) {
                final selected = _selectedParts.contains(p);
                return CheckboxListTile(
                  dense: true,
                  title: Text(p.title, style: const TextStyle(fontSize: 14)),
                  value: selected,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedParts.add(p);
                    } else {
                      _selectedParts.remove(p);
                    }
                  }),
                  activeColor: Colors.green,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }),
            ] else ...[
              Text(
                '选择章节（Part）',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GrammarPart>(
                value: _selectedPart,
                dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                decoration: InputDecoration(
                  labelText: 'Part',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                items: _parts?.map((p) => DropdownMenuItem(
                  value: p,
                  child: Text(p.title, overflow: TextOverflow.ellipsis),
                )).toList() ?? [],
                onChanged: (p) {
                  if (p != null) setState(() {
                    _selectedPart = p;
                    _selectedUnits = {};
                  });
                },
              ),
              const SizedBox(height: 12),
              Text(
                '选择具体单元（可选，不选则不限）',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              if (_selectedPart != null)
                ..._selectedPart!.units.map((u) {
                  final checked = _selectedUnits.contains(u);
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(u.title, style: const TextStyle(fontSize: 13)),
                    value: checked,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedUnits.add(u);
                      } else {
                        _selectedUnits.remove(u);
                      }
                    }),
                    activeColor: Colors.green,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }),
            ],
            const SizedBox(height: 24),

            // Theme
            Text(
              '选择主题大类',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _themes.map((t) {
                final selected = _selectedTheme == t.value;
                return ChoiceChip(
                  selected: selected,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.icon, size: 18),
                      const SizedBox(width: 6),
                      Text(t.label),
                    ],
                  ),
                  onSelected: (v) => setState(() => _selectedTheme = v ? t.value : null),
                  selectedColor: Colors.green.withValues(alpha: 0.2),
                  backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
                  labelStyle: TextStyle(
                    color: selected
                        ? (isDark ? Colors.green[200] : Colors.green[800])
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Generate Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _canGenerate && !_isLoading ? _generate : null,
                icon: _isLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_isLoading ? '生成中...' : '🚀 生成范文'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            // Error result (only shown when generation fails)
            if (_result.isNotEmpty && _result.startsWith('生成失败')) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_result, style: const TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemeOption {
  final IconData icon;
  final String label;
  final String value;
  const _ThemeOption({required this.icon, required this.label, required this.value});
}
