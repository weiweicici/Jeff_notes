import 'dart:io';

/// The audio paths already claimed by one persisted recording draft.
class RecoveryDraftAudioOwnership {
  final DateTime createdAt;
  final Iterable<String> rawAudioPaths;
  final Iterable<String> pendingAudioPaths;
  final Iterable<String> stitchedAudioPaths;

  const RecoveryDraftAudioOwnership({
    required this.createdAt,
    this.rawAudioPaths = const <String>[],
    this.pendingAudioPaths = const <String>[],
    this.stitchedAudioPaths = const <String>[],
  });
}

/// Selects only unclaimed raw slices that can conservatively belong to one
/// interrupted session. This helper deliberately does not inspect mtimes or
/// delete files; the `rec_<epochMs>.wav` name is the only trusted slice time.
class RecoveryAudioOwnership {
  RecoveryAudioOwnership._();

  static const _slicePattern = r'^rec_(\d+)\.wav$';
  static const _exportPattern =
      r'^Jeff_(?:Notes|Exam|FreeTalk|Discussion)_(\d{8}_\d{6}_\d{3})_(.+)\.md$';
  static List<String> selectCandidates({
    required Iterable<String> audioPaths,
    required DateTime sessionCreatedAt,
    required Iterable<RecoveryDraftAudioOwnership> drafts,
    required Iterable<String> exportedPaths,
  }) {
    final owned = <String>{};
    DateTime? upperBound;
    for (final draft in drafts) {
      owned
        ..addAll(draft.rawAudioPaths)
        ..addAll(draft.pendingAudioPaths)
        ..addAll(draft.stitchedAudioPaths);
      if (draft.createdAt.isAfter(sessionCreatedAt)) {
        upperBound = _earlier(upperBound, draft.createdAt);
      }
    }

    for (final path in exportedPaths) {
      final timestamp = _exportStart(path);
      // Export names retain millisecond precision, while createdAt may have
      // microseconds. The current session's export is therefore <= its
      // createdAt; any strictly later timestamp belongs to a later session.
      if (timestamp == null || !timestamp.isAfter(sessionCreatedAt)) {
        continue;
      }
      upperBound = _earlier(upperBound, timestamp);
    }

    final result = <String>[];
    for (final path in audioPaths) {
      if (owned.contains(path)) continue;
      final start = _sliceStart(path);
      if (start == null || start.isBefore(sessionCreatedAt)) continue;
      if (upperBound != null && !start.isBefore(upperBound)) continue;
      result.add(path);
    }
    return result;
  }

  static DateTime? _sliceStart(String path) {
    final match = RegExp(_slicePattern).firstMatch(_basename(path));
    final millis = match == null ? null : int.tryParse(match.group(1)!);
    if (millis == null) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } on RangeError {
      return null;
    }
  }

  static DateTime? _exportStart(String path) {
    final match = RegExp(_exportPattern).firstMatch(_basename(path));
    if (match == null) return null;
    try {
      final parts = match.group(1)!.split('_');
      final date = parts[0];
      final time = parts[1];
      final year = int.parse(date.substring(0, 4));
      final month = int.parse(date.substring(4, 6));
      final day = int.parse(date.substring(6, 8));
      final hour = int.parse(time.substring(0, 2));
      final minute = int.parse(time.substring(2, 4));
      final second = int.parse(time.substring(4, 6));
      final millis = int.parse(parts[2]);
      final parsed = DateTime(year, month, day, hour, minute, second, millis);
      if (parsed.year != year ||
          parsed.month != month ||
          parsed.day != day ||
          parsed.hour != hour ||
          parsed.minute != minute ||
          parsed.second != second ||
          parsed.millisecond != millis) {
        return null;
      }
      return parsed;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  static String _basename(String path) => File(path).uri.pathSegments.last;

  static DateTime _earlier(DateTime? current, DateTime candidate) =>
      current == null || candidate.isBefore(current) ? candidate : current;
}
