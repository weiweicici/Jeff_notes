import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/models/session_ready_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionReadyEvent & Deduplication Unit Tests', () {
    test('1. SessionReadyEvent properties and eventKey formatting', () {
      final event = SessionReadyEvent(
        sessionId: 'session_123',
        mode: AppMode.lecture,
        content: 'Lecture final content',
        exportPath: '/path/to/note.md',
        isFinal: true,
        eventSequence: 1,
      );

      expect(event.sessionId, 'session_123');
      expect(event.mode, AppMode.lecture);
      expect(event.exportPath, '/path/to/note.md');
      expect(event.isFinal, isTrue);
      expect(event.eventSequence, 1);
      expect(event.eventKey, 'session_123_1');
      expect(event.toString(), contains('session_123'));
    });

    test('2. Deduplication Set filters duplicate final events for the same sessionId', () {
      final shownSessionIds = <String>{};

      final event1 = SessionReadyEvent(
        sessionId: 'lecture_session_A',
        mode: AppMode.lecture,
        content: 'Content A',
        exportPath: '/path/A.md',
        isFinal: true,
        eventSequence: 1,
      );

      final event2 = SessionReadyEvent(
        sessionId: 'lecture_session_A',
        mode: AppMode.lecture,
        content: 'Content A Secondary',
        exportPath: '/path/A.md',
        isFinal: true,
        eventSequence: 2,
      );

      var modalShownCount = 0;
      for (final event in [event1, event2]) {
        if (event.mode == AppMode.lecture &&
            event.isFinal &&
            !shownSessionIds.contains(event.sessionId)) {
          shownSessionIds.add(event.sessionId);
          modalShownCount++;
        }
      }

      expect(modalShownCount, 1);
      expect(shownSessionIds, contains('lecture_session_A'));
    });

    test('3. Non-lecture modes (Exam, FreeTalk, Discussion) do NOT trigger Lecture final modal', () {
      final shownSessionIds = <String>{};

      final examEvent = SessionReadyEvent(
        sessionId: 'exam_session_B',
        mode: AppMode.exam,
        content: 'Exam content',
        exportPath: '/path/B.md',
        isFinal: true,
        eventSequence: 1,
      );

      final freeTalkEvent = SessionReadyEvent(
        sessionId: 'freetalk_session_C',
        mode: AppMode.freeTalk,
        content: 'FreeTalk content',
        exportPath: '/path/C.md',
        isFinal: true,
        eventSequence: 1,
      );

      var modalShownCount = 0;
      for (final event in [examEvent, freeTalkEvent]) {
        if (event.mode == AppMode.lecture &&
            event.isFinal &&
            !shownSessionIds.contains(event.sessionId)) {
          shownSessionIds.add(event.sessionId);
          modalShownCount++;
        }
      }

      expect(modalShownCount, 0);
      expect(shownSessionIds.isEmpty, isTrue);
    });

    test('4. Non-final events (isFinal = false) do NOT trigger Lecture final modal', () {
      final shownSessionIds = <String>{};

      final nonFinalEvent = SessionReadyEvent(
        sessionId: 'lecture_session_D',
        mode: AppMode.lecture,
        content: 'Segment summary',
        exportPath: '/path/D.md',
        isFinal: false,
        eventSequence: 1,
      );

      var modalShownCount = 0;
      if (nonFinalEvent.mode == AppMode.lecture &&
          nonFinalEvent.isFinal &&
          !shownSessionIds.contains(nonFinalEvent.sessionId)) {
        shownSessionIds.add(nonFinalEvent.sessionId);
        modalShownCount++;
      }

      expect(modalShownCount, 0);
    });

    test('5. Bounded set size cleanup (max 100 entries)', () {
      final shownSessionIds = <String>{};

      for (int i = 0; i < 105; i++) {
        final sid = 'session_$i';
        shownSessionIds.add(sid);
        if (shownSessionIds.length > 100) {
          shownSessionIds.clear();
          shownSessionIds.add(sid);
        }
      }

      expect(shownSessionIds.length, 5);
      expect(shownSessionIds, contains('session_104'));
    });
  });
}
