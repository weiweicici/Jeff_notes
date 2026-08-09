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
import '../services/grammar_writing_draft_service.dart';
import '../services/supabase_config.dart';
import '../services/upload_cache.dart';
import '../services/file_sync_agent.dart';
import '../services/watch_sync_service.dart';
import 'history_screen.dart';
import 'note_detail_screen.dart';

String buildGrammarArchiveFilename({
  required String topic,
  String? contentType,
  required String dateStamp,
}) {
  final preferredLabel = topic.trim().isNotEmpty
      ? topic.trim()
      : (contentType?.trim().isNotEmpty == true
            ? contentType!.trim()
            : 'Writing');
  final sanitized = preferredLabel
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'^[_\.]+|[_\.]+$'), '');
  // iOS limits one filename component to 255 UTF-8 bytes. Forty-eight Unicode
  // code points leave ample room for the fixed prefix, date, and extension.
  final shortLabel = String.fromCharCodes(sanitized.runes.take(48));
  final label = shortLabel.isEmpty ? 'Writing' : shortLabel;
  return 'Jeff_Grammar_${label}_$dateStamp.md';
}

class GrammarWritingScreen extends StatefulWidget {
  final GrammarUnit? unit;
  final String? initialTopic;
  final bool autoGenerate;
  final GrammarWritingLaunchOptions? launchOptions;
  const GrammarWritingScreen({
    super.key,
    this.unit,
    this.initialTopic,
    this.autoGenerate = false,
    this.launchOptions,
  });
  @override
  State<GrammarWritingScreen> createState() => _GrammarWritingScreenState();
}

class _GrammarWritingScreenState extends State<GrammarWritingScreen> {
  List<GrammarPart>? _parts;
  GrammarPart? _selectedPart;
  Set<GrammarUnit> _selectedUnits = {};
  final Set<GrammarPart> _selectedCombinedParts = {};
  final Set<GrammarUnit> _selectedCombinedUnits = {};
  final TextEditingController _combinedTopicController =
      TextEditingController();
  String? _selectedTheme;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _loadingParts = true;
  String _result = '';
  bool _combinedMode = true;
  bool _requireAllSelectedGrammar = false;
  bool _autoGenerationStarted = false;

  int get _combinedCoverageSelectionCount => _selectedCombinedUnits.isNotEmpty
      ? _selectedCombinedUnits.length
      : _selectedCombinedParts.length;

  bool get _showsRequireAllGrammarOption => _combinedCoverageSelectionCount > 6;

  static const _themes = [
    _ThemeOption(icon: Icons.place, label: '地点', value: 'a place'),
    _ThemeOption(icon: Icons.person, label: '人物', value: 'a person'),
    _ThemeOption(icon: Icons.event, label: '事件', value: 'an event'),
    _ThemeOption(
      icon: Icons.directions_run,
      label: '活动/日常',
      value: 'an activity or daily routine',
    ),
    _ThemeOption(
      icon: Icons.photo_album,
      label: '经历',
      value: 'a personal experience',
    ),
    _ThemeOption(
      icon: Icons.card_giftcard,
      label: '物品/事物',
      value: 'an important object or thing',
    ),
    _ThemeOption(
      icon: Icons.flag,
      label: '计划/目标',
      value: 'a future plan or goal',
    ),
    _ThemeOption(
      icon: Icons.tips_and_updates,
      label: '问题/建议',
      value: 'a problem and possible advice or solutions',
    ),
    _ThemeOption(
      icon: Icons.more_horiz,
      label: '其他',
      value: 'a topic of your choice',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _combinedTopicController.text = widget.initialTopic?.trim() ?? '';
    if (widget.unit != null) {
      _selectedUnits = {widget.unit!};
      _selectedCombinedUnits.add(widget.unit!);
      _selectedPart = _partContaining(widget.unit!);
    }
    _loadParts();
  }

  @override
  void dispose() {
    _combinedTopicController.dispose();
    super.dispose();
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
      var draft = widget.unit == null
          ? await GrammarWritingDraftService.instance.load()
          : const GrammarWritingDraft();
      final launch = widget.launchOptions;
      if (launch != null) {
        switch (launch.selectionMode) {
          case GrammarWritingSelectionMode.phone:
            if (launch.contentType != null) {
              draft = draft.copyWith(contentType: launch.contentType);
            }
            break;
          case GrammarWritingSelectionMode.automatic:
            draft = GrammarWritingDraft(
              contentType: launch.contentType,
              updatedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
            );
            break;
          case GrammarWritingSelectionMode.custom:
            draft = GrammarWritingDraft(
              selectedPartIds: launch.selectedPartIds,
              selectedUnitIds: launch.selectedUnitIds,
              contentType: launch.contentType,
              requireAllSelectedGrammar: launch.requireAllSelectedGrammar,
              updatedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
            );
            break;
        }
      }
      if (mounted) {
        setState(() {
          _parts = parts;
          if (widget.unit == null) {
            _applyCombinedDraft(parts, draft);
          } else {
            final matchingUnit = parts
                .expand((part) => part.units)
                .where((unit) => unit.id == widget.unit!.id)
                .firstOrNull;
            if (matchingUnit != null) {
              _selectedUnits = {matchingUnit};
              _selectedCombinedUnits
                ..clear()
                ..add(matchingUnit);
              _selectedPart = _partContaining(matchingUnit);
            }
          }
          if (_selectedPart == null && parts.isNotEmpty) {
            _selectedPart = parts.first;
          }
          _loadingParts = false;
        });
      }
      if (widget.unit == null) {
        if (launch != null) {
          await GrammarWritingDraftService.instance.save(_currentCombinedDraft());
        }
        await _pushCombinedDraftToWatch();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingParts = false);
    }
    if (mounted && widget.autoGenerate && !_autoGenerationStarted) {
      _autoGenerationStarted = true;
      unawaited(_generate());
    }
  }

