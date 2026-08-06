import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import '../models.dart';
import '../services/grammar_service.dart';
import '../services/grammar_repository.dart';
import '../services/supabase_config.dart';
import '../services/upload_cache.dart';
import '../services/file_sync_agent.dart';
import 'history_screen.dart';
import 'note_detail_screen.dart';

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
  final Set<GrammarPart> _selectedParts = {};
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
      if (mounted)
        setState(() {
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
    setState(() {
      _isLoading = true;
      _result = '';
    });
    try {
      if (_combinedMode) {
        final parts = _selectedParts.toList();
        final result = await GrammarService.generateCombinedSample(
          parts,
          _selectedTheme!,
        );
        if (mounted) {
          await _openGeneratedWriting(result);
        }
      } else {
        final unit = _selectedUnits.isNotEmpty
            ? _selectedUnits.first
            : _selectedPart!.units.first;
        final unitTitles = _selectedUnits.isNotEmpty
            ? _selectedUnits.map((u) => u.title).join('、')
            : '';
        final result = await GrammarService.generateWritingSample(
          unit,
          _selectedTheme!,
          partId: _selectedPart!.id,
          focusUnits: unitTitles.isNotEmpty ? unitTitles : null,
        );
        if (mounted) {
          await _openGeneratedWriting(result);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _result = '生成失败: $e';
        });
      }
    }
  }

  Future<void> _openGeneratedWriting(String result) async {
    setState(() {
      _result = result;
      _isLoading = false;
    });

    final file = await _saveToArchive();
    if (!mounted || file == null) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(file: file, autoPlayEnglish: true),
      ),
    );
  }

  Future<File?> _saveToArchive() async {
    if (_result.isEmpty || _isSaving) return null;

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
      final firstLine = _result.split('\n').firstOrNull ?? 'Grammar Writing';
      final safeTopic = firstLine
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
          .replaceAll(' ', '_')
          .trim();
      final filename = safeTopic.isNotEmpty
          ? 'Jeff_Grammar_${safeTopic}_$dateStr.md'
          : 'Jeff_Grammar_$dateStr.md';
      final contentMd = _result;

      // 1. 保存到本地 .md 文件
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsString(contentMd);
      debugPrint('[Grammar Save] Saved to local file: ${file.path}');
      // The detail page and automatic dictation must not wait for cloud sync.
      unawaited(_syncArchive(file, filename, contentMd));
      return file;
    } catch (e) {
      debugPrint('[Grammar Save Error] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 保存失败: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _syncArchive(
    File file,
    String filename,
    String contentMd,
  ) async {
    try {
      var userId = '';
      try {
        userId = SupabaseConfig.currentUserId;
      } catch (_) {
        // FileSyncAgent will retry after authentication becomes available.
      }

      // Hash only the content so repeated saves remain idempotent.
      final hash = md5.convert(utf8.encode(contentMd)).toString();
      final map = <String, dynamic>{
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

      await SupabaseConfig.client
          .from('archives')
          .upsert(map, onConflict: 'file_hash');
      await UploadCache.mark(hash);
    } catch (error) {
      debugPrint('[Grammar Supabase Upload Error] $error');
    } finally {
      if (await file.exists()) {
        await FileSyncAgent.instance.syncNow();
      }
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const HistoryScreen(initialModuleFilter: 'grammar'),
                ),
              ),
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const HistoryScreen(initialModuleFilter: 'grammar'),
              ),
            ),
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
                ButtonSegment(
                  value: false,
                  label: Text('单章练习'),
                  icon: Icon(Icons.article_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('综合练习'),
                  icon: Icon(Icons.auto_stories),
                ),
              ],
              selected: {_combinedMode},
              onSelectionChanged: (s) =>
                  setState(() => _combinedMode = s.first),
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
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                ),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                items:
                    _parts
                        ?.map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(
                              p.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList() ??
                    [],
                onChanged: (p) {
                  if (p != null)
                    setState(() {
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
                  onSelected: (v) =>
                      setState(() => _selectedTheme = v ? t.value : null),
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
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_isLoading ? '生成中...' : '🚀 生成范文'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.value,
  });
}
