import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/data/grammar_content.dart';
import 'package:jeff_notes/services/grammar_repository.dart';

void main() {
  setUp(() {
    GrammarRepository.setCachedPartsForTesting(GrammarContent.parts);
  });

  tearDown(() {
    GrammarRepository.setCachedPartsForTesting(null);
  });

  test('shows only the teacher-confirmed grammar exam units', () async {
    final parts = await GrammarRepository.loadParts();
    final unitIds = [
      for (final part in parts)
        for (final unit in part.units) unit.id,
    ];

    expect(
      unitIds,
      unorderedEquals(const [
        'unit_2',
        'unit_3',
        'unit_4',
        'unit_5',
        'unit_7',
        'unit_8',
        'unit_17',
        'unit_18',
        'unit_19',
        'unit_20',
        'unit_21',
        'unit_22',
        'unit_24',
        'unit_25',
      ]),
    );

    final unit20 = parts
        .expand((part) => part.units)
        .firstWhere((unit) => unit.id == 'unit_20');
    expect(unit20.title, contains('Present Real Conditional'));
    expect(unit20.keyRules, contains('一般现在时'));
  });
}
