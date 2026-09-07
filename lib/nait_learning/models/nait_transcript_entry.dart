class NaitTranscriptEntry {
  final Duration timestamp;
  final String text;
  final String? speaker;

  const NaitTranscriptEntry({
    required this.timestamp,
    required this.text,
    this.speaker,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.inMilliseconds,
    'text': text,
    if (speaker != null) 'speaker': speaker,
  };

  factory NaitTranscriptEntry.fromJson(Map<String, dynamic> json) =>
      NaitTranscriptEntry(
        timestamp: Duration(milliseconds: (json['timestamp'] as num?)?.toInt() ?? 0),
        text: json['text'] as String? ?? '',
        speaker: json['speaker'] as String?,
      );

  String get formattedTimestamp {
    final h = timestamp.inHours;
    final m = timestamp.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = timestamp.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  String toString() => '[$formattedTimestamp] $text';
}
