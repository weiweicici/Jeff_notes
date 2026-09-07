import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/data/grammar_content.dart';
import 'package:jeff_notes/services/grammar_repository.dart';
import 'package:jeff_notes/services/grammar_writing_draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GrammarWritingDraftService.instance.resetForTesting();
    GrammarRepository.setCachedPartsForTesting(GrammarContent.parts);
  });

  tearDown(() {
    GrammarRepository.setCachedPartsForTesting(null);
  });

  test(
    'combined draft survives navigation and keeps stable grammar IDs',
    () async {
      const draft = GrammarWritingDraft(
        selectedPartIds: {'part_1'},
        selectedUnitIds: {'unit_2', 'unit_3'},
        contentType: 'an activity or daily routine',
        requireAllSelectedGrammar: true,
      );

      await GrammarWritingDraftService.instance.save(draft);
      final restored = await GrammarWritingDraftService.instance.load();

      expect(restored.selectedPartIds, {'part_1'});
      expect(restored.selectedUnitIds, {'unit_2', 'unit_3'});
      expect(restored.contentType, 'an activity or daily routine');
      expect(restored.requireAllSelectedGrammar, isTrue);
    },
  );

  test(
    'watch payload includes exam catalog and drops stale selections',
    () async {
      final parts = await GrammarRepository.loadParts();
      const draft = GrammarWritingDraft(
        selectedPartIds: {'part_1', 'removed_part'},
        selectedUnitIds: {'unit_2', 'removed_unit'},
        contentType: 'a place',
      );

      final payload = draft.toWatchPayload(parts);

      expect(payload['selected_part_ids'], ['part_1']);
      expect(payload['selected_unit_ids'], ['unit_2']);
      expect((payload['parts'] as List).length, parts.length);
      expect((payload['themes'] as List).length, 9);
    },
  );
}
