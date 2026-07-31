/// Data model representing a single transcript line or AI summary entry.
class InsightNote {
  final String id;
  String summary;
  String transcript;
  String? translatedContent;
  final DateTime timestamp;
  bool isProcessing;
  final String? clusterId;
  final bool isSummary;

  InsightNote({
    String? id,
    required this.summary,
    required this.transcript,
    this.translatedContent,
    required this.timestamp,
    this.isProcessing = false,
    this.clusterId,
    this.isSummary = false,
  }) : id = id ?? "note_${DateTime.now().microsecondsSinceEpoch}_${transcript.hashCode}";

  Map<String, dynamic> toJson() => {
        'id': id,
        'summary': summary,
        'transcript': transcript,
        'translatedContent': translatedContent,
        'timestamp': timestamp.toIso8601String(),
        'clusterId': clusterId,
        'isSummary': isSummary,
      };

  factory InsightNote.fromJson(Map<String, dynamic> json) => InsightNote(
        id: json['id'] as String?,
        summary: json['summary'] as String? ?? '',
        transcript: json['transcript'] as String? ?? '',
        translatedContent: json['translatedContent'] as String?,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now(),
        clusterId: json['clusterId'] as String?,
        isSummary: json['isSummary'] as bool? ?? false,
      );
}
