class NaitEnglishChunk {
  final String id;
  String phrase;
  String chineseMeaning;
  String context;
  String courseId;
  String classSessionId;
  int weekNumber;
  Duration? sourceTimestamp;
  Duration? audioStart;
  Duration? audioEnd;
  String? audioClipId;
  int priority;
  DateTime firstSeenAt;
  DateTime lastSeenAt;
  int appearanceCount;
  int reviewCount;
  bool learned;
  DateTime? lastReviewedAt;
  String sourceType; // 'teacher_original' | 'cleaned_original' | 'practice_sentence'

  NaitEnglishChunk({
    required this.id,
    required this.phrase,
    this.chineseMeaning = '',
    this.context = '',
    this.courseId = '',
    this.classSessionId = '',
    this.weekNumber = 1,
    this.sourceTimestamp,
    this.audioStart,
    this.audioEnd,
    this.audioClipId,
    this.priority = 1,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
    this.appearanceCount = 1,
    this.reviewCount = 0,
    this.learned = false,
    this.lastReviewedAt,
    this.sourceType = 'teacher_original',
  })  : firstSeenAt = firstSeenAt ?? DateTime.now(),
        lastSeenAt = lastSeenAt ?? DateTime.now();

  static Duration? parseDurationString(dynamic val) {
    if (val == null) return null;
    if (val is int) return Duration(milliseconds: val);
    final str = val.toString().trim();
    if (str.isEmpty) return null;
    final parts = str.split(':');
    try {
      if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final s = double.parse(parts[1]);
        return Duration(minutes: m, milliseconds: (s * 1000).round());
      } else if (parts.length == 3) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final s = double.parse(parts[2]);
        return Duration(hours: h, minutes: m, milliseconds: (s * 1000).round());
      }
    } catch (_) {}
    return null;
  }

  static String formatDuration(Duration? d) {
    if (d == null) return '';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'phrase': phrase,
    'chineseMeaning': chineseMeaning,
    'context': context,
    'courseId': courseId,
    'classSessionId': classSessionId,
    'weekNumber': weekNumber,
    'sourceTimestamp': sourceTimestamp?.inMilliseconds,
    'audioStart': audioStart?.inMilliseconds,
    'audioEnd': audioEnd?.inMilliseconds,
    'audioClipId': audioClipId,
    'priority': priority,
    'firstSeenAt': firstSeenAt.toIso8601String(),
    'lastSeenAt': lastSeenAt.toIso8601String(),
    'appearanceCount': appearanceCount,
    'reviewCount': reviewCount,
    'learned': learned,
    'lastReviewedAt': lastReviewedAt?.toIso8601String(),
    'sourceType': sourceType,
  };

  factory NaitEnglishChunk.fromJson(Map<String, dynamic> json) => NaitEnglishChunk(
    id: json['id'] as String? ?? '',
    phrase: json['phrase'] as String? ?? '',
    chineseMeaning: json['chineseMeaning'] as String? ?? '',
    context: json['context'] as String? ?? '',
    courseId: json['courseId'] as String? ?? '',
    classSessionId: json['classSessionId'] as String? ?? '',
    weekNumber: (json['weekNumber'] as num?)?.toInt() ?? 1,
    sourceTimestamp: parseDurationString(json['sourceTimestamp']),
    audioStart: parseDurationString(json['audioStart']),
    audioEnd: parseDurationString(json['audioEnd']),
    audioClipId: json['audioClipId'] as String?,
    priority: (json['priority'] as num?)?.toInt() ?? 1,
    firstSeenAt: json['firstSeenAt'] != null ? DateTime.tryParse(json['firstSeenAt'] as String) : null,
    lastSeenAt: json['lastSeenAt'] != null ? DateTime.tryParse(json['lastSeenAt'] as String) : null,
    appearanceCount: (json['appearanceCount'] as num?)?.toInt() ?? 1,
    reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
    learned: json['learned'] as bool? ?? false,
    lastReviewedAt: json['lastReviewedAt'] != null ? DateTime.tryParse(json['lastReviewedAt'] as String) : null,
    sourceType: json['sourceType'] as String? ?? 'teacher_original',
  );
}
