class NaitReviewProgress {
  final String courseId;
  final Set<String> learnedChunkIds;
  final Set<String> starredChunkIds;
  final Set<String> completedSessionIds;
  DateTime? lastReviewDate;
  int todayReviewedCount;

  NaitReviewProgress({
    required this.courseId,
    Set<String>? learnedChunkIds,
    Set<String>? starredChunkIds,
    Set<String>? completedSessionIds,
    this.lastReviewDate,
    this.todayReviewedCount = 0,
  })  : learnedChunkIds = learnedChunkIds ?? {},
        starredChunkIds = starredChunkIds ?? {},
        completedSessionIds = completedSessionIds ?? {};

  Map<String, dynamic> toJson() => {
    'courseId': courseId,
    'learnedChunkIds': learnedChunkIds.toList(),
    'starredChunkIds': starredChunkIds.toList(),
    'completedSessionIds': completedSessionIds.toList(),
    'lastReviewDate': lastReviewDate?.toIso8601String(),
    'todayReviewedCount': todayReviewedCount,
  };

  factory NaitReviewProgress.fromJson(Map<String, dynamic> json) =>
      NaitReviewProgress(
        courseId: json['courseId'] as String? ?? '',
        learnedChunkIds: (json['learnedChunkIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toSet() ??
            {},
        starredChunkIds: (json['starredChunkIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toSet() ??
            {},
        completedSessionIds: (json['completedSessionIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toSet() ??
            {},
        lastReviewDate: json['lastReviewDate'] != null
            ? DateTime.tryParse(json['lastReviewDate'] as String)
            : null,
        todayReviewedCount:
            (json['todayReviewedCount'] as num?)?.toInt() ?? 0,
      );
}
