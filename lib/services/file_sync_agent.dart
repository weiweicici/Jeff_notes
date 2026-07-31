import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'supabase_config.dart';
import 'upload_cache.dart';

class FileSyncAgent {
  static FileSyncAgent? _instance;
  Timer? _timer;
  bool _running = false;

  FileSyncAgent._();

  static FileSyncAgent get instance {
    _instance ??= FileSyncAgent._();
    return _instance!;
  }

  void start({Duration interval = const Duration(seconds: 30)}) {
    if (_running) return;
    _running = true;
    _syncOnce();
    _timer = Timer.periodic(interval, (_) => _syncOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> syncNow() async {
    await _syncOnce();
  }

  Future<void> _syncOnce() async {
    try {
      final userId = SupabaseConfig.currentUserIdOrNull;
      if (userId == null || userId.isEmpty) {
        debugPrint('[SyncAgent] Unauthenticated; cloud sync skipped.');
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.md'))
          .toList();

      final uploaded = await UploadCache.load();

      for (final entity in files) {
        try {
          final file = entity as File;
          final bytes = await file.readAsBytes();
          final hash = md5.convert(bytes).toString();

          if (uploaded.contains(hash)) continue;

          final module = _inferModule(file.path);
          final title = file.path.split('/').last;

          final payload = <String, dynamic>{
            'session_id': 'file_$hash',
            'user_id': userId,
            'file_hash': hash,
            'module': module,
            'title': title,
            'content_md': utf8.decode(bytes),
            'file_size': bytes.length,
          };
          await SupabaseConfig.client
              .from('archives')
              .upsert(payload, onConflict: 'user_id,session_id');

          await UploadCache.mark(hash);
          debugPrint('[SyncAgent] Uploaded: $title ($module)');
        } catch (e) {
          debugPrint('[SyncAgent] Error syncing ${entity.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('[SyncAgent] Directory error: $e');
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
}
