import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cloud_identity_guard.dart';
import '../services/note_library_service.dart';
import '../services/note_deletion_store.dart';
import '../services/supabase_config.dart';
import '../services/upload_cache.dart';
import 'note_detail_screen.dart';

enum _LibrarySort { newest, oldest, name }

class HistoryCloudNote {
  const HistoryCloudNote({
    required this.ownerId,
    required this.id,
    required this.sessionId,
    required this.title,
    required this.content,
    required this.modifiedAt,
  });
  final String ownerId;
  final String? id;
  final String? sessionId;
  final String title;
  final String? content;
  final DateTime modifiedAt;
}

abstract class HistoryCloudRepository {
  Future<List<HistoryCloudNote>> list(String ownerId);
  Future<void> delete(HistoryCloudNote note);
}

class SupabaseHistoryCloudRepository implements HistoryCloudRepository {
  @override
  Future<List<HistoryCloudNote>> list(String ownerId) async {
    final data = await SupabaseConfig.client
        .from('archives')
        .select('id,session_id,title,content_md,created_at')
        .eq('user_id', ownerId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List)
        .map(
          (row) => HistoryCloudNote(
            ownerId: ownerId,
            id: row['id']?.toString(),
            sessionId: row['session_id']?.toString(),
            title: row['title'] as String? ?? '未命名笔记',
            content: row['content_md'] as String?,
            modifiedAt:
                DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
          ),
        )
        .toList();
  }

  @override
  Future<void> delete(HistoryCloudNote note) async {
    final q = SupabaseConfig.client
        .from('archives')
        .delete()
        .eq('user_id', note.ownerId);
    if (note.id != null)
      await q.eq('id', note.id!);
    else if (note.sessionId != null)
      await q.eq('session_id', note.sessionId!);
    else
      throw StateError('Cloud note has no deletion identity');
  }
}

/// Local-first folder browser. Sync stays in FileSyncAgent and is never needed
/// to open, name, or organize a note.
class HistoryScreen extends StatefulWidget {
  final String? initialModuleFilter;
  final HistoryCloudRepository? cloudRepository;
  final String? Function()? captureIdentity;
  final bool Function(String)? isCurrentIdentity;
  final NoteLibraryService? library;
  final Future<void> Function(NoteLibraryItem)? openNote;
  const HistoryScreen({
    super.key,
    this.initialModuleFilter,
    this.cloudRepository,
    this.captureIdentity,
    this.isCurrentIdentity,
    this.library,
    this.openNote,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final NoteLibraryService _library;
  NoteDeletionStore? _deletions;
  final _search = TextEditingController();
  List<NoteFolderItem> _folders = const [];
  List<NoteLibraryItem> _notes = const [];
  List<HistoryCloudNote> _cloudNotes = const [];
  late final HistoryCloudRepository _cloudRepository;
  int _loadGeneration = 0;
  StreamSubscription<AuthState>? _authChanges;
  late final String? Function() _captureIdentity;
  late final bool Function(String) _isCurrentIdentity;
  String _currentFolder = '';
  String _query = '';
  _LibrarySort _sort = _LibrarySort.newest;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _library = widget.library ?? NoteLibraryService.instance;
    _cloudRepository =
        widget.cloudRepository ?? SupabaseHistoryCloudRepository();
    _captureIdentity = widget.captureIdentity ?? CloudIdentityGuard.capture;
    _isCurrentIdentity =
        widget.isCurrentIdentity ?? CloudIdentityGuard.stillCurrent;
    try {
      _authChanges = SupabaseConfig.client.auth.onAuthStateChange.listen((_) {
        _loadGeneration++;
        if (mounted) setState(() => _cloudNotes = const []);
        _load();
      });
    } catch (_) {}
    _restoreAndLoad();
  }

  @override
  void dispose() {
    _authChanges?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _restoreAndLoad() async {
    final stored = (await SharedPreferences.getInstance()).getString(
      'note_library_sort',
    );
    for (final sort in _LibrarySort.values) {
      if (sort.name == stored) _sort = sort;
    }
    await _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final owner = _captureIdentity();
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      _deletions ??= NoteDeletionStore(await _library.documentsDirectory());
      if (owner != null && _isCurrentIdentity(owner)) {
        await _flushPendingCloudDeletions(owner);
      }
      final notes = _query.trim().isEmpty
          ? await _library.listNotes(_currentFolder)
          : await _library.searchAllNotes(_query);
      final folders = _query.trim().isEmpty
          ? await _library.listFolders(_currentFolder)
          : const <NoteFolderItem>[];
      final cloud = await _loadCloudNotes(owner);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _folders = folders;
        _notes = notes..sort(_compare);
        _cloudNotes = owner != null && _isCurrentIdentity(owner)
            ? cloud
            : const [];
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration)
        setState(() {
          _loading = false;
          _error = error.toString();
        });
    }
  }

