import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// A filesystem-backed library index.  Markdown remains the recoverable source
/// of truth; the adjacent metadata file only supplies a user-facing title and
/// an identity for files whose old name did not contain a recording session id.
class NoteLibraryItem {
  const NoteLibraryItem({
    required this.markdownFile,
    required this.stableSessionId,
    required this.displayTitle,
    required this.modifiedAt,
    required this.relativeFolderPath,
    this.audioFile,
    required this.isLegacy,
  });

  final File markdownFile;
  final File? audioFile;
  final String stableSessionId;
  final String displayTitle;
  final DateTime modifiedAt;
  final String relativeFolderPath;
  final bool isLegacy;
}

class NoteFolderItem {
  const NoteFolderItem({
    required this.name,
    required this.relativePath,
    required this.directory,
  });

  final String name;
  final String relativePath;
  final Directory directory;
}

class NoteLibraryException implements Exception {
  NoteLibraryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class NoteLibraryService {
  NoteLibraryService({Future<Directory> Function()? documentsDirectory})
    : _documentsDirectory = documentsDirectory;

  static final instance = NoteLibraryService();
  final Future<Directory> Function()? _documentsDirectory;

  static const _managedDirectoryName = 'JeffNotes';
  static const _metadataSuffix = '.jeffnotes.json';
  static const _transactionName = '.library-move.json';
  static final _invalidName = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

  Future<Directory> _documents() =>
      _documentsDirectory?.call() ?? getApplicationDocumentsDirectory();

  Future<Directory> documentsDirectory() => _documents();

  Future<void> assertCanDelete(NoteLibraryItem item) =>
      _assertNotProtected(item.markdownFile);

  /// Rechecks the whole library immediately before the synchronous commit.
  /// There is no await between identity/conflict checks and materialization.
  Future<NoteLibraryItem?> importCloudNote({
    required String sessionId,
    required String content,
    required String title,
    required bool Function() allowed,
  }) async {
    await recoverPendingTransaction();
    final documents = await _documents();
    if (!allowed()) return null;
    final root = Directory('${documents.path}/$_managedDirectoryName');
    final files = <FileSystemEntity>[
      ...documents.listSync(followLinks: false),
      if (root.existsSync())
        ...root.listSync(recursive: true, followLinks: false),
    ];
    for (final entity in files) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final sidecar = _metadataFile(entity);
      Map<String, dynamic> meta = {};
      try {
        if (sidecar.existsSync()) {
          meta = jsonDecode(sidecar.readAsStringSync()) as Map<String, dynamic>;
        }
      } catch (_) {}
      final id =
          _sessionIdFromName(_name(entity.path)) ??
          meta['stableSessionId'] ??
          'file_${sha1.convert(entity.readAsBytesSync())}';
      if (id == sessionId) {
        return _itemFor(
          entity,
          relativePath: entity.parent.path == documents.path
              ? ''
              : _relativeManaged(entity.parent.path),
        );
      }
    }
    if (!allowed()) return null;
    // A hash prevents cloud IDs from becoming paths; the sidecar preserves ID.
    final basename = 'Jeff_Cloud_${sha256.convert(utf8.encode(sessionId))}';
    final file = File('${documents.path}/$basename.md');
    if (file.existsSync() || _metadataFile(file).existsSync()) {
      throw NoteLibraryException('下载位置存在冲突，已保留原文件。');
    }
    final temporary = File('${file.path}.download.tmp');
    temporary.writeAsStringSync(content, flush: true);
    final metadata = _metadataFile(file);
    metadata.writeAsStringSync(
      jsonEncode({'stableSessionId': sessionId, 'displayTitle': title}),
      flush: true,
    );
    temporary.renameSync(file.path);
    return _itemFor(file, relativePath: '');
  }

  Future<Directory> managedRoot() async {
    final documents = await _documents();
    return Directory(_join(documents.path, _managedDirectoryName));
  }

