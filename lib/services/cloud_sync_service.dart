import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models.dart';
import '../models/recording_session_context.dart';
import 'supabase_config.dart';
import 'upload_cache.dart';
import 'diagnostic_log_service.dart';

/// Abstract interface for cloud archive synchronization.
abstract interface class CloudSyncService {
  Future<bool> syncArchiveSession({
    required RecordingSessionContext context,
    required File file,
  });
}

/// Production implementation of CloudSyncService using Supabase.
class SupabaseCloudSyncService implements CloudSyncService {
  const SupabaseCloudSyncService();

  @override
  Future<bool> syncArchiveSession({
    required RecordingSessionContext context,
    required File file,
  }) async {
    try {
      if (!await file.exists()) {
        debugPrint(
          '[SupabaseCloudSyncService] Sync skipped: File does not exist.',
        );
        return false;
      }

      if (!SupabaseConfig.hasValidSession) {
        final restored = await SupabaseConfig.ensureAuthenticated();
        if (!restored || !SupabaseConfig.hasValidSession) {
          unawaited(
            DiagnosticLogService.instance.record(
              'cloud',
              'sync_skipped_unauthenticated',
              sessionId: context.sessionId,
            ),
          );
          debugPrint(
            '[SupabaseCloudSyncService] Unauthenticated / Uninitialized, fail-closed skip.',
          );
          return false;
        }
      }

      final userId = SupabaseConfig.currentUserIdOrNull;
      if (userId == null || userId.isEmpty) {
        debugPrint(
          '[SupabaseCloudSyncService] Unauthenticated, fail-closed skip.',
        );
        return false;
      }

      final bytes = await file.readAsBytes();
      final hash = md5.convert(bytes).toString();
      final title = file.path.split('/').last;

      final module = context.mode == AppMode.discussion
          ? 'discussion'
          : context.mode == AppMode.exam
          ? 'exam'
          : context.mode == AppMode.freeTalk
          ? 'freetalk'
          : 'listening';

      final map = <String, dynamic>{
        'session_id': context.sessionId,
        'user_id': userId,
        'file_hash': hash,
        'module': module,
        'title': title,
        'content_md': utf8.decode(bytes, allowMalformed: true),
        'file_size': bytes.length,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final didUpload = await UploadCache.runSingleFlight(
        hash,
        userId: userId,
        sessionId: context.sessionId,
        operation: () async {
          // Upsert by composite key (user_id, session_id)
          if (!SupabaseConfig.hasValidSession ||
              SupabaseConfig.currentUserIdOrNull != userId) {
            throw StateError('Authentication identity changed during sync');
          }
          final receipt = await SupabaseConfig.client
              .from('archives')
              .upsert(map, onConflict: 'user_id,session_id')
              .select('user_id,session_id,file_hash')
              .maybeSingle();
          if (receipt == null ||
              receipt['user_id'] != map['user_id'] ||
              receipt['session_id'] != map['session_id'] ||
              receipt['file_hash'] != map['file_hash']) {
            throw StateError('remote_receipt_missing_or_mismatch');
          }
          unawaited(
            DiagnosticLogService.instance.record(
              'cloud',
              'remote_confirmed',
              sessionId: context.sessionId,
            ),
          );
          return true;
        },
      );
      if (!didUpload) return false;
      unawaited(
        DiagnosticLogService.instance.record(
          'cloud',
          'sync_completed',
          sessionId: context.sessionId,
        ),
      );
      debugPrint(
        '[SupabaseCloudSyncService] OK: ${context.sessionId} -> $title',
      );
      return true;
    } catch (e) {
      unawaited(
        DiagnosticLogService.instance.record(
          'cloud',
          'sync_failed',
          sessionId: context.sessionId,
          fields: {'errorType': e.runtimeType},
        ),
      );
      debugPrint(
        '[SupabaseCloudSyncService] Exception during sync (fail-closed): ${e.runtimeType}',
      );
      return false;
    }
  }
}

/// Fake implementation for unit testing cloud sync without real network dependencies.
class FakeCloudSyncService implements CloudSyncService {
  final List<Map<String, dynamic>> syncedRecords = [];
  bool shouldFail;

  FakeCloudSyncService({this.shouldFail = false});

  @override
  Future<bool> syncArchiveSession({
    required RecordingSessionContext context,
    required File file,
  }) async {
    if (shouldFail || !await file.exists()) return false;

    final bytes = await file.readAsBytes();
    final hash = md5.convert(bytes).toString();

    final record = <String, dynamic>{
      'session_id': context.sessionId,
      'user_id': 'fake_user_123',
      'file_hash': hash,
      'module': context.mode.name,
      'title': file.path.split('/').last,
      'file_size': bytes.length,
    };

    final didUpload = await UploadCache.runSingleFlight(
      hash,
      userId: 'fake_user_123',
      operation: () async {
        syncedRecords.add(record);
        return true;
      },
    );
    if (!didUpload) return true;
    return true;
  }
}