  void _applyCombinedDraft(
    List<GrammarPart> parts,
    GrammarWritingDraft draft,
  ) {
    final partById = {for (final part in parts) part.id: part};
    final unitById = {
      for (final part in parts)
        for (final unit in part.units) unit.id: unit,
    };
    _selectedCombinedParts
      ..clear()
      ..addAll(
        draft.selectedPartIds
            .map((id) => partById[id])
            .whereType<GrammarPart>(),
      );
    _selectedCombinedUnits
      ..clear()
      ..addAll(
        draft.selectedUnitIds
            .map((id) => unitById[id])
            .whereType<GrammarUnit>(),
      );
    _selectedTheme = draft.contentType;
    _requireAllSelectedGrammar = draft.requireAllSelectedGrammar;
    if (!_showsRequireAllGrammarOption) {
      _requireAllSelectedGrammar = false;
    }
  }

  GrammarWritingDraft _currentCombinedDraft() => GrammarWritingDraft(
        selectedPartIds: _selectedCombinedParts.map((part) => part.id).toSet(),
        selectedUnitIds: _selectedCombinedUnits.map((unit) => unit.id).toSet(),
        contentType: _selectedTheme,
        requireAllSelectedGrammar: _requireAllSelectedGrammar,
        updatedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
      );

  Future<void> _persistCombinedDraft() async {
    if (!_combinedMode) return;
    final draft = _currentCombinedDraft();
    await GrammarWritingDraftService.instance.save(draft);
    await _pushCombinedDraftToWatch(draft: draft);
  }

  Future<void> _pushCombinedDraftToWatch({GrammarWritingDraft? draft}) async {
    final parts = _parts;
    if (parts == null) return;
    await WatchSyncService.instance.updateGrammarWritingConfig(
      (draft ?? _currentCombinedDraft()).toWatchPayload(parts),
    );
  }

  Future<void> _reportWatchState(String state, String message) async {
    final requestId = widget.launchOptions?.requestId;
    if (requestId == null || requestId.isEmpty) return;
    await WatchSyncService.instance.updateGrammarWritingState(
      requestId: requestId,
      state: state,
      message: message,
    );
  }

  void _updateCombinedSelection(VoidCallback update) {
    setState(() {
      update();
      if (!_showsRequireAllGrammarOption) {
        _requireAllSelectedGrammar = false;
      }
    });
    unawaited(_persistCombinedDraft());
  }

  bool get _canGenerate {
    if (_combinedMode) return true;
    if (_selectedTheme == null) return false;
    return _selectedPart != null;
  }

