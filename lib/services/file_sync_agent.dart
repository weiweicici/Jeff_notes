import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'upload_cache.dart';
import 'diagnostic_log_service.dart';

typedef ArchiveUpload =
    Future<Map<String, dynamic>?> Function(Map<String, dynamic> payload);
typedef AuthenticatedUser = Future<String?> Function();

class FileSyncAgent {
  static FileSyncAgent? _instance;
  Timer? _timer;
  StreamSubscription<AuthState>? _authSubscription;
  bool _running = false;
  bool _syncInProgress = false;
  DateTime? _lastAnonymousSignInAttempt;

  static const _anonymousSignInRetryInterval = Duration(minutes: 1);

  final AuthenticatedUser? _authenticatedUser;
  final ArchiveUpload? _archiveUpload;
  final Future<Directory> Function()? _documentsDirectory;

  FileSyncAgent._({
    AuthenticatedUser? authenticatedUser,
    ArchiveUpload? archiveUpload,
    Future<Directory> Function()? documentsDirectory,
  }) : _authenticatedUser = authenticatedUser,
       _archiveUpload = archiveUpload,
       _documentsDirectory = documentsDirectory;

  @visibleForTesting
  FileSyncAgent.forTesting({
    required AuthenticatedUser authenticatedUser,
    required ArchiveUpload archiveUpload,
    required Future<Directory> Function() documentsDirectory,
  }) : this._(
         authenticatedUser: authenticatedUser,
         archiveUpload: archiveUpload,
         documentsDirectory: documentsDirectory,
       );

  static FileSyncAgent get instance {
    _instance ??= FileSyncAgent._();
    return _instance!;
  }

  void start({Duration interval = const Duration(seconds: 30)}) {
    if (_running) return;
    _running = true;
    _syncOnce();
    _timer = Timer.periodic(interval, (_) => _syncOnce());
    try {
      _authSubscription = SupabaseConfig.client.auth.onAuthStateChange.listen(
        (_) => _syncOnce(),
      );
    } catch (_) {}
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _authSubscription?.cancel();
    _authSubscription = null;
    _running = false;
  }

  Future<void> syncNow() async {
    await _syncOnce();
  }

  Future<void> _syncOnce() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      var userId = await _currentAuthenticatedUser();
      if (userId == null || userId.isEmpty) {
        final now = DateTime.now();
        final lastAttempt = _lastAnonymousSignInAttempt;
        if (lastAttempt != null &&
            now.difference(lastAttempt) < _anonymousSignInRetryInterval) {
          return;
        }
        _lastAnonymousSignInAttempt = now;
        userId = await _restoreAuthenticatedUser();
        if (userId == null || userId.isEmpty) {
          unawaited(
            DiagnosticLogService.instance.record(
              'cloud',
              'auth_restore_blocked',
            ),
          );
          debugPrint(
            '[SyncAgent] Authentication unavailable; pending files retained.',
          );
          return;
        }
      }
      if (userId.isEmpty) {
        debugPrint('[SyncAgent] Unauthenticated; cloud sync skipped.');
        return;
      }

      final dir =
          await (_documentsDirectory?.call() ??
              getApplicationDocumentsDirectory());
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.md'))
          .toList();

      final uploaded = await UploadCache.load(userId: userId);

