class NaitListeningTimestamp {
  final String id;
  final String label;
  final String phrase;
  final Duration start;
  final Duration end;
  final String classSessionId;
  String? audioClipId;
  String? clipPath;
  final String sourceType;

  NaitListeningTimestamp({
    required this.id,
    required this.label,
    required this.phrase,
    required this.start,
    required this.end,
    this.classSessionId = '',
    this.audioClipId,
    this.clipPath,
    this.sourceType = 'teacher_original',
  });

  Duration get duration => end - start;

  static Duration parseDurationString(dynamic val) {
    if (val == null) return Duration.zero;
    if (val is int) return Duration(milliseconds: val);
    final str = val.toString().trim();
    if (str.isEmpty) return Duration.zero;
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
    return Duration.zero;
  }

  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'phrase': phrase,
    'start': start.inMilliseconds,
    'end': end.inMilliseconds,
    'classSessionId': classSessionId,
    'audioClipId': audioClipId,
    'clipPath': clipPath,
    'sourceType': sourceType,
  };

  factory NaitListeningTimestamp.fromJson(Map<String, dynamic> json) =>
      NaitListeningTimestamp(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        phrase: json['phrase'] as String? ?? '',
        start: parseDurationString(json['start']),
        end: parseDurationString(json['end']),
        classSessionId: json['classSessionId'] as String? ?? '',
        audioClipId: json['audioClipId'] as String?,
        clipPath: json['clipPath'] as String?,
        sourceType: json['sourceType'] as String? ?? 'teacher_original',
      );
}
