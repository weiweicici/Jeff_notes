import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Durable tombstones live outside note bundles, so moving/removing a folder
/// cannot erase the protection against a delayed cloud response or re-upload.
class NoteDeletionStore {
  NoteDeletionStore(this.documents);
  final Directory documents;

  Directory get _root => Directory('${documents.path}/JeffNotes/.deletions');
  File _file(String sessionId) =>
      File('${_root.path}/${sha256.convert(utf8.encode(sessionId))}.json');

  Map<String, dynamic>? read(String sessionId) {
    final file = _file(sessionId);
    if (!file.existsSync()) return null;
    // Fail closed: damaged deletion metadata must never permit re-upload.
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  bool blocksUpload(String sessionId) => _file(sessionId).existsSync();

  bool hidesCloud(String owner, String sessionId) {
    final state = read(sessionId);
    if (state == null || state['owner'] != owner) return false;
    if (state['state'] == 'completed') return true;
    if (state['localDeleted'] == true) return true;
    return false;
  }

  void begin(String? owner, String sessionId, {bool localDeleted = false}) {
    final existing = read(sessionId);
    if (existing != null &&
        existing['owner'] != null &&
        owner != null &&
        existing['owner'] != owner) {
      throw StateError('Deletion belongs to another account');
    }
    final effectiveOwner = existing?['owner'] as String? ?? owner;
    final isAlreadyCompleted = existing?['state'] == 'completed';
    _write(sessionId, {
      'owner': effectiveOwner,
      'sessionId': sessionId,
      'state': isAlreadyCompleted
          ? 'completed'
          : (effectiveOwner != null ? 'pending' : 'completed'),
      'localDeleted': localDeleted || (existing?['localDeleted'] == true),
    });
  }

  void complete(String owner, String sessionId) {
    final existing = read(sessionId);
    if (existing == null || existing['owner'] != owner) {
      throw StateError('Deletion owner changed');
    }
    _write(sessionId, {...existing, 'state': 'completed'});
  }

  List<String> pendingSessionIdsFor(String owner) {
    if (!_root.existsSync()) return const [];
    final results = <String>[];
    for (final entity in _root.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final data =
            jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
        if (data['owner'] == owner && data['state'] == 'pending') {
          final sessionId = data['sessionId'] as String?;
          if (sessionId != null && sessionId.isNotEmpty) {
            results.add(sessionId);
          }
        }
      } catch (_) {}
    }
    return results;
  }

  void _write(String sessionId, Map<String, dynamic> value) {
    _root.createSync(recursive: true);
    final destination = _file(sessionId);
    final temporary = File('${destination.path}.tmp');
    temporary.writeAsStringSync(jsonEncode(value), flush: true);
    temporary.renameSync(destination.path);
  }
}
