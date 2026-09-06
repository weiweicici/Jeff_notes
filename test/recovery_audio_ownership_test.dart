import 'package:flutter_test/flutter_test.dart';

import 'package:jeff_notes/services/recovery_audio_ownership.dart';

void main() {
  final start = DateTime(2026, 8, 29, 13, 0);
  String slice(DateTime time) => '/docs/rec_${time.millisecondsSinceEpoch}.wav';

  test('uses slice timestamp and excludes paths owned by any draft', () {
    final current = slice(start);
    final owned = slice(start.add(const Duration(minutes: 1)));
    final later = slice(start.add(const Duration(minutes: 2)));
    final unknown = '/docs/rec_not-a-time.wav';
    final candidates = RecoveryAudioOwnership.selectCandidates(
      audioPaths: [current, owned, later, unknown],
      sessionCreatedAt: start,
      drafts: [
        RecoveryDraftAudioOwnership(
          createdAt: start.add(const Duration(minutes: 5)),
          rawAudioPaths: [owned],
        ),
      ],
      exportedPaths: const [],
    );

    expect(candidates, [current, later]);
  });

  test('uses the next draft or later export as an exclusive upper bound', () {
    final beforeNext = slice(start.add(const Duration(minutes: 1)));
    final atNextDraft = slice(start.add(const Duration(minutes: 5)));
    final afterNextDraft = slice(start.add(const Duration(minutes: 6)));
    final candidates = RecoveryAudioOwnership.selectCandidates(
      audioPaths: [beforeNext, atNextDraft, afterNextDraft],
      sessionCreatedAt: start,
      drafts: [
        RecoveryDraftAudioOwnership(
          createdAt: start.add(const Duration(minutes: 5)),
        ),
      ],
      exportedPaths: const [],
    );

    expect(candidates, [beforeNext]);
  });

  test('does not treat the current session export as its upper bound', () {
    final preciseStart = DateTime(2026, 8, 29, 13, 0, 0, 0, 900);
    final sameSession = slice(preciseStart.add(const Duration(minutes: 10)));
    final later = slice(preciseStart.add(const Duration(minutes: 20)));
    final candidates = RecoveryAudioOwnership.selectCandidates(
      audioPaths: [sameSession, later],
      sessionCreatedAt: preciseStart,
      drafts: const [],
      exportedPaths: ['/docs/Jeff_FreeTalk_20260829_130000_000_current.md'],
    );

    expect(candidates, [sameSession, later]);
  });

  test('recognizes a later export as an exclusive upper bound', () {
    final beforeExport = slice(start.add(const Duration(minutes: 1)));
    final atExport = slice(
      start.add(const Duration(minutes: 10, milliseconds: 123)),
    );
    final candidates = RecoveryAudioOwnership.selectCandidates(
      audioPaths: [beforeExport, atExport],
      sessionCreatedAt: start,
      drafts: const [],
      exportedPaths: ['/docs/Jeff_Exam_20260829_131000_123_session.md'],
    );

    expect(candidates, [beforeExport]);
  });

  test('bounds a next session that starts only 500ms later', () {
    final nextSession = slice(start.add(const Duration(milliseconds: 500)));
    final candidates = RecoveryAudioOwnership.selectCandidates(
      audioPaths: [nextSession],
      sessionCreatedAt: start,
      drafts: const [],
      exportedPaths: const [],
    );

    expect(candidates, [nextSession]);
    final bounded = RecoveryAudioOwnership.selectCandidates(
      audioPaths: [nextSession],
      sessionCreatedAt: start,
      drafts: [
        RecoveryDraftAudioOwnership(
          createdAt: start.add(const Duration(milliseconds: 500)),
        ),
      ],
      exportedPaths: const [],
    );
    expect(bounded, isEmpty);
  });

  test('ignores malformed slice epochs and export dates', () {
    final candidates = RecoveryAudioOwnership.selectCandidates(
      audioPaths: [
        '/docs/rec_999999999999999999999999999999.wav',
        slice(start.add(const Duration(minutes: 1))),
      ],
      sessionCreatedAt: start,
      drafts: const [],
      exportedPaths: ['/docs/Jeff_Notes_20261399_250000_000_bad.md'],
    );

    expect(candidates, [slice(start.add(const Duration(minutes: 1)))]);
  });
}
