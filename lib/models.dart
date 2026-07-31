export 'models/insight_note.dart';

enum AIProvider { groq, siliconFlow, gemini }
enum AppMode { lecture, discussion, freeTalk, exam }
enum PromptStrategy { general, toeflIelts, scientific, humanities, recap, discovery, discussion, essay, grammar }
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

class GrammarPart {
  final String id;
  final String title;
  final List<GrammarUnit> units;
  const GrammarPart({required this.id, required this.title, required this.units});

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'units': units.map((u) => u.toJson()).toList(),
  };

  factory GrammarPart.fromJson(Map<String, dynamic> json) => GrammarPart(
    id: json['id'] as String,
    title: json['title'] as String,
    units: (json['units'] as List<dynamic>)
        .map((e) => GrammarUnit.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class GrammarUnit {
  final String id;
  final String title;
  final String outcomes;
  final String chart;
  final String chineseGuide;
  final String keyRules;
  final String commonMistakes;
  final String vocabulary;
  const GrammarUnit({
    required this.id,
    required this.title,
    required this.outcomes,
    required this.chart,
    required this.chineseGuide,
    required this.keyRules,
    required this.commonMistakes,
    required this.vocabulary,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'outcomes': outcomes,
    'chart': chart,
    'chinese_guide': chineseGuide,
    'key_rules': keyRules,
    'common_mistakes': commonMistakes,
    'vocabulary': vocabulary,
  };

  factory GrammarUnit.fromJson(Map<String, dynamic> json) => GrammarUnit(
    id: json['id'] as String,
    title: json['title'] as String,
    outcomes: json['outcomes'] as String? ?? '',
    chart: json['chart'] as String? ?? '',
    chineseGuide: json['chinese_guide'] as String? ?? '',
    keyRules: json['key_rules'] as String? ?? '',
    commonMistakes: json['common_mistakes'] as String? ?? '',
    vocabulary: json['vocabulary'] as String? ?? '',
  );
}
