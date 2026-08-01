import '../models.dart';

/// Structured completion event emitted when background session processing finishes.
class SessionReadyEvent {
  final String sessionId;
  final AppMode mode;
  final String content;
  final String exportPath;
  final bool isFinal;
  final int eventSequence;
  final DateTime? recordedAt;

  SessionReadyEvent({
    required this.sessionId,
    required this.mode,
    required this.content,
    required this.exportPath,
    required this.isFinal,
    required this.eventSequence,
    this.recordedAt,
  });

  String get eventKey => '${sessionId}_$eventSequence';

  /// Recording time wins over AI completion time when sessions finish out of
  /// order. Session IDs are a deterministic fallback for legacy events.
  bool isNewerThan(SessionReadyEvent other) {
    final thisTime = recordedAt;
    final otherTime = other.recordedAt;
    if (thisTime != null && otherTime != null) {
      return thisTime.isAfter(otherTime);
    }
    return sessionId.compareTo(other.sessionId) > 0;
  }

  @override
  String toString() =>
      'SessionReadyEvent(sessionId: $sessionId, mode: $mode, exportPath: $exportPath, isFinal: $isFinal, eventSequence: $eventSequence)';
}
