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
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;
  @override
  void initState() { super.initState(); _loadFiles(); }
  Future<void> _loadFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync().where((f) => f.path.endsWith('.md')).toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      if (mounted) setState(() { _files = files; _isLoading = false; });
    } catch (e) {
      debugPrint("Load History Error: $e");
      if (mounted) setState(() { _isLoading = false; });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lecture History')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
               ? const Center(child: Text('No recorded lectures found'))
               : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    return ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: Text(file.path.split('/').last),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NoteDetailScreen(file: File(file.path)))),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline), 
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Note'),
                              content: const Text('Are you sure you want to delete this note? This action cannot be undone.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true), 
                                  child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
}
