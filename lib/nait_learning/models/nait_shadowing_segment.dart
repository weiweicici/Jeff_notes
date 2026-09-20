class NaitShadowingSegment {
  final String id;
  final String phrase;
  final String context;
  final String chineseMeaning;
  final String sourceType;
  final int originalStartMs;
  final int originalEndMs;
  final int shadowingStartMs;
  final int shadowingEndMs;
  final int priority;

  const NaitShadowingSegment({
    required this.id,
    required this.phrase,
    this.context = '',
    this.chineseMeaning = '',
    this.sourceType = 'teacher_original',
    required this.originalStartMs,
    required this.originalEndMs,
    required this.shadowingStartMs,
    required this.shadowingEndMs,
    this.priority = 1,
  });

  Duration get originalDuration => Duration(milliseconds: originalEndMs - originalStartMs);
  Duration get shadowingDuration => Duration(milliseconds: shadowingEndMs - shadowingStartMs);

  Map<String, dynamic> toJson() => {
    'id': id,
    'phrase': phrase,
    'context': context,
    'chineseMeaning': chineseMeaning,
    'sourceType': sourceType,
    'originalStartMs': originalStartMs,
    'originalEndMs': originalEndMs,
    'shadowingStartMs': shadowingStartMs,
    'shadowingEndMs': shadowingEndMs,
    'priority': priority,
  };

  factory NaitShadowingSegment.fromJson(Map<String, dynamic> json) => NaitShadowingSegment(
    id: json['id'] as String? ?? '',
    phrase: json['phrase'] as String? ?? '',
    context: json['context'] as String? ?? '',
    chineseMeaning: json['chineseMeaning'] as String? ?? '',
    sourceType: json['sourceType'] as String? ?? 'teacher_original',
    originalStartMs: (json['originalStartMs'] as num?)?.toInt() ?? 0,
    originalEndMs: (json['originalEndMs'] as num?)?.toInt() ?? 0,
    shadowingStartMs: (json['shadowingStartMs'] as num?)?.toInt() ?? 0,
    shadowingEndMs: (json['shadowingEndMs'] as num?)?.toInt() ?? 0,
    priority: (json['priority'] as num?)?.toInt() ?? 1,
  );
}
