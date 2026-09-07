import 'dart:convert';

class NaitCourse {
  final String id;       // e.g. 'SYSA1010'
  String courseCode;     // e.g. 'SYSA1010'
  String displayName;    // e.g. 'System Administration'
  final DateTime createdAt;
  DateTime updatedAt;

  NaitCourse({
    required this.id,
    required this.courseCode,
    required this.displayName,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory NaitCourse.create({
    required String courseCode,
    required String displayName,
  }) {
    final now = DateTime.now();
    return NaitCourse(
      id: courseCode.trim().toUpperCase(),
      courseCode: courseCode.trim().toUpperCase(),
      displayName: displayName.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'courseCode': courseCode,
    'displayName': displayName,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NaitCourse.fromJson(Map<String, dynamic> json) => NaitCourse(
    id: json['id'] as String,
    courseCode: json['courseCode'] as String,
    displayName: json['displayName'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  String toJsonString() => jsonEncode(toJson());
  factory NaitCourse.fromJsonString(String s) =>
      NaitCourse.fromJson(jsonDecode(s) as Map<String, dynamic>);

  NaitCourse copyWith({String? courseCode, String? displayName}) => NaitCourse(
    id: id,
    courseCode: courseCode ?? this.courseCode,
    displayName: displayName ?? this.displayName,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}