  /// Replays an interrupted move before any scanner can observe half a bundle.
  Future<void> recoverPendingTransaction() async {
    final root = await managedRoot();
    final log = File(_join(root.path, _transactionName));
    if (!await log.exists()) return;
    try {
      final raw = jsonDecode(await log.readAsString()) as Map<String, dynamic>;
      final pairs = List<Map<String, dynamic>>.from(raw['moves'] as List);
      for (final pair in pairs) {
        final from = File(pair['from'] as String);
        final to = File(pair['to'] as String);
        await _validateTransactionPath(from.path);
        await _validateTransactionPath(to.path);
        final sourceExists = await from.exists();
        final destinationExists = await to.exists();
        if (sourceExists && !destinationExists) {
          await to.parent.create(recursive: true);
          await from.rename(to.path);
        } else if (sourceExists && destinationExists) {
          throw NoteLibraryException('检测到未完成移动的同名冲突，请保留原文件后重试。');
        } else if (!sourceExists && !destinationExists) {
          throw NoteLibraryException('检测到未完成移动且文件缺失，已停止扫描以保护数据。');
        }
      }
      await log.delete();
    } catch (error) {
      throw NoteLibraryException('正在恢复上次文件移动；请勿编辑 JeffNotes 文件夹。$error');
    }
  }