  Future<List<HistoryCloudNote>> _loadCloudNotes(String? userId) async {
    if (userId == null || !_isCurrentIdentity(userId)) return const [];
    try {
      final allLocal = await _library.searchAllNotes('');
      final localIds = allLocal.map((item) => item.stableSessionId).toSet();
      if (!_isCurrentIdentity(userId)) return const [];
      final data = await _cloudRepository.list(userId);
      if (!_isCurrentIdentity(userId)) return const [];
      return data
          .where(
            (note) =>
                note.ownerId == userId &&
                !(_deletions?.hidesCloud(userId, _cloudId(note)) ?? false),
          )
          .where((note) => !localIds.contains(_cloudId(note)))
          .where(
            (note) =>
                _query.trim().isEmpty ||
                note.title.toLowerCase().contains(_query.toLowerCase()),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  int _compare(NoteLibraryItem a, NoteLibraryItem b) {
    switch (_sort) {
      case _LibrarySort.newest:
        return b.modifiedAt.compareTo(a.modifiedAt);
      case _LibrarySort.oldest:
        return a.modifiedAt.compareTo(b.modifiedAt);
      case _LibrarySort.name:
        return a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        );
    }
  }

  Future<void> _setSort(_LibrarySort value) async {
    await (await SharedPreferences.getInstance()).setString(
      'note_library_sort',
      value.name,
    );
    setState(() {
      _sort = value;
      _notes = List.of(_notes)..sort(_compare);
    });
  }

  Future<String?> _askName(String title, [String initial = '']) async {
    var edited = initial;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          onChanged: (value) => edited = value,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(hintText: '输入名称'),
          onFieldSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, edited),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return value;
  }

  Future<void> _run(Future<void> Function() work) async {
    try {
      await work();
      await _load();
    } on NoteLibraryException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('操作未完整完成。请检查列表；删除未完成的笔记已暂停上传，可恢复原账号连接后重试。'),
          ),
        );
      await _load();
    }
  }

  Future<void> _newFolder() async {
    final name = await _askName('新建文件夹');
    if (name != null)
      await _run(() => _library.createFolder(_currentFolder, name));
  }

  Future<void> _open(NoteLibraryItem item) async {
    if (widget.openNote != null) {
      await widget.openNote!(item);
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(file: item.markdownFile),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openCloud(HistoryCloudNote note) async {
    if (note.content == null || note.content!.isEmpty) return;
    final owner = _captureIdentity();
    bool allowed() =>
        mounted &&
        owner == note.ownerId &&
        _isCurrentIdentity(note.ownerId) &&
        !(_deletions?.blocksUpload(_cloudId(note)) ?? false);
    if (!allowed()) return;
    try {
      final local = await _library.importCloudNote(
        sessionId: _cloudId(note),
        content: note.content!,
        title: note.title,
        allowed: allowed,
      );
      if (local != null && allowed()) await _open(local);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('下载未完成，已保留已有笔记。')));
    }
  }

  String _cloudId(HistoryCloudNote note) =>
      note.sessionId ??
      'cloud_${note.id ?? md5.convert(utf8.encode(note.content ?? note.title))}';

  Future<void> _deleteCloud(HistoryCloudNote note) async {
    final owner = _captureIdentity();
    if (!await _confirm('删除笔记', '确定删除“${note.title}”吗？将删除云端记录。')) return;
    if (owner != note.ownerId || !_isCurrentIdentity(note.ownerId)) return;
    try {
      _deletions!.begin(owner, _cloudId(note));
      await _deleteRemote(note);
      await _load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('云端删除失败，未移除列表。')));
      await _load();
    }
  }

  Future<void> _deleteRemote(HistoryCloudNote note) async {
    final owner = note.ownerId;
    if (!_isCurrentIdentity(owner)) throw StateError('Identity changed');
    await UploadCache.runSingleFlight(
      'delete:${_cloudId(note)}:${DateTime.now().microsecondsSinceEpoch}',
      userId: owner,
      sessionId: _cloudId(note),
      operation: () async {
        if (!_isCurrentIdentity(owner)) throw StateError('Identity changed');
        await _cloudRepository.delete(note);
        if (!_isCurrentIdentity(owner)) throw StateError('Identity changed');
        _deletions!.complete(owner, _cloudId(note));
        return false;
      },
    );
    if (!_isCurrentIdentity(owner)) throw StateError('Identity changed');
  }

  Future<void> _flushPendingCloudDeletions(String owner) async {
    if (!_isCurrentIdentity(owner) || _deletions == null) return;
    final pending = _deletions!.pendingSessionIdsFor(owner);
    for (final sessionId in pending) {
      if (!_isCurrentIdentity(owner)) return;
      try {
        await _deleteRemote(
          HistoryCloudNote(
            ownerId: owner,
            id: null,
            sessionId: sessionId,
            title: '',
            content: null,
            modifiedAt: DateTime.now(),
          ),
        );
      } catch (_) {
        // Cloud cleanup remains pending
      }
    }
  }

  Future<void> _deleteLocalNotes(
    List<NoteLibraryItem> items,
    String? owner,
  ) async {
    for (final item in items) {
      await _library.assertCanDelete(item);
      if (_captureIdentity() != owner ||
          (owner != null && !_isCurrentIdentity(owner))) {
        throw StateError('Identity changed');
      }
    }
    for (final item in items) {
      _deletions!.begin(owner, item.stableSessionId, localDeleted: true);
    }
    for (final item in items) {
      if (owner != null && !_isCurrentIdentity(owner)) {
        throw StateError('Identity changed');
      }
      await _library.deleteNoteFiles(
        item,
        allowed: owner != null ? () => _isCurrentIdentity(owner) : null,
      );
    }
    if (owner != null && _isCurrentIdentity(owner)) {
      for (final item in items) {
        try {
          await _deleteRemote(
            HistoryCloudNote(
              ownerId: owner,
              id: null,
              sessionId: item.stableSessionId,
              title: item.displayTitle,
              content: null,
              modifiedAt: item.modifiedAt,
            ),
          );
        } catch (_) {
          // Cloud cleanup remains pending in NoteDeletionStore;
          // local deletion is already complete.
        }
      }
    }
  }

  Future<void> _cloudMenu(HistoryCloudNote note) async {
    final action = await _menu(['打开', '删除']);
    if (action == '打开') await _openCloud(note);
    if (action == '删除') await _deleteCloud(note);
  }

  Future<List<NoteFolderItem>> _allFolders([String path = '']) async {
    final direct = await _library.listFolders(path);
    final result = <NoteFolderItem>[...direct];
    for (final folder in direct) {
      result.addAll(await _allFolders(folder.relativePath));
    }
    return result;
  }

  Future<String?> _pickFolder(String title, {String? exclude}) async {
    final folders = await _allFolders();
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(title), enabled: false),
            if (exclude != '')
              ListTile(
                leading: const Icon(Icons.inbox_outlined),
                title: const Text('Inbox（虚拟）'),
                onTap: () => Navigator.pop(context, ''),
              ),
            for (final folder in folders)
              if (folder.relativePath != exclude)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.relativePath),
                  onTap: () => Navigator.pop(context, folder.relativePath),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _noteMenu(NoteLibraryItem item) async {
    final action = await _menu(['打开', '重命名', '移动', '删除']);
    if (action == '打开') await _open(item);
    if (action == '重命名') {
      final title = await _askName('重命名笔记', item.displayTitle);
      if (title != null)
        await _run(() => _library.renameNoteDisplayTitle(item, title));
    }
    if (action == '移动') {
      final target = await _pickFolder('移动笔记到');
      if (target != null) await _run(() => _library.moveNote(item, target));
    }
    if (action == '删除') await _confirmDeleteNote(item);
  }

  Future<void> _confirmDeleteNote(NoteLibraryItem item) async {
    final owner = _captureIdentity();
    final confirmed = await _confirm(
      '删除笔记',
      '确定删除“${item.displayTitle}”吗？将立即删除本地笔记及音频；若已同步云端，将在联网登录后清理云端副本。',
    );
    if (confirmed)
      await _run(() async {
        await _deleteLocalNotes([item], owner);
      });
  }

  Future<void> _folderMenu(NoteFolderItem folder) async {
    final action = await _menu(['重命名', '移动', '删除']);
    if (action == '重命名') {
      final name = await _askName('重命名文件夹', folder.name);
      if (name != null)
        await _run(() => _library.renameFolder(folder.relativePath, name));
    }
    if (action == '移动') {
      final target = await _pickFolder('移动文件夹到', exclude: folder.relativePath);
      if (target != null)
        await _run(() => _library.moveFolder(folder.relativePath, target));
    }
    if (action == '删除') {
      final owner = _captureIdentity();
      final count = await _library.descendantsCount(folder.relativePath);
      if (!mounted) return;
      final message = count.notes == 0 && count.folders == 0
          ? '确定删除空文件夹“${folder.name}”吗？'
          : '此文件夹包含 ${count.notes} 篇笔记和 ${count.folders} 个子文件夹。确定递归删除吗？';
      if (await _confirm('删除文件夹', message))
        await _run(() async {
          final descendants = (await _library.searchAllNotes(''))
              .where(
                (item) =>
                    item.relativeFolderPath == folder.relativePath ||
                    item.relativeFolderPath.startsWith(
                      '${folder.relativePath}/',
                    ),
              )
              .toList();
          if (descendants.isNotEmpty)
            await _deleteLocalNotes(descendants, owner);
          if (_captureIdentity() != owner) throw StateError('Identity changed');
          await _library.deleteFolderRecursively(
            folder.relativePath,
            allowed: () => _captureIdentity() == owner,
          );
        });
    }
  }

  Future<String?> _menu(List<String> choices) => showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          for (final choice in choices)
            ListTile(
              leading: Icon(
                choice == '删除'
                    ? Icons.delete_outline
                    : choice == '移动'
                    ? Icons.drive_file_move_outline
                    : choice == '重命名'
                    ? Icons.drive_file_rename_outline
                    : Icons.open_in_new,
                color: choice == '删除' ? Colors.red : null,
              ),
              title: Text(
                choice,
                style: TextStyle(color: choice == '删除' ? Colors.red : null),
              ),
              onTap: () => Navigator.pop(context, choice),
            ),
        ],
      ),
    ),
  );

  Future<bool> _confirm(String title, String message) async =>
      (await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      )) ??
      false;

  void _back() {
    setState(() {
      final parts = _currentFolder.split('/');
      parts.removeLast();
      _currentFolder = parts.join('/');
    });
    _load();
  }

  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _currentFolder.isEmpty ? 'Jeff Notes' : 'Jeff Notes › $_currentFolder',
      ),
      leading: _currentFolder.isEmpty
          ? null
          : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
      actions: [
        PopupMenuButton<_LibrarySort>(
          icon: const Icon(Icons.sort),
          onSelected: _setSort,
          itemBuilder: (_) => const [
            PopupMenuItem(value: _LibrarySort.newest, child: Text('最新')),
            PopupMenuItem(value: _LibrarySort.oldest, child: Text('最早')),
            PopupMenuItem(value: _LibrarySort.name, child: Text('名称')),
          ],
        ),
        IconButton(
          onPressed: _newFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: (v) {
              _query = v;
              _load();
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '搜索所有笔记',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _query = '';
                        _load();
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      if (_currentFolder.isEmpty && _query.isEmpty)
                        const ListTile(
                          leading: Icon(Icons.inbox_outlined),
                          title: Text('Inbox'),
                          subtitle: Text('新完成和旧版顶层笔记（虚拟，不移动文件）'),
                        ),
                      for (final folder in _folders)
                        ListTile(
                          leading: const Icon(
                            Icons.folder_outlined,
                            color: Colors.amber,
                          ),
                          title: Text(folder.name),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _folderMenu(folder),
                          ),
                          onTap: () {
                            setState(
                              () => _currentFolder = folder.relativePath,
                            );
                            _load();
                          },
                        ),
                      if (_folders.isNotEmpty) const Divider(),
                      if (_notes.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            '笔记',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      for (final note in _notes)
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(
                            note.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${_date(note.modifiedAt)}${_deletions?.blocksUpload(note.stableSessionId) == true ? ' · 删除未完成，请重试' : ''}${note.audioFile == null ? '' : ' · 有录音'}${_query.isNotEmpty && note.relativeFolderPath.isNotEmpty ? ' · ${note.relativeFolderPath}' : ''}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _noteMenu(note),
                          ),
                          onTap: () => _open(note),
                        ),
                      if (_cloudNotes.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            '云端笔记',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      for (final note in _cloudNotes)
                        ListTile(
                          leading: const Icon(Icons.cloud_outlined),
                          title: Text(
                            note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${_date(note.modifiedAt)} · ${_deletions?.blocksUpload(_cloudId(note)) == true ? '删除未完成，请重试' : '下载后可整理'}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _cloudMenu(note),
                          ),
                          onTap: () => _openCloud(note),
                        ),
                      if (_folders.isEmpty &&
                          _notes.isEmpty &&
                          _cloudNotes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 96),
                          child: Center(child: Text('暂无笔记或文件夹')),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}
