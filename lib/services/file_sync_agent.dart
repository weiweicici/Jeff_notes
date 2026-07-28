import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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
      final dir = await getApplicationDocumentsDirectory();
      final files = await dir.list().where((e) => e is File && e.path.endsWith('.md')).toList();

      final uploaded = await UploadCache.load();

      for (final entity in files) {
        try {
          final file = entity as File;
          final bytes = await file.readAsBytes();
          final hash = md5.convert(bytes).toString();

          if (uploaded.contains(hash)) continue;

          final module = _inferModule(file.path);
          final title = file.path.split('/').last;

          await SupabaseConfig.client.from('archives').insert({
            'file_hash': hash,
            'module': module,
            'title': title,
            'content_md': utf8.decode(bytes),
            'file_size': bytes.length,
            'user_id': SupabaseConfig.currentUserId,
          });

          await UploadCache.mark(hash);
          // ignore: avoid_print
          print('[SyncAgent] Uploaded: $title ($module)');
        } catch (e) {
          // ignore: avoid_print
          print('[SyncAgent] Error syncing ${entity.path}: $e');
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[SyncAgent] Directory error: $e');
    }
  }

  String _inferModule(String path) {
    final name = path.split('/').last.toLowerCase();
    if (name.contains('essay')) return 'essay';
    if (name.contains('discussion')) return 'discussion';
    if (name.contains('freetalk')) return 'freetalk';
    if (name.contains('reading')) return 'reading';
    if (name.contains('exam')) return 'exam';
    return 'listening';
  }
}