  Future<List<NoteFolderItem>> listFolders(String relativePath) async {
    await recoverPendingTransaction();
    final folder = await _folderFor(relativePath, create: false);
    if (!await folder.exists()) return const [];
    final folders = <NoteFolderItem>[];
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is Directory && !_isHidden(entity.path)) {
        folders.add(
          NoteFolderItem(
            name: _name(entity.path),
            relativePath: _relativeManaged(entity.path),
            directory: entity,
          ),
        );
      }
    }
    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return folders;
  }

  /// At root, legacy top-level notes are exposed as a virtual Inbox without
  /// relocating newly completed recordings or old user data.
  Future<List<NoteLibraryItem>> listNotes(String relativePath) async {
    await recoverPendingTransaction();
    final documents = await _documents();
    final directory = relativePath.isEmpty
        ? documents
        : await _folderFor(relativePath, create: false);
    if (!await directory.exists()) return const [];
    final notes = <NoteLibraryItem>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.md'))
        continue;
      notes.add(await _itemFor(entity, relativePath: relativePath));
    }
    return notes;
  }

  Future<List<NoteLibraryItem>> searchAllNotes(String query) async {
    await recoverPendingTransaction();
    final normalized = query.trim().toLowerCase();
    final result = <NoteLibraryItem>[];
    result.addAll(await listNotes(''));
    final root = await managedRoot();
    if (await root.exists()) {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
          result.add(
            await _itemFor(
              entity,
              relativePath: _relativeManaged(entity.parent.path),
            ),
          );
        }
      }
    }
    if (normalized.isEmpty) return result;
    return result
        .where((item) => item.displayTitle.toLowerCase().contains(normalized))
        .toList();
  }

  Future<void> createFolder(String parentRelativePath, String name) async {
    final clean = _validatedName(name);
    final parent = await _folderFor(parentRelativePath, create: true);
    final target = Directory(_join(parent.path, clean));
    if (await target.exists()) throw NoteLibraryException('该位置已有同名文件夹。');
    await target.create();
  }

  Future<void> renameFolder(String relativePath, String name) async {
    if (relativePath.isEmpty) throw NoteLibraryException('Inbox 是虚拟文件夹，不能改名。');
    final source = await _folderFor(relativePath, create: false);
    final target = Directory(_join(source.parent.path, _validatedName(name)));
    if (await target.exists()) throw NoteLibraryException('该位置已有同名文件夹。');
    await _moveDirectory(source, target);
  }

  Future<void> moveFolder(
    String relativePath,
    String targetParentRelativePath,
  ) async {
    if (relativePath.isEmpty) throw NoteLibraryException('Inbox 是虚拟文件夹，不能移动。');
    final source = await _folderFor(relativePath, create: false);
    final parent = await _folderFor(targetParentRelativePath, create: false);
    if (!_isInside(parent.path, (await managedRoot()).path) ||
        _isInside(parent.path, source.path)) {
      throw NoteLibraryException('不能将文件夹移动到自身或其子文件夹中。');
    }
    final target = Directory(_join(parent.path, _name(source.path)));
    if (await target.exists()) throw NoteLibraryException('目标位置已有同名文件夹。');
    await _moveDirectory(source, target);
  }

  Future<void> renameNoteDisplayTitle(
    NoteLibraryItem item,
    String title,
  ) async {
    final clean = _validatedName(title);
    final meta = await _readMetadata(item.markdownFile);
    meta['stableSessionId'] = item.stableSessionId;
    meta['displayTitle'] = clean;
    await _writeMetadata(item.markdownFile, meta);
  }

  Future<void> moveNote(NoteLibraryItem item, String targetRelativePath) async {
    await recoverPendingTransaction();
    await _assertNotProtected(item.markdownFile);
    final targetFolder = targetRelativePath.isEmpty
        ? await _documents()
        : await _folderFor(targetRelativePath, create: false);
    if (!await targetFolder.exists()) throw NoteLibraryException('目标文件夹不存在。');
    final targetMarkdown = File(
      _join(targetFolder.path, _name(item.markdownFile.path)),
    );
    if (await targetMarkdown.exists())
      throw NoteLibraryException('目标文件夹已有同名笔记。');
    final moves = <Map<String, String>>[
      {'from': item.markdownFile.path, 'to': targetMarkdown.path},
    ];
    if (item.audioFile != null && await item.audioFile!.exists()) {
      moves.add({
        'from': item.audioFile!.path,
        'to': _join(targetFolder.path, _name(item.audioFile!.path)),
      });
    }
    final meta = _metadataFile(item.markdownFile);
    if (await meta.exists()) {
      moves.add({'from': meta.path, 'to': _metadataFile(targetMarkdown).path});
    }
    await _moveFilesWithJournal(moves);
  }

  Future<void> deleteEmptyFolder(String relativePath) async {
    if (relativePath.isEmpty) throw NoteLibraryException('Inbox 是虚拟文件夹，不能删除。');
    final folder = await _folderFor(relativePath, create: false);
    if ((await folder.list(followLinks: false).toList()).isNotEmpty) {
      throw NoteLibraryException('文件夹不为空，请先确认递归删除。');
    }
    await folder.delete();
  }

  Future<({int notes, int folders})> descendantsCount(
    String relativePath,
  ) async {
    final folder = await _folderFor(relativePath, create: false);
    var notes = 0;
    var folders = 0;
    await for (final entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.toLowerCase().endsWith('.md')) notes++;
      if (entity is Directory) folders++;
    }
    return (notes: notes, folders: folders);
  }

  Future<void> deleteFolderRecursively(
    String relativePath, {
    bool Function()? allowed,
  }) async {
    final folder = await _folderFor(relativePath, create: false);
    await for (final entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
        await _assertNotProtected(entity);
      }
    }
    if (allowed != null && !allowed())
      throw NoteLibraryException('账号已改变，删除未完成。');
    folder.deleteSync(recursive: true);
  }

  Future<void> deleteNoteFiles(
    NoteLibraryItem item, {
    bool Function()? allowed,
  }) async {
    await _assertNotProtected(item.markdownFile);
    if (allowed != null && !allowed())
      throw NoteLibraryException('账号已改变，删除未完成。');
    if (item.markdownFile.existsSync()) item.markdownFile.deleteSync();
    final wavPath = item.markdownFile.path.replaceFirst(
      RegExp(r'\.md$', caseSensitive: false),
      '.wav',
    );
    final wavFile = item.audioFile ?? File(wavPath);
    if (wavFile.existsSync()) wavFile.deleteSync();
    final sidecar = _metadataFile(item.markdownFile);
    if (sidecar.existsSync()) sidecar.deleteSync();
  }

  Future<String> stableSessionIdFor(File file) async =>
      (await _itemFor(file, relativePath: '')).stableSessionId;
  Future<String> displayTitleFor(File file) async =>
      (await _itemFor(file, relativePath: '')).displayTitle;

  Future<NoteLibraryItem> _itemFor(
    File file, {
    required String relativePath,
  }) async {
    final meta = await _readMetadata(file);
    final filenameId = _sessionIdFromName(_name(file.path));
    final bytes = await file.readAsBytes();
    final stableId =
        filenameId ??
        meta['stableSessionId'] as String? ??
        'file_${sha1.convert(bytes)}';
    final display = (meta['displayTitle'] as String?)?.trim();
    final wav = File(
      file.path.replaceFirst(RegExp(r'\.md$', caseSensitive: false), '.wav'),
    );
    return NoteLibraryItem(
      markdownFile: file,
      audioFile: await wav.exists() ? wav : null,
      stableSessionId: stableId,
      displayTitle: display == null || display.isEmpty
          ? _name(file.path)
          : display,
      modifiedAt: (await file.stat()).modified,
      relativeFolderPath: relativePath,
      isLegacy: relativePath.isEmpty,
    );
  }

  Future<void> _moveDirectory(Directory source, Directory target) async {
    await recoverPendingTransaction();
    if (!await source.exists()) throw NoteLibraryException('文件夹不存在。');
    await _assertDirectorySafe(source);
    await target.parent.create(recursive: true);
    await source.rename(target.path);
  }

  Future<void> _moveFilesWithJournal(List<Map<String, String>> moves) async {
    final root = await managedRoot();
    await root.create(recursive: true);
    for (final move in moves) {
      await _validateTransactionPath(move['from']!);
      await _validateTransactionPath(move['to']!);
    }
    final log = File(_join(root.path, _transactionName));
    await _atomicJson(log, {'version': 1, 'moves': moves});
    try {
      for (final move in moves) {
        final from = File(move['from']!);
        final to = File(move['to']!);
        if (!await from.exists()) continue;
        await to.parent.create(recursive: true);
        await from.rename(to.path);
      }
      await log.delete();
    } catch (_) {
      // Keep the journal: next startup deterministically completes the bundle.
      rethrow;
    }
  }

  Future<Directory> _folderFor(
    String relativePath, {
    required bool create,
  }) async {
    final root = await managedRoot();
    final clean = _cleanRelativePath(relativePath);
    final folder = clean.isEmpty ? root : Directory(_join(root.path, clean));
    if (create) await folder.create(recursive: true);
    return folder;
  }

  String _cleanRelativePath(String value) {
    final normalized = value
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+|/+$'), '');
    if (normalized.isEmpty) return '';
    final parts = normalized.split('/');
    if (parts.any(
      (p) => p.isEmpty || p == '.' || p == '..' || _invalidName.hasMatch(p),
    )) {
      throw NoteLibraryException('文件夹路径无效。');
    }
    return parts.join('/');
  }

  String _validatedName(String value) {
    final clean = value.trim();
    if (clean.isEmpty ||
        clean == '.' ||
        clean == '..' ||
        _invalidName.hasMatch(clean)) {
      throw NoteLibraryException('名称不能为空且不能包含文件系统保留字符。');
    }
    return clean;
  }

  Future<Map<String, dynamic>> _readMetadata(File note) async {
    final meta = _metadataFile(note);
    try {
      if (!await meta.exists()) return <String, dynamic>{};
      final value = jsonDecode(await meta.readAsString());
      return value is Map<String, dynamic>
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
    } catch (_) {
      // A damaged sidecar must never hide the Markdown file.
      return <String, dynamic>{};
    }
  }

  Future<void> _writeMetadata(File note, Map<String, dynamic> value) =>
      _atomicJson(_metadataFile(note), value);

  Future<void> _atomicJson(File file, Map<String, dynamic> value) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    await temp.rename(file.path);
  }

  File _metadataFile(File note) => File('${note.path}$_metadataSuffix');

  Future<void> _assertNotProtected(File note) async {
    final documents = await _documents();
    await for (final entity in documents.list(followLinks: false)) {
      if (entity is! File ||
          !_name(entity.path).startsWith('shadow_draft_') ||
          !entity.path.endsWith('.json'))
        continue;
      try {
        final draft =
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        final protected = <String>{draft['exportPath'] as String? ?? ''};
        protected.addAll(
          (draft['pendingAudioNotes'] as Map?)?.keys.whereType<String>() ??
              const <String>[],
        );
        if (protected.contains(note.path)) {
          throw NoteLibraryException('此笔记仍在处理或等待恢复，完成后才能移动或删除。');
        }
      } catch (error) {
        if (error is NoteLibraryException) rethrow;
      }
    }
  }

  Future<void> _assertDirectorySafe(Directory directory) async {
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw NoteLibraryException('文件夹含有符号链接，不能安全移动。');
      }
    }
  }

  Future<void> _validateTransactionPath(String path) async {
    final documents = await _documents();
    if (!_isInside(path, documents.path) ||
        await FileSystemEntity.type(path, followLinks: false) ==
            FileSystemEntityType.link) {
      throw NoteLibraryException('移动路径不安全。');
    }
  }

  bool _isInside(String candidate, String parent) =>
      candidate == parent ||
      candidate.startsWith(
        '${parent.endsWith('/') ? parent.substring(0, parent.length - 1) : parent}/',
      );
  bool _isHidden(String path) => _name(path).startsWith('.');
  String _relativeManaged(String path) {
    // Caller only supplies paths under the managed root.
    return path.split('/$_managedDirectoryName/').last;
  }

  String _join(String left, String right) =>
      left.endsWith('/') ? '$left$right' : '$left/$right';
  String _name(String path) => path.split('/').last;

  static String? sessionIdFromFileName(String path) =>
      _sessionIdFromName(path.split('/').last);
  static String? _sessionIdFromName(String name) => RegExp(
    r'^Jeff_(?:Notes|Exam|FreeTalk|Discussion)_(\d{8}_\d{6}_\d+_\d+)\.md$',
    caseSensitive: false,
  ).firstMatch(name)?.group(1);
}
