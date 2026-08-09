import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class GrammarWritingThemePreset {
  const GrammarWritingThemePreset({required this.label, required this.value});

  final String label;
  final String value;
}

const grammarWritingThemePresets = <GrammarWritingThemePreset>[
  GrammarWritingThemePreset(label: '地点', value: 'a place'),
  GrammarWritingThemePreset(label: '人物', value: 'a person'),
  GrammarWritingThemePreset(label: '事件', value: 'an event'),
  GrammarWritingThemePreset(
    label: '活动/日常',
    value: 'an activity or daily routine',
  ),
  GrammarWritingThemePreset(label: '经历', value: 'a personal experience'),
  GrammarWritingThemePreset(
    label: '物品/事物',
    value: 'an important object or thing',
  ),
  GrammarWritingThemePreset(label: '计划/目标', value: 'a future plan or goal'),
  GrammarWritingThemePreset(
    label: '问题/建议',
    value: 'a problem and possible advice or solutions',
  ),
  GrammarWritingThemePreset(label: '其他', value: 'a topic of your choice'),
];

enum GrammarWritingSelectionMode { phone, automatic, custom }

class GrammarWritingDraft {
  const GrammarWritingDraft({
    this.selectedPartIds = const <String>{},
    this.selectedUnitIds = const <String>{},
    this.contentType,
    this.requireAllSelectedGrammar = false,
    this.updatedAtMilliseconds = 0,
  });

  final Set<String> selectedPartIds;
  final Set<String> selectedUnitIds;
  final String? contentType;
  final bool requireAllSelectedGrammar;
  final int updatedAtMilliseconds;

  GrammarWritingDraft copyWith({
    Set<String>? selectedPartIds,
    Set<String>? selectedUnitIds,
    String? contentType,
    bool clearContentType = false,
    bool? requireAllSelectedGrammar,
    int? updatedAtMilliseconds,
  }) {
    return GrammarWritingDraft(
      selectedPartIds: selectedPartIds ?? this.selectedPartIds,
      selectedUnitIds: selectedUnitIds ?? this.selectedUnitIds,
      contentType: clearContentType ? null : (contentType ?? this.contentType),
      requireAllSelectedGrammar:
          requireAllSelectedGrammar ?? this.requireAllSelectedGrammar,
      updatedAtMilliseconds:
          updatedAtMilliseconds ?? this.updatedAtMilliseconds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'selected_part_ids': selectedPartIds.toList()..sort(),
    'selected_unit_ids': selectedUnitIds.toList()..sort(),
    'content_type': contentType,
    'require_all_selected_grammar': requireAllSelectedGrammar,
    'updated_at_ms': updatedAtMilliseconds,
  };

  factory GrammarWritingDraft.fromJson(Map<String, dynamic> json) {
    Set<String> stringSet(Object? value) => value is List
        ? value.map((item) => item.toString()).toSet()
        : const <String>{};

    return GrammarWritingDraft(
      selectedPartIds: stringSet(json['selected_part_ids']),
      selectedUnitIds: stringSet(json['selected_unit_ids']),
      contentType: json['content_type']?.toString(),
      requireAllSelectedGrammar: json['require_all_selected_grammar'] == true,
      updatedAtMilliseconds: (json['updated_at_ms'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toWatchPayload(List<GrammarPart> parts) {
    final validPartIds = parts.map((part) => part.id).toSet();
    final validUnitIds = parts
        .expand((part) => part.units)
        .map((unit) => unit.id)
        .toSet();
    return <String, Object?>{
      'schema_version': 1,
      'updated_at_ms': updatedAtMilliseconds,
      'selected_part_ids': selectedPartIds
          .where(validPartIds.contains)
          .toList(),
      'selected_unit_ids': selectedUnitIds
          .where(validUnitIds.contains)
          .toList(),
      'content_type': contentType ?? '',
      'require_all_selected_grammar': requireAllSelectedGrammar,
      'themes': grammarWritingThemePresets
          .map(
            (theme) => <String, Object>{
              'label': theme.label,
              'value': theme.value,
            },
          )
          .toList(),
      'parts': parts
          .map(
            (part) => <String, Object>{
              'id': part.id,
              'title': part.title,
              'units': part.units
                  .map(
                    (unit) => <String, Object>{
                      'id': unit.id,
                      'title': unit.title,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    };
  }
}

class GrammarWritingLaunchOptions {
  const GrammarWritingLaunchOptions({
    required this.selectionMode,
    this.selectedPartIds = const <String>{},
    this.selectedUnitIds = const <String>{},
    this.contentType,
    this.requireAllSelectedGrammar = false,
    this.requestId,
  });

  final GrammarWritingSelectionMode selectionMode;
  final Set<String> selectedPartIds;
  final Set<String> selectedUnitIds;
  final String? contentType;
  final bool requireAllSelectedGrammar;
  final String? requestId;
}

class GrammarWritingDraftService {
  GrammarWritingDraftService._();

  static final GrammarWritingDraftService instance =
      GrammarWritingDraftService._();
  static const _preferenceKey = 'grammar_combined_draft_v1';

  Future<void>? _writeTail;
  int _pendingWriteCount = 0;

  Future<GrammarWritingDraft> load() async {
    // A Watch request can open a fresh screen immediately after the user taps
    // a phone checkbox. Wait for that last serialized write so the new screen
    // never reads the previous selection.
    final pendingWrite = _pendingWriteCount > 0 ? _writeTail : null;
    if (pendingWrite != null) {
      try {
        await pendingWrite;
      } catch (_) {}
    }
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_preferenceKey);
    if (encoded == null || encoded.isEmpty) {
      return const GrammarWritingDraft();
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const GrammarWritingDraft();
      return GrammarWritingDraft.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const GrammarWritingDraft();
    }
  }

  Future<void> save(GrammarWritingDraft draft) {
    final snapshot = draft.copyWith(
      selectedPartIds: Set<String>.from(draft.selectedPartIds),
      selectedUnitIds: Set<String>.from(draft.selectedUnitIds),
      updatedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
    );
    final previousWrite = _writeTail;
    _pendingWriteCount += 1;
    final operation = () async {
      if (previousWrite != null) {
        try {
          await previousWrite;
        } catch (_) {}
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _preferenceKey,
        jsonEncode(snapshot.toJson()),
      );
    }();
    _writeTail = operation;
    return operation.whenComplete(() {
      if (_pendingWriteCount > 0) _pendingWriteCount -= 1;
    });
  }

  void resetForTesting() {
    _writeTail = null;
    _pendingWriteCount = 0;
  }
}
