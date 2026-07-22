import 'dart:convert';

class VocabCard {
  final String id;
  final String wordOrPhrase;
  final String? phonetic;
  final String definition;
  final String exampleSentence;
  final String exampleTranslation;
  final String grammarBreakdown;
  final String sourceTitle;
  final DateTime createdAt;
  bool isMastered;

  VocabCard({
    required this.id,
    required this.wordOrPhrase,
    this.phonetic,
    required this.definition,
    required this.exampleSentence,
    required this.exampleTranslation,
    required this.grammarBreakdown,
    required this.sourceTitle,
    required this.createdAt,
    this.isMastered = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'wordOrPhrase': wordOrPhrase,
        'phonetic': phonetic,
        'definition': definition,
        'exampleSentence': exampleSentence,
        'exampleTranslation': exampleTranslation,
        'grammarBreakdown': grammarBreakdown,
        'sourceTitle': sourceTitle,
        'createdAt': createdAt.toIso8601String(),
        'isMastered': isMastered,
      };

  factory VocabCard.fromJson(Map<String, dynamic> json) => VocabCard(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        wordOrPhrase: json['wordOrPhrase'] as String? ?? '',
        phonetic: json['phonetic'] as String?,
        definition: json['definition'] as String? ?? '',
        exampleSentence: json['exampleSentence'] as String? ?? '',
        exampleTranslation: json['exampleTranslation'] as String? ?? '',
        grammarBreakdown: json['grammarBreakdown'] as String? ?? '',
        sourceTitle: json['sourceTitle'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        isMastered: json['isMastered'] as bool? ?? false,
      );

  String encode() => jsonEncode(toJson());
  factory VocabCard.decode(String str) => VocabCard.fromJson(jsonDecode(str) as Map<String, dynamic>);
}
