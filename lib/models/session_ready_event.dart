import '../models.dart';

/// Structured completion event emitted when background session processing finishes.
class SessionReadyEvent {
  final String sessionId;
  final AppMode mode;
  final String content;
  final String exportPath;
  final bool isFinal;
  final int eventSequence;

  SessionReadyEvent({
    required this.sessionId,
    required this.mode,
    required this.content,
    required this.exportPath,
    required this.isFinal,
    required this.eventSequence,
  });

  String get eventKey => '${sessionId}_$eventSequence';

  @override
  String toString() =>
      'SessionReadyEvent(sessionId: $sessionId, mode: $mode, exportPath: $exportPath, isFinal: $isFinal, eventSequence: $eventSequence)';
}
