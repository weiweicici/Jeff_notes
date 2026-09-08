import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/nait_learning/models/nait_transcript_entry.dart';
import 'package:jeff_notes/nait_learning/services/nait_chunking_service.dart';

void main() {
  group('NaitChunkingService Tests', () {
    const chunker = NaitChunkingService(
      targetChunkDuration: Duration(minutes: 17),
      overlapDuration: Duration(seconds: 90),
      maxPromptTokens: 6000,
      pauseThreshold: Duration(seconds: 4),
      pauseSearchWindow: Duration(seconds: 45),
    );

    test('1. Short transcript (<17m) produces exactly 1 chunk without slicing', () {
      final entries = List.generate(
        30,
        (i) => NaitTranscriptEntry(
          timestamp: Duration(seconds: i * 20), // 0s to 580s (~9.6m)
          text: 'Entry $i discussing basic Active Directory setup.',
        ),
      );

      final chunks = chunker.createChunks(entries);
      expect(chunks.length, equals(1));
      expect(chunks.first.index, equals(0));
      expect(chunks.first.entries.length, equals(30));
      expect(chunks.first.startTime, equals(Duration.zero));
      expect(chunks.first.endTime, equals(const Duration(seconds: 580)));
    });

    test('2. 60-minute synthetic transcript creates overlapping chunks with no entry split', () {
      // 1 entry every 10 seconds -> 360 entries over 60 minutes
      final entries = List.generate(
        360,
        (i) => NaitTranscriptEntry(
          timestamp: Duration(seconds: i * 10),
          text: 'Sentence number $i explaining the server configuration and lab steps in detail.',
        ),
      );

      final chunks = chunker.createChunks(entries);

      // ~60m / ~17m chunking with 90s overlap -> ~4 chunks
      expect(chunks.length, inInclusiveRange(3, 5));

      // Verify each entry belongs to complete objects (never split)
      for (final c in chunks) {
        expect(c.entries, isNotEmpty);
        expect(c.startTime, equals(c.entries.first.timestamp));
        expect(c.endTime, equals(c.entries.last.timestamp));
        // Absolute timestamps preserved
        expect(c.entries.first.timestamp.inSeconds, greaterThanOrEqualTo(0));
      }

      // Verify overlap exists between consecutive chunks
      for (int i = 0; i < chunks.length - 1; i++) {
        final curChunk = chunks[i];
        final nextChunk = chunks[i + 1];

        // Next chunk should start before current chunk ends
        expect(nextChunk.startTime, lessThan(curChunk.endTime));
        final overlap = curChunk.endTime - nextChunk.startTime;
        expect(overlap.inSeconds, inInclusiveRange(60, 150));
      }

      // Verify all entries from first to last are covered
      expect(chunks.first.entries.first.text, equals(entries.first.text));
      expect(chunks.last.entries.last.text, equals(entries.last.text));
    });

    test('3. 120-minute synthetic transcript creates proper chunks across 2 hours', () {
      // 1 entry every 8 seconds -> 900 entries over 120 minutes
      final entries = List.generate(
        900,
        (i) => NaitTranscriptEntry(
          timestamp: Duration(seconds: i * 8),
          text: 'Technical discussion item $i on enterprise network infrastructure and DNS.',
        ),
      );

      final chunks = chunker.createChunks(entries);

      // 120 mins with 17m window & 90s overlap -> ~7-9 chunks
      expect(chunks.length, inInclusiveRange(7, 10));

      for (int i = 0; i < chunks.length; i++) {
        expect(chunks[i].index, equals(i));
        expect(chunks[i].estimatedTokenCount, lessThanOrEqualTo(6000));
      }
    });

    test('4. Boundary snaps to natural silence pause near target cutoff', () {
      // Create entries where at minute 16:40 (1000s) there is an 8-second silence gap
      final entries = <NaitTranscriptEntry>[];
      var curSec = 0;
      for (int i = 0; i < 350; i++) {
        if (curSec >= 995 && curSec < 1005) {
          curSec += 10; // 10-second silence gap at ~16m35s
        } else {
          curSec += 5;
        }
        entries.add(NaitTranscriptEntry(
          timestamp: Duration(seconds: curSec),
          text: 'Instruction point $i',
        ));
      }

      final chunks = chunker.createChunks(entries);
      expect(chunks.length, greaterThanOrEqualTo(2));

      // The end of chunk 0 should snap around the 1000s mark where the pause occurred
      final c0EndSec = chunks[0].endTime.inSeconds;
      expect(c0EndSec, inInclusiveRange(950, 1050));
    });

    test('5. Safety ceiling prevents oversized chunks when text is extremely dense', () {
      // Very long text per entry
      const smallBudgetChunker = NaitChunkingService(
        targetChunkDuration: Duration(minutes: 30),
        overlapDuration: Duration(seconds: 30),
        maxPromptTokens: 500, // Very tight token budget
      );

      final entries = List.generate(
        100,
        (i) => NaitTranscriptEntry(
          timestamp: Duration(seconds: i * 10),
          text: 'Extremely detailed explanation line $i with repeated technical nomenclature '
              'including DNS records, Active Directory domain partitions, and kerberos tickets. ' * 3,
        ),
      );

      final chunks = smallBudgetChunker.createChunks(entries);
      expect(chunks.length, greaterThan(1));

      for (final c in chunks) {
        expect(c.estimatedTokenCount, lessThanOrEqualTo(550));
      }
    });
  });
}
