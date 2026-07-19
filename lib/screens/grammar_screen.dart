import 'package:flutter/material.dart';
import '../models.dart';
import '../services/grammar_repository.dart';
import 'grammar_detail_screen.dart';

class GrammarScreen extends StatefulWidget {
  const GrammarScreen({super.key});
  @override
  State<GrammarScreen> createState() => _GrammarScreenState();
}

class _GrammarScreenState extends State<GrammarScreen> {
  List<GrammarPart>? _parts;
  GrammarPart? _selectedPart;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final parts = await GrammarRepository.loadParts();
      if (mounted) setState(() {
        _parts = parts;
        _selectedPart ??= parts.isNotEmpty ? parts.first : null;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '加载失败: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('🔤 语法精讲')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _parts == null || _parts!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('🔤 语法精讲')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? '暂无数据', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: DropdownButtonHideUnderline(
          child: DropdownButton<GrammarPart>(
            value: _selectedPart,
            isExpanded: false,
            dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
            items: _parts!.map((part) {
              return DropdownMenuItem(
                value: part,
                child: Text(part.title, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (part) {
              if (part != null) setState(() => _selectedPart = part);
            },
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _selectedPart!.units.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: (context, index) {
            final unit = _selectedPart!.units[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? Colors.blueGrey[700] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.blueAccent[200] : Colors.blue[700],
                  ),
                ),
              ),
              title: Text(
                unit.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GrammarDetailScreen(unit: unit),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
