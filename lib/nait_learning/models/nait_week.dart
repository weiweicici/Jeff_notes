import 'dart:convert';

class NaitWeek {
  final String courseId;
  final int weekNumber;
  String? packAudioPath;   // assembled listening pack WAV
  DateTime updatedAt;

  NaitWeek({
    required this.courseId,
    required this.weekNumber,
    this.packAudioPath,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'courseId': courseId,
    'weekNumber': weekNumber,
    if (packAudioPath != null) 'packAudioPath': packAudioPath,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NaitWeek.fromJson(Map<String, dynamic> json) => NaitWeek(
    courseId: json['courseId'] as String,
    weekNumber: json['weekNumber'] as int,
    packAudioPath: json['packAudioPath'] as String?,
    updatedAt: json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now(),
  );

  String toJsonString() => jsonEncode(toJson());
  factory NaitWeek.fromJsonString(String s) =>
      NaitWeek.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
