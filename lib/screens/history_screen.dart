import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'note_detail_screen.dart';
import '../services/supabase_config.dart';

class _HistoryEntry {
  final String title;
  final DateTime modified;
  final bool isLocal;
  final File? localFile;
  final String? cloudContent;

  _HistoryEntry.local({
    required this.title,
    required this.modified,
    required this.localFile,
  })  : isLocal = true,
        cloudContent = null;

  _HistoryEntry.cloud({
    required this.title,
    required this.modified,
    required this.cloudContent,
  })  : isLocal = false,
        localFile = null;
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<_HistoryEntry> _entries = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadEntries();
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
        ),
      ).toList();

      try {
        final data = await SupabaseConfig.client
            .from('archives')
            .select('id,title,content_md,created_at,module')
            .or('module.eq.listening,module.eq.freetalk,module.eq.discussion,module.eq.essay')
            .order('created_at', ascending: false);

        for (final row in List<Map<String, dynamic>>.from(data as List)) {
          final title = row['title'] as String? ?? '';
          if (localTitles.contains(title)) continue;

          final createdAt = row['created_at'] as String?;
          merged.add(
            _HistoryEntry.cloud(
              title: title,
              modified: createdAt != null
                  ? DateTime.parse(createdAt)
                  : DateTime.now(),
              cloudContent: row['content_md'] as String?,
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
    if (name.contains('Essay')) return Icons.edit_note_rounded;
    if (name.contains('Discussion')) return Icons.forum_outlined;
    if (name.contains('FreeTalk')) return Icons.chat_bubble_outline_rounded;
    if (name.contains('Reading')) return Icons.menu_book_rounded;
    return Icons.school_outlined;
  }

  Color _colorFor(String name) {
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

  Future<void> _openEntry(_HistoryEntry entry) async {
    if (entry.isLocal && entry.localFile != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NoteDetailScreen(file: entry.localFile!),
        ),
      );
    } else if (entry.cloudContent != null) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${entry.title}');
      await file.writeAsString(entry.cloudContent!);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NoteDetailScreen(file: file),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: _isLoading
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
              : _entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open, size: 48, color: isDark ? Colors.white10 : Colors.black12),
                          const SizedBox(height: 16),
                          Text('No recorded sessions found',
                              style: TextStyle(color: isDark ? Colors.white24 : Colors.black26)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadEntries,
                      child: ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          return ListTile(
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
                            trailing: entry.isLocal
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Delete Note'),
                                          content: const Text(
                                              'Are you sure you want to delete this note? This action cannot be undone.'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              child: const Text('Delete',
                                                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        await entry.localFile!.delete();
                                        _loadEntries();
                                      }
                                    },
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
    );
  }
}
