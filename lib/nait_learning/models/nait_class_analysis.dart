import 'dart:convert';
import 'nait_english_chunk.dart';
import 'nait_listening_timestamp.dart';
import 'nait_teacher_mode_task.dart';

class NaitPracticeItem {
  final String text;
  final String sourceType; // 'practice_sentence'

  const NaitPracticeItem({required this.text, required this.sourceType});

  Map<String, dynamic> toJson() => {'text': text, 'sourceType': sourceType};

  factory NaitPracticeItem.fromJson(Map<String, dynamic> json) =>
      NaitPracticeItem(
        text: json['text'] as String? ?? '',
        sourceType: json['sourceType'] as String? ?? 'practice_sentence',
      );
}

class NaitClassAnalysis {
  final List<String> mustDo;
  final List<String> lab;
  final List<String> important;
  final List<String> nextClass;
  final List<String> technicalPoints;
  final List<NaitEnglishChunk> classroomEnglish;
  final List<NaitPracticeItem> askTeacher;
  final List<NaitPracticeItem> classmateEnglish;
  final NaitTeacherModeTask? teacherMode;
  final List<NaitListeningTimestamp> listeningTimestamps;

  const NaitClassAnalysis({
    this.mustDo = const [],
    this.lab = const [],
    this.important = const [],
    this.nextClass = const [],
    this.technicalPoints = const [],
    this.classroomEnglish = const [],
    this.askTeacher = const [],
    this.classmateEnglish = const [],
    this.teacherMode,
    this.listeningTimestamps = const [],
  });

  bool get isEmpty =>
      mustDo.isEmpty &&
      lab.isEmpty &&
      important.isEmpty &&
      technicalPoints.isEmpty &&
      classroomEnglish.isEmpty;

  Map<String, dynamic> toJson() => {
    'mustDo': mustDo,
    'lab': lab,
    'important': important,
    'nextClass': nextClass,
    'technicalPoints': technicalPoints,
    'classroomEnglish': classroomEnglish.map((e) => e.toJson()).toList(),
    'askTeacher': askTeacher.map((e) => e.toJson()).toList(),
    'classmateEnglish': classmateEnglish.map((e) => e.toJson()).toList(),
    if (teacherMode != null) 'teacherMode': teacherMode!.toJson(),
    'listeningTimestamps':
        listeningTimestamps.map((e) => e.toJson()).toList(),
  };

  factory NaitClassAnalysis.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List? ?? []).map((e) => e.toString()).toList();
    return NaitClassAnalysis(
      mustDo: strings('mustDo'),
      lab: strings('lab'),
      important: strings('important'),
      nextClass: strings('nextClass'),
      technicalPoints: strings('technicalPoints'),
      classroomEnglish: (json['classroomEnglish'] as List? ?? [])
          .map((e) => NaitEnglishChunk.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      askTeacher: (json['askTeacher'] as List? ?? [])
          .map((e) => NaitPracticeItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      classmateEnglish: (json['classmateEnglish'] as List? ?? [])
          .map((e) => NaitPracticeItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      teacherMode: json['teacherMode'] != null
          ? NaitTeacherModeTask.fromJson(
              Map<String, dynamic>.from(json['teacherMode'] as Map),
            )
          : null,
      listeningTimestamps:
          (json['listeningTimestamps'] as List? ?? [])
              .map(
                (e) => NaitListeningTimestamp.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList(),
    );
  }

  String toJsonString() => jsonEncode(toJson());
  factory NaitClassAnalysis.fromJsonString(String s) =>
      NaitClassAnalysis.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
