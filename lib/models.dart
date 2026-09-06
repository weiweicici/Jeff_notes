export 'models/insight_note.dart';

enum AIProvider { groq, gemini }

enum AppMode { lecture, discussion, freeTalk, exam }

enum PromptStrategy {
  general,
  toeflIelts,
  scientific,
  humanities,
  recap,
  rollingNotes,
  discovery,
  discussion,
  essay,
  grammar,
}

enum PathwaysUnit {
  none,
  unit1,
  unit2,
  unit3,
  unit4,
  unit5,
  unit6,
  unit7,
  unit8,
  unit9,
  unit10,
}

/// 结构化教材数据，区分主题框架、课文、练习题
class PathwaysUnitData {
  final String theme;
  final String reading;
  final List<String> exercises;

  const PathwaysUnitData({
    required this.theme,
    required this.reading,
    this.exercises = const [],
  });

  String get fullContent => [
    '## 单元框架\n$theme',
    '## 📖 课文\n$reading',
    if (exercises.isNotEmpty) '## 📝 练习\n${exercises.join('\n\n---\n\n')}',
  ].join('\n\n---\n\n');
}
