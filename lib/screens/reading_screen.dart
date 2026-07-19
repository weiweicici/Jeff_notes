import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/reading_quiz_service.dart';
import '../services/supabase_config.dart';
import 'reading_session_screen.dart';
import 'reading_detail_screen.dart';

class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key});
  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEntries());
  }

  Future<void> _loadEntries() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final data = await SupabaseConfig.client
          .from('archives')
          .select('id,title,content_md,created_at,metadata')
          .eq('module', 'reading')
          .order('created_at', ascending: false);
      _entries = List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      _error = '查询异常: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.menu_book, size: 32),
                title: const Text('选择教材章节', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Pathways 3 Third Edition'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _showUnitPicker();
                },
              ),
              const Divider(indent: 72),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate, size: 32),
                title: const Text('导入截图或 PDF', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('拍照 / PDF 导入真实教材'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateToImport();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUnitPicker() {
    final units = PathwaysUnit.values.where((u) => u != PathwaysUnit.none).toList();
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择 Pathways 3 单元'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('Pathways 3 Reading & Writing, Third Edition',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          const SizedBox(height: 8),
          for (final unit in units)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _generatePathwaysContent(unit);
              },
              child: ListTile(
                dense: true,
                title: Text(_unitLabel(unit)),
              ),
            ),
        ],
      ),
    );
  }

  String _unitLabel(PathwaysUnit unit) {
    switch (unit) {
      case PathwaysUnit.unit1: return 'Unit 1: Shopping Psychology';
      case PathwaysUnit.unit2: return "Unit 2: It's In My DNA";
      case PathwaysUnit.unit3: return 'Unit 3: On the Move';
      case PathwaysUnit.unit4: return 'Unit 4: Our Changing Planet';
      case PathwaysUnit.unit5: return 'Unit 5: Rise to the Top';
      case PathwaysUnit.unit6: return 'Unit 6: Design with Purpose';
      case PathwaysUnit.unit7: return 'Unit 7: Inspired to Protect';
      case PathwaysUnit.unit8: return 'Unit 8: Traditional and Modern Medicine';
      case PathwaysUnit.unit9: return 'Unit 9: Uncovering the Past';
      case PathwaysUnit.unit10: return 'Unit 10: Feelings & Emotions';
      default: return '';
    }
  }

  Future<void> _generatePathwaysContent(PathwaysUnit unit) async {
    if (!mounted) return;

    // 优先查本地内置数据
    final data = ReadingQuizService.getPathwaysLocalContent(unit);
    String content;
    if (data != null) {
      content = data.fullContent;
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      final aiContent = await ReadingQuizService.getPathwaysContent(unit);
      if (!mounted) return;
      Navigator.of(context).pop();
      content = aiContent;

      if (content.startsWith('[')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(content)),
          );
        }
        return;
      }
    }

    final title = 'Pathways 3 - ${_unitLabel(unit)}';
    final hash = md5.convert(utf8.encode('${content}_${DateTime.now().microsecondsSinceEpoch}')).toString();

    try {
      final saved = await SupabaseConfig.client
          .from('archives')
          .insert({
            'module': 'reading',
            'title': title,
            'content_md': content,
            'file_hash': hash,
            'metadata': {'source': 'pathways', 'unit': unit.name, 'unitName': _unitLabel(unit)},
            'file_size': content.length,
          })
          .select('id')
          .single();

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReadingDetailScreen(
              id: saved['id'],
              title: title,
              contentMd: content,
            ),
          ),
        );
        _loadEntries();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _navigateToImport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReadingSessionScreen()),
    );
    _loadEntries();
  }

  Future<void> _deleteEntry(String id) async {
    try {
      await SupabaseConfig.client.from('archives').delete().eq('id', id);
      _loadEntries();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.length < 10) return '';
    return raw.substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读精读'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEntries,
            tooltip: '刷新',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: Text('$_error', style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ),
                )
              : _entries.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _loadEntries,
                      child: ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.menu_book, size: 64, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text('暂无阅读记录', style: TextStyle(color: Colors.grey, fontSize: 18)),
                                  SizedBox(height: 8),
                                  Text('点击 + 号选择教材章节或导入截图/PDF', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadEntries,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final e = _entries[index];
                          final meta = e['metadata'] is Map ? Map<String, dynamic>.from(e['metadata']) : <String, dynamic>{};
                          final source = meta['source'] as String?;
                          final pageCount = meta['pageCount']?.toString();
                          final subtitle = source == 'pathways'
                              ? meta['unitName'] as String? ?? 'Pathways 3'
                              : pageCount != null ? '$pageCount 页' : '';
                          final leadingIcon = source == 'pathways' ? Icons.menu_book : Icons.description;
                          final title = (e['title'] as String?) ?? '未命名';
                          final date = _formatDate(e['created_at'] as String?);
                          return Dismissible(
                            key: ValueKey(e['id']),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.red,
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => _deleteEntry(e['id']),
                            child: Card(
                              child: ListTile(
                                leading: Icon(leadingIcon, size: 32),
                                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('$subtitle · $date' == ' · $date' ? date : '$subtitle · $date'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ReadingDetailScreen(
                                        id: e['id'],
                                        title: title,
                                        contentMd: e['content_md'] as String? ?? '',
                                      ),
                                    ),
                                  );
                                  _loadEntries();
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
