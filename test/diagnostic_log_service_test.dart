import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/diagnostic_log_service.dart';

void main() {
  test('diagnostic log records metadata and redacts credentials', () async {
    final directory = await Directory.systemTemp.createTemp(
      'jeff_notes_diagnostic_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final file = File('${directory.path}/diagnostic.log');
    final service = DiagnosticLogService.instance;
    await service.initialize(file: file);
    await service.record(
      'tts',
      'route_blocked',
      sessionId: 'session-123',
      fields: {
        'outputs': 'builtInSpeaker',
        'unsafe': 'sk-abcdefghijklmnopqrstuvwxyz',
        'multiline': 'first\nsecond',
      },
    );

    final log = await service.readForSharing();
    expect(log, contains('tts | route_blocked'));
    expect(log, contains('session=session-123'));
    expect(log, contains('outputs=builtInSpeaker'));
    expect(log, contains('[REDACTED]'));
    expect(log, isNot(contains('sk-abcdefghijklmnopqrstuvwxyz')));
    expect(log, contains('multiline=first second'));

    await service.clear();
    final clearedLog = await service.readForSharing();
    expect(clearedLog, contains('diagnostic | log_cleared'));
    expect(clearedLog, isNot(contains('route_blocked')));
  });
}
