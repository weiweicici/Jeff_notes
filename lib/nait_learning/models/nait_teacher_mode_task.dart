class NaitTeacherModeTask {
  final String prompt;
  final String suggestedOpening;
  final List<String> targetChunks;

  const NaitTeacherModeTask({
    required this.prompt,
    this.suggestedOpening = '',
    this.targetChunks = const [],
  });

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    'suggestedOpening': suggestedOpening,
    'targetChunks': targetChunks,
  };

  factory NaitTeacherModeTask.fromJson(Map<String, dynamic> json) =>
      NaitTeacherModeTask(
        prompt: json['prompt'] as String? ?? '',
        suggestedOpening: json['suggestedOpening'] as String? ?? '',
        targetChunks: (json['targetChunks'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}
