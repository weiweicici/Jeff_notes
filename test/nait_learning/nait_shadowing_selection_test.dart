import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/nait_learning/models/nait_english_chunk.dart';
import 'package:jeff_notes/nait_learning/services/nait_shadowing_selection_service.dart';

void main() {
  group('NaitShadowingSelectionService', () {
    const service = NaitShadowingSelectionService();

    test('rejects non-teacher_original items and invalid audio ranges', () {
      final chunks = [
        NaitEnglishChunk(
          id: '1',
          phrase: 'valid teacher phrase',
          sourceType: 'teacher_original',
          audioStart: const Duration(seconds: 10),
          audioEnd: const Duration(seconds: 20),
        ),
        NaitEnglishChunk(
          id: '2',
          phrase: 'practice sentence phrase',
          sourceType: 'practice_sentence',
          audioStart: const Duration(seconds: 30),
          audioEnd: const Duration(seconds: 40),
        ),
        NaitEnglishChunk(
          id: '3',
          phrase: 'missing start time',
          sourceType: 'teacher_original',
          audioStart: null,
          audioEnd: const Duration(seconds: 50),
        ),
        NaitEnglishChunk(
          id: '4',
          phrase: 'invalid zero duration',
          sourceType: 'teacher_original',
          audioStart: const Duration(seconds: 60),
          audioEnd: const Duration(seconds: 60),
        ),
      ];

      final selected = service.selectBalancedChunks(chunks);
      expect(selected.length, equals(1));
      expect(selected.first.id, equals('1'));
    });

    test('preserves chronological order of selected clips by audioStart', () {
      final chunks = [
        NaitEnglishChunk(
          id: 'late_high_priority',
          phrase: 'make sure you click save',
          priority: 5,
          appearanceCount: 3,
          sourceType: 'teacher_original',
          audioStart: const Duration(minutes: 50),
          audioEnd: const Duration(minutes: 50, seconds: 15),
        ),
        NaitEnglishChunk(
          id: 'early_lower_priority',
          phrase: 'good morning everyone',
          priority: 2,
          appearanceCount: 1,
          sourceType: 'teacher_original',
          audioStart: const Duration(minutes: 2),
          audioEnd: const Duration(minutes: 2, seconds: 10),
        ),
        NaitEnglishChunk(
          id: 'mid_question',
          phrase: 'does anyone need more time?',
          priority: 4,
          appearanceCount: 1,
          sourceType: 'teacher_original',
          audioStart: const Duration(minutes: 25),
          audioEnd: const Duration(minutes: 25, seconds: 12),
        ),
      ];

      final selected = service.selectBalancedChunks(chunks);
      expect(selected.length, equals(3));
      // Must be strictly chronological
      expect(selected[0].id, equals('early_lower_priority'));
      expect(selected[1].id, equals('mid_question'));
      expect(selected[2].id, equals('late_high_priority'));
    });

    test('respects duration budget and balances categories when many chunks exist', () {
      final List<NaitEnglishChunk> manyChunks = [];

      // Generate 40 chunks across different timestamps and types (each ~15s + 0.8s gap = 15.8s, 40 * 15.8s = 632s)
      for (int i = 0; i < 40; i++) {
        final startSec = i * 120;
        final isQuestion = i % 4 == 0;
        final isInstruction = i % 4 == 1;
        final isHighFreq = i % 4 == 2;

        manyChunks.add(NaitEnglishChunk(
          id: 'chunk_$i',
          phrase: isQuestion
              ? 'Does everyone see step $i?'
              : isInstruction
                  ? 'Make sure you configure adapter $i'
                  : isHighFreq
                      ? 'leave it at default $i'
                      : 'play around with option $i',
          priority: isHighFreq ? 5 : (i % 3 + 2),
          appearanceCount: isHighFreq ? 2 : 1,
          sourceType: 'teacher_original',
          audioStart: Duration(seconds: startSec),
          audioEnd: Duration(seconds: startSec + 15),
        ));
      }

      final selected = service.selectBalancedChunks(manyChunks);

      // Total duration should fit within max budget (600s)
      int totalMs = 0;
      for (int i = 0; i < selected.length; i++) {
        totalMs += (selected[i].audioEnd! - selected[i].audioStart!).inMilliseconds;
        if (i < selected.length - 1) {
          totalMs += const Duration(milliseconds: 800).inMilliseconds;
        }
      }

      expect(totalMs, lessThanOrEqualTo(const Duration(minutes: 10).inMilliseconds));
      expect(totalMs, greaterThanOrEqualTo(const Duration(minutes: 8).inMilliseconds));

      // Check chronological order
      for (int i = 0; i < selected.length - 1; i++) {
        expect(selected[i].audioStart!.inMilliseconds, lessThan(selected[i + 1].audioStart!.inMilliseconds));
      }
    });

    test('duration fallback: retains all qualified clips when total duration < 8 minutes', () {
      final List<NaitEnglishChunk> shortClassChunks = [
        NaitEnglishChunk(
          id: 'c1',
          phrase: 'phrase one',
          sourceType: 'teacher_original',
          audioStart: const Duration(seconds: 10),
          audioEnd: const Duration(seconds: 20),
        ),
        NaitEnglishChunk(
          id: 'c2',
          phrase: 'phrase two',
          sourceType: 'teacher_original',
          audioStart: const Duration(seconds: 50),
          audioEnd: const Duration(seconds: 65),
        ),
      ];

      final selected = service.selectBalancedChunks(shortClassChunks);
      // Total duration is only ~25 seconds, but all qualified clips must be retained without duplicates
      expect(selected.length, equals(2));
      expect(selected[0].id, equals('c1'));
      expect(selected[1].id, equals('c2'));
    });
  });
}
