import 'dart:convert';
import 'nait_class_analysis.dart';
import 'nait_audio_clip.dart';
import 'nait_shadowing_segment.dart';

enum NaitSessionStatus {
  importing,
  readyToProcess,
  processing,
  partial,
  processed,
  failed,
}

class NaitClassSession {
  final String id;          // e.g. '20260906'
  final String courseId;
  final int weekNumber;
  final DateTime classDate;

  /// Absolute path to the original imported audio (MP4/M4A/MP3/WAV).
  /// Kept during processing; internal temp copies may be cleaned post-verification.
  String? originalAudioPath;

  /// Path to the FFmpeg-normalized mono 16kHz 16-bit PCM WAV.
  String? normalizedAudioPath;

  /// Path to the imported Meetily TXT/JSON file.
  String? transcriptPath;

  /// Final Deliverable #1: Standalone Markdown summary path.
  String? summaryPath;

  /// Final Deliverable #2: Single 8–10 minute Shadowing MP3 path.
  String? shadowingAudioPath;

  /// Duration of shadowing.mp3 in milliseconds.
  int? shadowingDurationMs;

  /// Lightweight SonicShadow aligned segment metadata.
  List<NaitShadowingSegment> shadowingSegments;

  NaitClassAnalysis? analysis;
  List<NaitAudioClip> clips;

  NaitSessionStatus status;
  /// True after the user explicitly removes source/intermediate audio.
  bool sourceAudioCleanedUp;
  String? errorMessage;

  DateTime createdAt;
  DateTime updatedAt;

  NaitClassSession({
    required this.id,
    required this.courseId,
    required this.weekNumber,
    required this.classDate,
    this.originalAudioPath,
    this.normalizedAudioPath,
    this.transcriptPath,
    this.summaryPath,
    this.shadowingAudioPath,
    this.shadowingDurationMs,
    List<NaitShadowingSegment>? shadowingSegments,
    this.analysis,
    List<NaitAudioClip>? clips,
    this.status = NaitSessionStatus.readyToProcess,
    this.sourceAudioCleanedUp = false,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  })  : clips = clips ?? [],
        shadowingSegments = shadowingSegments ?? [];

  bool get isProcessed => status == NaitSessionStatus.processed;
  bool get isProcessing => status == NaitSessionStatus.processing;
  bool get isPartial => status == NaitSessionStatus.partial;
  bool get hasFailed => status == NaitSessionStatus.failed;

  String get displayDate {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[classDate.month - 1]} ${classDate.day}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'courseId': courseId,
    'weekNumber': weekNumber,
    'classDate': classDate.toIso8601String(),
    if (originalAudioPath != null) 'originalAudioPath': originalAudioPath,
    if (normalizedAudioPath != null) 'normalizedAudioPath': normalizedAudioPath,
    if (transcriptPath != null) 'transcriptPath': transcriptPath,
    if (summaryPath != null) 'summaryPath': summaryPath,
    if (shadowingAudioPath != null) 'shadowingAudioPath': shadowingAudioPath,
    if (shadowingDurationMs != null) 'shadowingDurationMs': shadowingDurationMs,
    if (shadowingSegments.isNotEmpty)
      'shadowingSegments': shadowingSegments.map((s) => s.toJson()).toList(),
    if (analysis != null) 'analysis': analysis!.toJson(),
    'clips': clips.map((c) => c.toJson()).toList(),
    'status': status.name,
    if (sourceAudioCleanedUp) 'sourceAudioCleanedUp': true,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NaitClassSession.fromJson(Map<String, dynamic> json) {
    NaitSessionStatus parseStatus(String? s) {
      return NaitSessionStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => NaitSessionStatus.readyToProcess,
      );
    }
    return NaitClassSession(
      id: json['id'] as String,
      courseId: json['courseId'] as String,
      weekNumber: json['weekNumber'] as int,
      classDate: DateTime.parse(json['classDate'] as String),
      originalAudioPath: json['originalAudioPath'] as String?,
      normalizedAudioPath: json['normalizedAudioPath'] as String?,
      transcriptPath: json['transcriptPath'] as String?,
      summaryPath: json['summaryPath'] as String?,
      shadowingAudioPath: json['shadowingAudioPath'] as String?,
      shadowingDurationMs: (json['shadowingDurationMs'] as num?)?.toInt(),
      shadowingSegments: (json['shadowingSegments'] as List? ?? [])
          .map((s) => NaitShadowingSegment.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList(),
      analysis: json['analysis'] != null
          ? NaitClassAnalysis.fromJson(
              Map<String, dynamic>.from(json['analysis'] as Map),
            )
          : null,
      clips: (json['clips'] as List? ?? [])
          .map((c) => NaitAudioClip.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList(),
      status: parseStatus(json['status'] as String?),
      sourceAudioCleanedUp: json['sourceAudioCleanedUp'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  String toJsonString() => jsonEncode(toJson());
  factory NaitClassSession.fromJsonString(String s) =>
      NaitClassSession.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