      for (final entity in files) {
        try {
          final file = entity as File;
          final bytes = await file.readAsBytes();
          final hash = md5.convert(bytes).toString();

          if (uploaded.contains(hash)) continue;

          final module = _inferModule(file.path);
          final title = file.path.split('/').last;
          final sessionId = _sessionIdForFile(file.path) ?? 'file_$hash';

          final payload = <String, dynamic>{
            'session_id': sessionId,
            'user_id': userId,
            'file_hash': hash,
            'module': module,
            'title': title,
            'content_md': utf8.decode(bytes),
            'file_size': bytes.length,
          };
          final didUpload = await UploadCache.runSingleFlight(
            hash,
            userId: userId,
            sessionId: sessionId,
            operation: () async {
              final currentUserId = await _currentAuthenticatedUser();
              if (currentUserId != userId) {
                throw StateError('Authentication identity changed during sync');
              }
              if (_archiveUpload != null) {
                final receipt = await _archiveUpload(payload);
                _requireMatchingReceipt(receipt, payload);
              } else {
                final receipt = await SupabaseConfig.client
                    .from('archives')
                    .upsert(payload, onConflict: 'user_id,session_id')
                    .select('user_id,session_id,file_hash')
                    .maybeSingle();
                _requireMatchingReceipt(receipt, payload);
              }
              unawaited(
                DiagnosticLogService.instance.record(
                  'cloud',
                  'remote_confirmed',
                  fields: {'title': title},
                ),
              );
              return true;
            },
          );
          if (didUpload) {
            uploaded.add(hash);
            unawaited(
              DiagnosticLogService.instance.record(
                'cloud',
                'sync_completed',
                fields: {'title': title},
              ),
            );
            debugPrint('[SyncAgent] Uploaded: $title ($module)');
          }
        } catch (e) {
          unawaited(
            DiagnosticLogService.instance.record(
              'cloud',
              'sync_failed',
              fields: {'errorType': e.runtimeType},
            ),
          );
          debugPrint(
            '[SyncAgent] Error syncing ${entity.path}: ${e.runtimeType}',
          );
        }
      }
    } catch (e) {
      debugPrint('[SyncAgent] Directory error: ${e.runtimeType}');
    } finally {
      _syncInProgress = false;
    }
  }

  Future<String?> _currentAuthenticatedUser() async {
    if (_authenticatedUser != null) return _authenticatedUser();
    if (!SupabaseConfig.hasValidSession) return null;
    return SupabaseConfig.currentUserIdOrNull;
  }

  Future<String?> _restoreAuthenticatedUser() async {
    if (_authenticatedUser != null) return _authenticatedUser();
    final restored = await SupabaseConfig.ensureAuthenticated();
    return restored ? SupabaseConfig.currentUserIdOrNull : null;
  }

  static void _requireMatchingReceipt(
    Map<String, dynamic>? receipt,
    Map<String, dynamic> payload,
  ) {
    if (receipt == null ||
        receipt['user_id'] != payload['user_id'] ||
        receipt['session_id'] != payload['session_id'] ||
        receipt['file_hash'] != payload['file_hash']) {
      throw StateError('remote_receipt_missing_or_mismatch');
    }
  }

  String _inferModule(String path) {
    final name = path.split('/').last.toLowerCase();
    if (name.contains('essay')) return 'essay';
    if (name.contains('discussion')) return 'discussion';
    if (name.contains('freetalk')) return 'freetalk';
    if (name.contains('reading')) return 'reading';
    // [BUG-11 Fix] Jeff_速记_*.md 由 Exam 模式生成，应归为 'exam'，
    // 之前因无此分支而回退到 'listening'，导致历史记录分类混乱。
    if (name.contains('速记')) return 'exam';
    if (name.contains('exam')) return 'exam';
    if (name.contains('grammar')) return 'grammar';
    return 'listening';
  }

  /// Background exports use the recording session id in these filenames.
  /// Keep that id stable when the Markdown content changes, so a later scan
  /// upserts the same archive row instead of creating a second one.
  @visibleForTesting
  static String? sessionIdForFileName(String path) => _sessionIdForFile(path);

  static String? _sessionIdForFile(String path) {
    final name = path.split('/').last;
    final match = RegExp(
      r'^Jeff_(?:Notes|Exam|FreeTalk|Discussion)_(\d{8}_\d{6}_\d+_\d+)\.md$',
      caseSensitive: false,
    ).firstMatch(name);
    return match?.group(1);
  }
}