  Future<void> _generate() async {
    if (!_canGenerate) return;
    if (_combinedMode) await _persistCombinedDraft();
    setState(() {
      _isLoading = true;
      _result = '';
    });
    unawaited(_reportWatchState('generating', 'AI 正在生成文章'));
    try {
      if (_combinedMode) {
        final units = _selectedCombinedUnits.toList();
        final result = await GrammarService.generateCombinedSample(
          availableParts: _parts ?? const [],
          selectedParts: _selectedCombinedParts.toList(),
          selectedUnits: units,
          topic: _combinedTopicController.text.trim(),
          contentType: _selectedTheme,
          requireAllSelectedGrammar: _requireAllSelectedGrammar,
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
      unawaited(_reportWatchState('error', '生成失败，请在手机查看原因'));
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

    await _reportWatchState('saving', '文章已生成，正在保存 MD');
    final file = await _saveToArchive();
    if (!mounted || file == null) {
      unawaited(_reportWatchState('error', '文章生成成功，但保存 MD 失败'));
      return;
    }

    await _reportWatchState('syncing', 'MD 已保存，正在发送到手表');
    final queued = await WatchSyncService.instance.queueMarkdownDocument(
      title: file.uri.pathSegments.last,
      markdown: result,
    );
    await _reportWatchState(
      queued ? 'completed' : 'syncing',
      queued ? '已发送，文档到达后会自动打开' : '手机已保存，等待手表连接',
    );

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
      final filename = buildGrammarArchiveFilename(
        topic: _combinedMode ? _combinedTopicController.text : '',
        contentType: _selectedTheme,
        dateStamp: dateStr,
      );
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

  Widget _buildThemeChoices(bool isDark) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _themes.map((theme) {
        final selected = _selectedTheme == theme.value;
        return ChoiceChip(
          selected: selected,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(theme.icon, size: 18),
              const SizedBox(width: 6),
              Text(theme.label),
            ],
          ),
          onSelected: (value) {
            if (_combinedMode) {
              _updateCombinedSelection(
                () => _selectedTheme = value ? theme.value : null,
              );
            } else {
              setState(() => _selectedTheme = value ? theme.value : null);
            }
          },
          selectedColor: Colors.green.withValues(alpha: 0.2),
          backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
          labelStyle: TextStyle(
            color: selected
                ? (isDark ? Colors.green[200] : Colors.green[800])
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        );
      }).toList(),
    );
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
                '老师给出的写作主题',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('combinedWritingTopic'),
                controller: _combinedTopicController,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText:
                      '输入老师给出的完整题目，例如：Describe an important event in your life.',
                  helperText: '可输入完整题目，也可留空使用预设或让 AI 自选',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '快捷主题（可选）',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '可单独使用，也可与输入内容一起作为写作要求',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 10),
              _buildThemeChoices(isDark),
              const SizedBox(height: 24),
              Text(
                '选择语法（可选）',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '已选 ${_selectedCombinedParts.length} 章、${_selectedCombinedUnits.length} 个具体语法。选 1–6 个具体语法会逐项覆盖；选更多时默认从中挑最适合题目的 4–6 个。全部留空则自动搭配 4–6 种。',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                ),
              ),
              if (_showsRequireAllGrammarOption) ...[
                const SizedBox(height: 4),
                SwitchListTile.adaptive(
                  key: const ValueKey('requireAllSelectedGrammarSwitch'),
                  contentPadding: EdgeInsets.zero,
                  value: _requireAllSelectedGrammar,
                  onChanged: (value) => _updateCombinedSelection(
                    () => _requireAllSelectedGrammar = value,
                  ),
                  title: Text(
                    _selectedCombinedUnits.isNotEmpty
                        ? '老师指定：全部 $_combinedCoverageSelectionCount 个具体语法都必须覆盖'
                        : '老师指定：全部 $_combinedCoverageSelectionCount 个章节都必须覆盖',
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text('默认关闭：AI 自动选择 4–6 项；老师明确要求 7 项以上时再打开。'),
                ),
              ],
              const SizedBox(height: 8),
              ...?_parts?.map((p) {
                final partSelected = _selectedCombinedParts.contains(p);
                final selectedCount = p.units
                    .where(_selectedCombinedUnits.contains)
                    .length;
                final selectionSummary = [
                  if (partSelected) '整章已选',
                  if (selectedCount > 0) '具体语法 $selectedCount 项',
                ].join(' · ');
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: Checkbox(
                      key: ValueKey('combinedPartCheckbox_${p.id}'),
                      value: partSelected,
                      onChanged: (value) => _updateCombinedSelection(() {
                        if (value == true) {
                          _selectedCombinedParts.add(p);
                        } else {
                          _selectedCombinedParts.remove(p);
                        }
                      }),
                    ),
                    title: Text(p.title, style: const TextStyle(fontSize: 14)),
                    subtitle: selectionSummary.isEmpty
                        ? null
                        : Text(selectionSummary),
                    children: p.units.map((u) {
                      final checked = _selectedCombinedUnits.contains(u);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(
                          left: 16,
                          right: 12,
                        ),
                        title: Text(
                          u.title,
                          style: const TextStyle(fontSize: 13),
                        ),
                        value: checked,
                        onChanged: (v) => _updateCombinedSelection(() {
                          if (v == true) {
                            _selectedCombinedUnits.add(u);
                          } else {
                            _selectedCombinedUnits.remove(u);
                          }
                        }),
                        activeColor: Colors.green,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }).toList(),
                  ),
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

            if (!_combinedMode) ...[
              // Keep the existing single-part theme flow unchanged.
              Text(
                '选择主题大类',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              _buildThemeChoices(isDark),
              const SizedBox(height: 24),
            ],

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
