import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import '../models.dart';
import '../services/grammar_service.dart';
import '../services/grammar_repository.dart';
import '../widgets/academic_markdown.dart';

class GrammarWritingScreen extends StatefulWidget {
  final GrammarUnit? unit; // From detail screen: pre-selected
  const GrammarWritingScreen({super.key, this.unit});

  @override
  State<GrammarWritingScreen> createState() => _GrammarWritingScreenState();
}

class _GrammarWritingScreenState extends State<GrammarWritingScreen> {
  List<GrammarPart>? _parts;
  GrammarPart? _selectedPart;
  GrammarUnit? _selectedUnit;
  String? _selectedTheme;
  bool _isLoading = false;
  bool _loadingParts = true;
  String _result = '';

  static const _themes = [
    _ThemeOption(icon: Icons.place, label: '地点', value: 'a place'),
    _ThemeOption(icon: Icons.person, label: '人物', value: 'a person'),
    _ThemeOption(icon: Icons.event, label: '事件', value: 'an event'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.unit != null) {
      _selectedUnit = widget.unit;
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
        _selectedUnit ??= null;
        _loadingParts = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingParts = false);
    }
  }

  Future<void> _generate() async {
    if (_selectedPart == null || _selectedTheme == null) return;
    setState(() { _isLoading = true; _result = ''; });
    final unit = _selectedUnit ?? _selectedPart!.units.first;
    final result = await GrammarService.generateWritingSample(unit, _selectedTheme!, partId: _selectedPart!.id);
    if (mounted) setState(() { _result = result; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loadingParts) {
      return Scaffold(
        appBar: AppBar(title: const Text('✍️ 写作练习')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('✍️ 写作练习')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  _selectedUnit = p.units.isNotEmpty ? p.units.first : null;
                });
              },
            ),
            const SizedBox(height: 12),
            Text(
              '选择单元（可选）',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<GrammarUnit?>(
              value: _selectedUnit,
              hint: Text('不限', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600])),
              dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              decoration: InputDecoration(
                labelText: 'Unit',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              items: [
                const DropdownMenuItem<GrammarUnit?>(
                  value: null,
                  child: Text('不限'),
                ),
                ...?_selectedPart?.units.map((u) => DropdownMenuItem<GrammarUnit?>(
                  value: u,
                  child: Text(u.title, overflow: TextOverflow.ellipsis),
                )),
              ],
              onChanged: (u) {
                setState(() => _selectedUnit = u);
              },
            ),
            const SizedBox(height: 24),
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
                  onSelected: (v) {
                    setState(() => _selectedTheme = v ? t.value : null);
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
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedTheme != null && _selectedUnit != null && !_isLoading
                  ? _generate : null,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
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
            if (_result.isNotEmpty) ...[
              const SizedBox(height: 24),
              MarkdownBody(
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
