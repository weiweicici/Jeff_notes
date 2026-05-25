import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'note_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<File> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final entities = await directory
          .list()
          .where((f) => f.path.endsWith('.md'))
          .toList();

      // ✅ 修复：按文件最后修改时间降序排列，最新的永远在最上面
      final files = entities.whereType<File>().toList();
      files.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });

      if (mounted) {
        setState(() {
          _files = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Load History Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('No recorded sessions found'))
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final name = file.path.split('/').last;
                    final isDiscussion = name.contains('Discussion');

                    // 根据文件类型显示不同图标和颜色
                    final icon = isDiscussion
                        ? Icons.forum_outlined
                        : Icons.school_outlined;
                    final iconColor = isDiscussion
                        ? Colors.deepPurpleAccent
                        : Colors.blueAccent;

                    return ListTile(
                      leading: Icon(icon, color: iconColor),
                      title: Text(name),
                      subtitle: Text(
                        _formatModifiedTime(file.statSync().modified),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NoteDetailScreen(file: file),
                        ),
                      ),
                      trailing: IconButton(
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
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Delete',
                                      style: TextStyle(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await file.delete();
                            _loadFiles();
                          }
                        },
                      ),
                    );
                  },
                ),
    );
  }

  String _formatModifiedTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }
}
