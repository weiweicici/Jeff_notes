import 'nait_storage_service.dart';
import 'nait_week_consolidation_service.dart';

class NaitBankItem {
  final String id;
  final String phrase;
  final String chineseMeaning;
  final String context;
  final Set<String> coursesSeen;
  final Set<int> weeksSeen;
  DateTime firstSeenAt;
  DateTime lastSeenAt;
  int appearanceCount;
  int priority;
  bool learned;
  bool isStarred;
  String? audioClipPath;

  NaitBankItem({
    required this.id,
    required this.phrase,
    required this.chineseMeaning,
    required this.context,
    required this.coursesSeen,
    required this.weeksSeen,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.appearanceCount = 1,
    this.priority = 1,
    this.learned = false,
    this.isStarred = false,
    this.audioClipPath,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'phrase': phrase,
    'chineseMeaning': chineseMeaning,
    'context': context,
    'coursesSeen': coursesSeen.toList(),
    'weeksSeen': weeksSeen.toList(),
    'firstSeenAt': firstSeenAt.toIso8601String(),
    'lastSeenAt': lastSeenAt.toIso8601String(),
    'appearanceCount': appearanceCount,
    'priority': priority,
    'learned': learned,
    'isStarred': isStarred,
    if (audioClipPath != null) 'audioClipPath': audioClipPath,
  };

  factory NaitBankItem.fromJson(Map<String, dynamic> json) => NaitBankItem(
    id: json['id'] as String? ?? '',
    phrase: json['phrase'] as String? ?? '',
    chineseMeaning: json['chineseMeaning'] as String? ?? '',
    context: json['context'] as String? ?? '',
    coursesSeen: (json['coursesSeen'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toSet() ??
        {},
    weeksSeen: (json['weeksSeen'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toSet() ??
        {},
    firstSeenAt: json['firstSeenAt'] != null
        ? DateTime.parse(json['firstSeenAt'] as String)
        : DateTime.now(),
    lastSeenAt: json['lastSeenAt'] != null
        ? DateTime.parse(json['lastSeenAt'] as String)
        : DateTime.now(),
    appearanceCount: (json['appearanceCount'] as num?)?.toInt() ?? 1,
    priority: (json['priority'] as num?)?.toInt() ?? 1,
    learned: json['learned'] as bool? ?? false,
    isStarred: json['isStarred'] as bool? ?? false,
    audioClipPath: json['audioClipPath'] as String?,
  );
}

class NaitEnglishBankService {
  final NaitStorageService _storageService;

  NaitEnglishBankService({NaitStorageService? storageService})
      : _storageService = storageService ?? NaitStorageService();

  /// Collects all English chunks from all sessions across all courses (or a specific course),
  /// aggregates counts and dates, and applies review progress.
  Future<List<NaitBankItem>> getEnglishBank({String? courseId}) async {
    final List<String> courseIds = courseId != null
        ? [courseId]
        : await _storageService.getCourseIds();

    final Map<String, NaitBankItem> bankMap = {};

    for (final cId in courseIds) {
      final weeks = await _storageService.loadWeeksForCourse(cId);
      final progress = await _storageService.loadReviewProgress(cId);

      for (final week in weeks) {
        final sessions = await _storageService.loadSessionsForWeek(cId, week.weekNumber);
        for (final session in sessions) {
          if (session.analysis == null) continue;

          // Map clips for fast lookup
          final clipPathMap = <String, String>{};
          for (final clip in session.clips) {
            clipPathMap[clip.id] = clip.filePath;
          }

          for (final chunk in session.analysis!.classroomEnglish) {
            final key = NaitWeekConsolidationService.normalizePhraseKey(chunk.phrase);
            if (key.isEmpty) continue;

            final clipPath = chunk.audioClipId != null
                ? clipPathMap[chunk.audioClipId]
                : null;

            if (bankMap.containsKey(key)) {
              final item = bankMap[key]!;
              item.coursesSeen.add(cId);
              item.weeksSeen.add(week.weekNumber);
              item.appearanceCount += 1;
              item.priority = (item.priority + 1).clamp(1, 5);
              if (chunk.lastSeenAt.isAfter(item.lastSeenAt)) {
                item.lastSeenAt = chunk.lastSeenAt;
              }
              if (item.audioClipPath == null && clipPath != null) {
                item.audioClipPath = clipPath;
              }
            } else {
              final isLearned = progress.learnedChunkIds.contains(chunk.id);
              final isStarred = progress.starredChunkIds.contains(chunk.id);

              bankMap[key] = NaitBankItem(
                id: chunk.id,
                phrase: chunk.phrase,
                chineseMeaning: chunk.chineseMeaning,
                context: chunk.context,
                coursesSeen: {cId},
                weeksSeen: {week.weekNumber},
                firstSeenAt: chunk.firstSeenAt,
                lastSeenAt: chunk.lastSeenAt,
                appearanceCount: 1,
                priority: chunk.priority,
                learned: isLearned,
                isStarred: isStarred,
                audioClipPath: clipPath,
              );
            }
          }
        }
      }
    }

    final list = bankMap.values.toList();
    list.sort((a, b) {
      final pCmp = b.priority.compareTo(a.priority);
      if (pCmp != 0) return pCmp;
      return b.appearanceCount.compareTo(a.appearanceCount);
    });
    return list;
  }

  /// Toggles learned status for a chunk.
  Future<void> toggleLearned({
    required String courseId,
    required String chunkId,
  }) async {
    final progress = await _storageService.loadReviewProgress(courseId);
    if (progress.learnedChunkIds.contains(chunkId)) {
      progress.learnedChunkIds.remove(chunkId);
    } else {
      progress.learnedChunkIds.add(chunkId);
    }
    progress.lastReviewDate = DateTime.now();
    await _storageService.saveReviewProgress(progress);
  }

  /// Toggles starred status for a chunk.
  Future<void> toggleStarred({
    required String courseId,
    required String chunkId,
  }) async {
    final progress = await _storageService.loadReviewProgress(courseId);
    if (progress.starredChunkIds.contains(chunkId)) {
      progress.starredChunkIds.remove(chunkId);
    } else {
      progress.starredChunkIds.add(chunkId);
    }
    await _storageService.saveReviewProgress(progress);
  }
}
