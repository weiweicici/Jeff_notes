import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../models/recording_session_context.dart';

class ShadowDraftService {
  ShadowDraftService._();
  static final ShadowDraftService instance = ShadowDraftService._();

  static const int currentSchemaVersion = 1;
  final Map<String, Future<void>> _writeQueues = {};

  /// Saves current session state as a JSON shadow draft file atomically.
  /// Uses a temporary file (.tmp) with flush: true and renames upon completion
  /// to protect pre-existing drafts against corruption or partial writes.
  Future<bool> saveDraft(RecordingSessionContext context) {
    final targetPath = context.shadowDraftPath;
    final data = _snapshot(context);
    final previous = _writeQueues[targetPath] ?? Future<void>.value();
    final operation = previous.then((_) => _saveSnapshot(targetPath, data));
    late final Future<void> queueTail;
    queueTail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    _writeQueues[targetPath] = queueTail;

    return operation.whenComplete(() {
      if (identical(_writeQueues[targetPath], queueTail)) {
        _writeQueues.remove(targetPath);
      }
    });
  }

  Map<String, dynamic> _snapshot(RecordingSessionContext context) => {
    'schemaVersion': currentSchemaVersion,
    'sessionId': context.sessionId,
    'mode': context.mode.index,
    'unit': context.unit.index,
    'createdAt': context.createdAt.toIso8601String(),
    'exportPath': context.exportPath,
    'notes': context.notes.map((note) => note.toJson()).toList(),
    'segmentSummaries': List<String>.of(context.segmentSummaries),
    'rawAudioPaths': List<String>.of(context.rawAudioPaths),
    'stitchedAudioPaths': List<String>.of(context.stitchedAudioPaths),
    'pendingAudioNotes': Map<String, String?>.of(context.pendingAudioNotes),
    'finalReviewContent': context.finalReviewContent,
    'shorthandReviewContent': context.shorthandReviewContent,
    'identifiedLectureContext': context.identifiedLectureContext,
    'isCompleted': context.isCompleted,
  };

  Future<bool> _saveSnapshot(
    String targetPath,
    Map<String, dynamic> data,
  ) async {
    final tempPath = '$targetPath.tmp';

    try {
      final tempFile = File(tempPath);
      final jsonStr = jsonEncode(data);
      await tempFile.writeAsString(jsonStr, flush: true);

      // Atomic rename
      await tempFile.rename(targetPath);
      debugPrint(
        '[ShadowDraftService] Atomically saved shadow draft: $targetPath',
      );
      return true;
    } catch (e) {
      debugPrint(
        '[ShadowDraftService] Error saving draft atomically to $targetPath: $e',
      );
      // Clean up temp file if left over
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
      return false;
    }
  }

