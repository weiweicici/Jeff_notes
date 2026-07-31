import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A small, privacy-conscious diagnostic log intended for manual device tests.
///
/// Never pass note/transcript content, credentials, cookies, or response bodies
/// to [record]. The service also redacts common credential patterns as a final
/// safeguard.
class DiagnosticLogService {
  DiagnosticLogService._();

  static final DiagnosticLogService instance = DiagnosticLogService._();

  static const int _maxBytes = 512 * 1024;
  static const int _retainedBytes = 256 * 1024;

  File? _file;
  Future<void> _queue = Future<void>.value();

  Future<void> initialize({@visibleForTesting File? file}) async {
    await _queue;
    try {
      if (file != null) {
        _file = file;
      } else {
        final directory = await getApplicationDocumentsDirectory();
        _file = File('${directory.path}/jeff_notes_diagnostic.log');
      }
      await _rotateIfNeeded();
      await record('app', 'launched');
    } catch (error) {
      debugPrint('Diagnostic log initialization failed: ${error.runtimeType}');
    }
  }

  Future<void> record(
    String category,
    String event, {
    String? sessionId,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final file = _file;
    if (file == null) return Future<void>.value();

    final values = <String>[
      DateTime.now().toUtc().toIso8601String(),
      _cleanField(category),
      _cleanField(event),
      if (sessionId != null && sessionId.isNotEmpty)
        'session=${_cleanField(sessionId)}',
      for (final entry in fields.entries)
        if (entry.value != null)
          '${_cleanField(entry.key)}=${_cleanField(entry.value.toString())}',
    ];
    final line = '${values.join(' | ')}\n';

    _queue = _queue.then((_) async {
      try {
        await _rotateIfNeeded();
        await file.writeAsString(line, mode: FileMode.append, flush: true);
      } catch (error) {
        debugPrint('Diagnostic log write failed: ${error.runtimeType}');
      }
    });
    return _queue;
  }

  Future<String> readForSharing() async {
    await _queue;
    final file = _file;
    if (file == null || !await file.exists()) return '';
    try {
      return _redactSecrets(await file.readAsString());
    } catch (error) {
      return 'Unable to read diagnostic log (${error.runtimeType}).';
    }
  }

  Future<void> clear() async {
    await _queue;
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString('', flush: true);
      await record('diagnostic', 'log_cleared');
    } catch (error) {
      debugPrint('Diagnostic log clear failed: ${error.runtimeType}');
    }
  }

  Future<void> _rotateIfNeeded() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    if (await file.length() <= _maxBytes) return;

    final bytes = await file.readAsBytes();
    final start = bytes.length > _retainedBytes
        ? bytes.length - _retainedBytes
        : 0;
    await file.writeAsBytes(bytes.sublist(start), flush: true);
  }

  static String _cleanField(String value) =>
      _redactSecrets(value).replaceAll(RegExp(r'[\r\n|]+'), ' ').trim();

  static String _redactSecrets(String value) => value
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}'), '[REDACTED]')
      .replaceAll(RegExp(r'gsk_[A-Za-z0-9_-]{8,}'), '[REDACTED]')
      .replaceAll(RegExp(r'AIza[A-Za-z0-9_-]{20,}'), '[REDACTED]')
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
        'Bearer [REDACTED]',
      );
}
