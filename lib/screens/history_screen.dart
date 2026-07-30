import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'note_detail_screen.dart';
import '../services/supabase_config.dart';
import '../services/upload_cache.dart';

class _HistoryEntry {
  final String? id;
  final String title;
  final DateTime modified;
  final bool isLocal;
  final File? localFile;
  final String? cloudContent;
  final String? module;

  _HistoryEntry.local({
    this.id,
    required this.title,
    required this.modified,
    required this.localFile,
    this.module,
  })  : isLocal = true,
        cloudContent = null;

  _HistoryEntry.cloud({
    this.id,
    required this.title,
    required this.modified,
    required this.cloudContent,
    this.module,
  })  : isLocal = false,
        localFile = null;
}

class HistoryScreen extends StatefulWidget {
  final String? initialModuleFilter;
  const HistoryScreen({super.key, this.initialModuleFilter});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<_HistoryEntry> _entries = [];
  bool _isLoading = true;
  String _error = '';
  late String _selectedFilter;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialModuleFilter ?? 'all';
    _loadEntries();
  }

  String _moduleOfEntry(_HistoryEntry entry) {
    if (entry.module != null && entry.module!.isNotEmpty) {
      final m = entry.module!.toLowerCase();
      if (m == 'listening' || m == 'discussion' || m == 'notes') return 'notes';
      if (m == 'reading') return 'reading';
      if (m == 'essay') return 'essay';
      if (m == 'freetalk') return 'freetalk';
      if (m == 'grammar') return 'grammar';
      if (m == 'exam') return 'exam';
    }

    final t = entry.title.toLowerCase();
    if (t.contains('reading')) return 'reading';
    if (t.contains('essay')) return 'essay';
    if (t.contains('freetalk')) return 'freetalk';
    if (t.contains('grammar')) return 'grammar';
    if (t.contains('速记') || t.contains('exam')) return 'exam';
    if (t.contains('discussion') || t.contains('note') || t.contains('lecture') || t.contains('listening')) return 'notes';
    return 'other';
  }

  static String _inferModuleFromFileName(String filename) {
    final name = filename.toLowerCase();
    if (name.contains('essay')) return 'essay';
    if (name.contains('discussion')) return 'discussion';
    if (name.contains('freetalk')) return 'freetalk';
    if (name.contains('reading')) return 'reading';
    if (name.contains('速记')) return 'exam';
    if (name.contains('exam')) return 'exam';
    if (name.contains('grammar')) return 'grammar';
    return 'listening';
  }

  List<_HistoryEntry> get _filteredEntries {
    if (_selectedFilter == 'all') return _entries;
    return _entries.where((e) => _moduleOfEntry(e) == _selectedFilter).toList();
  }

  Future<void> _loadEntries() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final entities = await directory
          .list()
          .where((f) => f.path.endsWith('.md'))
          .toList();
      final localFiles = entities.whereType<File>().toList();
      localFiles.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );

      final localTitles = localFiles.map((f) => f.path.split('/').last).toSet();

      final List<_HistoryEntry> merged = localFiles.map(
        (f) => _HistoryEntry.local(
          title: f.path.split('/').last,
          modified: f.statSync().modified,
          localFile: f,
          module: _inferModuleFromFileName(f.path.split('/').last),
        ),
      ).toList();

      try {
        var userId = '';
        try { userId = SupabaseConfig.currentUserId; } catch (_) {}
        var query = SupabaseConfig.client
            .from('archives')
            .select('id,title,content_md,created_at,module');
        if (userId.isNotEmpty) {
          query = query.eq('user_id', userId);
        }
        final data = await query
            .or('module.eq.listening,module.eq.freetalk,module.eq.discussion,module.eq.essay,module.eq.exam,module.eq.grammar,module.eq.reading')
            .order('created_at', ascending: false);

        for (final row in List<Map<String, dynamic>>.from(data as List)) {
          final id = row['id']?.toString();
          final title = row['title'] as String? ?? '';
          final module = row['module'] as String?;
          if (localTitles.contains(title)) {
            final localIdx = merged.indexWhere((e) => e.title == title);
            if (localIdx != -1) {
              merged[localIdx] = _HistoryEntry.local(
                id: id,
                title: title,
                modified: merged[localIdx].modified,
                localFile: merged[localIdx].localFile,
                module: module,
              );
            }
            continue;
          }

          final createdAt = row['created_at'] as String?;
          merged.add(
            _HistoryEntry.cloud(
              id: id,
              title: title,
              modified: createdAt != null
                  ? DateTime.parse(createdAt)
                  : DateTime.now(),
              cloudContent: row['content_md'] as String?,
              module: module,
            ),
          );
        }
      } catch (e) {
        debugPrint("Load Cloud Error: $e");
      }

      merged.sort((a, b) => b.modified.compareTo(a.modified));

      if (mounted) {
        setState(() {
          _entries = merged;
          _isLoading = false;
          _error = '';
        });
      }
    } catch (e) {
      debugPrint("Load History Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  IconData _iconFor(String name) {
    if (name.contains('Grammar')) return Icons.abc_rounded;
    if (name.contains('Essay')) return Icons.edit_note_rounded;
    if (name.contains('Discussion')) return Icons.forum_outlined;
    if (name.contains('FreeTalk')) return Icons.chat_bubble_outline_rounded;
    if (name.contains('Reading')) return Icons.menu_book_rounded;
    return Icons.school_outlined;
  }

  Color _colorFor(String name) {
    if (name.contains('Grammar')) return Colors.orange;
    if (name.contains('Essay')) return Colors.deepPurpleAccent;
    if (name.contains('Discussion')) return Colors.deepPurpleAccent;
    if (name.contains('FreeTalk')) return Colors.teal;
    if (name.contains('Reading')) return Colors.green;
    return Colors.blueAccent;
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  Widget _buildFilterChips() {
    final filters = [
      {'id': 'all', 'label': '🌐 全部文档'},
      {'id': 'reading', 'label': '📖 精读阅读'},
      {'id': 'essay', 'label': '📝 短文写作'},
      {'id': 'freetalk', 'label': '🗣️ 自由对话'},
      {'id': 'grammar', 'label': '📚 语法练习'},
      {'id': 'exam', 'label': '📋 听力考试'},
      {'id': 'notes', 'label': '🎙️ 课堂笔记'},
    ];

    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = filters[index];
          final id = f['id']!;
          final label = f['label']!;
          final isSelected = _selectedFilter == id;

          return ChoiceChip(
            label: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedFilter = id),
            selectedColor: Theme.of(context).colorScheme.primaryContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          );
        },
      ),
    );
  }

  Future<void> _openEntry(_HistoryEntry entry) async {
    File? fileToOpen;
    if (entry.isLocal && entry.localFile != null) {
      fileToOpen = entry.localFile!;
    } else if (entry.cloudContent != null) {
      final dir = await getApplicationDocumentsDirectory();
      fileToOpen = File('${dir.path}/${entry.title}');
      await fileToOpen.writeAsString(entry.cloudContent!);
      // [BUG-12 Fix] 标记云端下载的内容 Hash 为已上传，防止 FileSyncAgent 当作新文件重复 insert
      final hash = md5.convert(utf8.encode(entry.cloudContent!)).toString();
      await UploadCache.mark(hash);
    }

    if (fileToOpen != null && mounted) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => NoteDetailScreen(file: fileToOpen!),
        ),
      );
      if (result == true) {
        _loadEntries();
      }
    }
  }

  Future<void> _deleteEntry(_HistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记'),
        content: Text('确定要删除 "${entry.title}" 吗？将同时清理本地文件与 Supabase 云端数据库，彻底无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // [BUG-07 Fix] 本地删除先执行（不依赖认证），云端删除分离，用 currentUser?.id 替代
      // 可能 throw StateError 的 currentUserId getter，防止本地已删但云端残留的不一致。
      bool localDeleted = false;
      try {
        if (entry.isLocal && entry.localFile != null) {
          if (await entry.localFile!.exists()) {
            await entry.localFile!.delete();
          }
          final wavPath = entry.localFile!.path.replaceAll('.md', '.wav');
          final wavFile = File(wavPath);
          if (await wavFile.exists()) {
            await wavFile.delete();
          }
        }
        localDeleted = true;
      } catch (e) {
        debugPrint("[HistoryScreen] Local delete error: $e");
      }

      if (entry.id != null && entry.id!.isNotEmpty) {
        try {
          // 安全取 userId，不再使用会 throw 的 currentUserId getter
          final userId = SupabaseConfig.client.auth.currentUser?.id;
          if (userId != null && userId.isNotEmpty) {
            await SupabaseConfig.client
                .from('archives')
                .delete()
                .eq('id', entry.id!)
                .eq('user_id', userId);
          } else {
            debugPrint("[HistoryScreen] Skipping cloud delete — user not authenticated.");
          }
        } catch (e) {
          debugPrint("[HistoryScreen] Cloud delete error: $e");
          if (mounted && localDeleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ 本地文件已删除，但云端记录清除失败，请刷新后重试'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      await _loadEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayEntries = _filteredEntries;

    return Scaffold(
      appBar: AppBar(title: const Text('文档存档')),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text('Load failed', style: TextStyle(color: isDark ? Colors.white38 : Colors.black26)),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                setState(() => _isLoading = true);
                                _loadEntries();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : displayEntries.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.folder_open, size: 48, color: isDark ? Colors.white10 : Colors.black12),
                                const SizedBox(height: 16),
                                Text('暂无该分类文档',
                                    style: TextStyle(color: isDark ? Colors.white24 : Colors.black26)),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadEntries,
                            child: ListView.builder(
                              itemCount: displayEntries.length,
                              itemBuilder: (context, index) {
                                final entry = displayEntries[index];
                                return Dismissible(
                                  key: Key(entry.title + (entry.id ?? '')),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    color: Colors.redAccent,
                                    child: const Icon(Icons.delete_forever, color: Colors.white),
                                  ),
                                  confirmDismiss: (_) async {
                                    await _deleteEntry(entry);
                                    return false;
                                  },
                                  child: ListTile(
                                    leading: Icon(_iconFor(entry.title), color: _colorFor(entry.title)),
                                    title: Row(
                                      children: [
                                        Flexible(child: Text(entry.title, overflow: TextOverflow.ellipsis)),
                                        if (!entry.isLocal) ...[
                                          const SizedBox(width: 6),
                                          Icon(Icons.cloud, size: 14, color: Colors.grey[400]),
                                        ],
                                      ],
                                    ),
                                    subtitle: Text(
                                      _formatTime(entry.modified),
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                    onTap: () => _openEntry(entry),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                                      onPressed: () => _deleteEntry(entry),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