  /// Validates the structure and schema of a parsed draft map.
  bool validateDraft(Map<String, dynamic> data) {
    try {
      final schemaVer = data['schemaVersion'] as int?;
      if (schemaVer != currentSchemaVersion) return false;

      final sessionId = data['sessionId'] as String?;
      if (sessionId == null || sessionId.trim().isEmpty) {
        return false;
      }

      final modeIdx = data['mode'] as int?;
      if (modeIdx == null || modeIdx < 0 || modeIdx >= AppMode.values.length)
        return false;

      final unitIdx = data['unit'] as int?;
      if (unitIdx == null ||
          unitIdx < 0 ||
          unitIdx >= PathwaysUnit.values.length)
        return false;

      final exportPath = data['exportPath'] as String?;
      if (exportPath == null || exportPath.trim().isEmpty) {
        return false;
      }

      final createdAt = data['createdAt'];
      if (createdAt is! String || DateTime.tryParse(createdAt) == null) {
        return false;
      }

      final notesList = data['notes'] as List?;
      if (notesList == null || !notesList.every(_isValidNote)) return false;

      if (!_isStringList(data['segmentSummaries']) ||
          !_isStringList(data['rawAudioPaths']) ||
          !_isStringList(data['stitchedAudioPaths'])) {
        return false;
      }

      final pendingAudioNotes = data['pendingAudioNotes'];
      if (pendingAudioNotes != null &&
          (pendingAudioNotes is! Map ||
              pendingAudioNotes.entries.any(
                (entry) =>
                    entry.key is! String ||
                    (entry.value != null && entry.value is! String),
              ))) {
        return false;
      }

      if (!_isNullableString(data['finalReviewContent']) ||
          !_isNullableString(data['shorthandReviewContent']) ||
          !_isNullableString(data['identifiedLectureContext']) ||
          data['isCompleted'] is! bool) {
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[ShadowDraftService] Draft validation exception: $e');
      return false;
    }
  }

  bool _isValidNote(Object? value) {
    if (value is! Map<String, dynamic>) return false;
    final timestamp = value['timestamp'];
    return value['id'] is String &&
        (value['id'] as String).isNotEmpty &&
        value['summary'] is String &&
        value['transcript'] is String &&
        _isNullableString(value['translatedContent']) &&
        timestamp is String &&
        DateTime.tryParse(timestamp) != null &&
        _isNullableString(value['clusterId']) &&
        value['isSummary'] is bool;
  }

  bool _isStringList(Object? value) =>
      value is List && value.every((item) => item is String);

  bool _isNullableString(Object? value) => value == null || value is String;

  /// Deletes shadow draft file after successful final review and export.
  Future<bool> deleteDraft(String draftPath) async {
    await waitForPendingWrites(draftPath);
    try {
      final file = File(draftPath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[ShadowDraftService] Deleted shadow draft: $draftPath');
      }
      return true;
    } catch (e) {
      debugPrint('[ShadowDraftService] Error deleting draft $draftPath: $e');
      return false;
    }
  }

  Future<void> waitForPendingWrites(String draftPath) async {
    await (_writeQueues[draftPath] ?? Future<void>.value());
  }

  /// Checks if a valid shadow draft file exists.
  Future<bool> hasDraft(String draftPath) async {
    try {
      final file = File(draftPath);
      if (!await file.exists()) return false;
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return false;
      return validateDraft(decoded);
    } catch (_) {
      return false;
    }
  }

  /// Reads and validates a shadow draft file.
  Future<RecordingSessionContext?> readDraft(String draftPath) async {
    try {
      final file = File(draftPath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final data = jsonDecode(content);
      if (data is! Map<String, dynamic> || !validateDraft(data)) {
        debugPrint(
          '[ShadowDraftService] Rejected invalid or corrupted draft: $draftPath',
        );
        return null;
      }

      final mode = AppMode.values[data['mode'] as int];
      final unit = PathwaysUnit.values[data['unit'] as int];
      final sessionId = data['sessionId'] as String;
      final exportPath = data['exportPath'] as String;
      final createdAt = DateTime.parse(data['createdAt'] as String);

      final context = RecordingSessionContext(
        sessionId: sessionId,
        mode: mode,
        unit: unit,
        exportPath: exportPath,
        shadowDraftPath: draftPath,
        createdAt: createdAt,
      );

      final rawNotes = data['notes'] as List;
      for (final item in rawNotes) {
        context.addNote(InsightNote.fromJson(item as Map<String, dynamic>));
      }

      if (data['segmentSummaries'] != null) {
        context.segmentSummaries.addAll(
          (data['segmentSummaries'] as List).cast<String>(),
        );
      }
      if (data['rawAudioPaths'] != null) {
        context.rawAudioPaths.addAll(
          (data['rawAudioPaths'] as List).cast<String>(),
        );
      }
      if (data['stitchedAudioPaths'] != null) {
        context.stitchedAudioPaths.addAll(
          (data['stitchedAudioPaths'] as List).cast<String>(),
        );
      }
      final pendingAudioNotes = data['pendingAudioNotes'];
      if (pendingAudioNotes is Map) {
        for (final entry in pendingAudioNotes.entries) {
          context.pendingAudioNotes[entry.key.toString()] = entry.value
              ?.toString();
        }
      }

      context.finalReviewContent = data['finalReviewContent'] as String?;
      context.shorthandReviewContent =
          data['shorthandReviewContent'] as String?;
      context.identifiedLectureContext =
          data['identifiedLectureContext'] as String?;
      context.isCompleted = data['isCompleted'] as bool? ?? false;

      return context;
    } catch (e) {
      debugPrint('[ShadowDraftService] Error reading draft $draftPath: $e');
      return null;
    }
  }
}
