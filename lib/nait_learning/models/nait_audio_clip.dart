class NaitAudioClip {
  final String id;
  final String classSessionId;
  final String courseId;
  final int weekNumber;
  final String label;
  final String phrase;
  final Duration start;
  final Duration end;
  final String filePath;
  final int durationMs;
  final DateTime createdAt;

  NaitAudioClip({
    required this.id,
    required this.classSessionId,
    required this.courseId,
    required this.weekNumber,
    required this.label,
    required this.phrase,
    required this.start,
    required this.end,
    required this.filePath,
    required this.durationMs,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Duration get duration => end - start;

  Map<String, dynamic> toJson() => {
    'id': id,
    'classSessionId': classSessionId,
    'courseId': courseId,
    'weekNumber': weekNumber,
    'label': label,
    'phrase': phrase,
    'start': start.inMilliseconds,
    'end': end.inMilliseconds,
    'filePath': filePath,
    'durationMs': durationMs,
    'createdAt': createdAt.toIso8601String(),
  };

  factory NaitAudioClip.fromJson(Map<String, dynamic> json) => NaitAudioClip(
    id: json['id'] as String? ?? '',
    classSessionId: json['classSessionId'] as String? ?? '',
    courseId: json['courseId'] as String? ?? '',
    weekNumber: (json['weekNumber'] as num?)?.toInt() ?? 1,
    label: json['label'] as String? ?? '',
    phrase: json['phrase'] as String? ?? '',
    start: Duration(milliseconds: (json['start'] as num?)?.toInt() ?? 0),
    end: Duration(milliseconds: (json['end'] as num?)?.toInt() ?? 0),
    filePath: json['filePath'] as String? ?? '',
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String)
        : null,
  );
}
