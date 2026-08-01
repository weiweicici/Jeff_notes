import 'package:flutter/foundation.dart';

/// Converts the existing compact shorthand output (【】 block structure) into a
/// Markdown nested-list "mindmap tree" document, reusing the AI semantics that
/// were already computed during the handover. No extra AI call is needed.
class MindmapTreeBuilder {
  const MindmapTreeBuilder._();

  static const String separator = '━━━━━━━━━━━━';

  static String build({required String shorthand, String? title}) {
    final lines = shorthand.split('\n');
    final blocks = <String>[];
    var current = <String>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      if (line.trim().startsWith('━━')) {
        if (current.isNotEmpty) {
          blocks.add(current.join('\n'));
          current = [];
        }
        continue;
      }
      current.add(line.trim());
    }
    if (current.isNotEmpty) blocks.add(current.join('\n'));

    if (blocks.isEmpty) return '(暂无速记内容可生成思维导图)';

    final buffer = StringBuffer();
    if (title != null && title.isNotEmpty) {
      buffer.writeln('# $title');
      buffer.writeln();
    }
    buffer.writeln('> 由速记自动生成的思维导图（Mindmap Tree）');
    buffer.writeln();

    var blockIndex = 0;
    for (final block in blocks) {
      final head = _blockHeader(block);
      buffer.writeln('## ${head ?? '区块 ${++blockIndex}'}');
      buffer.writeln();

      final bodyLines = block.split('\n');
      for (var i = 0; i < bodyLines.length; i++) {
        final line = bodyLines[i].trim();
        if (line.isEmpty || line == head) continue;
        if (line.startsWith('──') && line.endsWith('──')) {
          buffer.writeln('  - **$line**');
        } else if (line.startsWith('──')) {
          buffer.writeln('  - **$line**');
        } else if (line.startsWith('?（待核对）') ||
            line.startsWith('✓（已确认）')) {
          buffer.writeln('  - $line');
        } else if (line.contains('：') && line.length < 40) {
          buffer.writeln('  - **$line**');
        } else {
          buffer.writeln('- $line');
        }
      }
      buffer.writeln();
    }

    final result = buffer.toString().trimRight();
    return result.isEmpty ? '(暂无速记内容可生成思维导图)' : result;
  }

  static String? _blockHeader(String block) {
    final match = RegExp(r'【(.+?)】').firstMatch(block);
    if (match == null) return null;
    return match.group(1);
  }

  static String buildFallback({
    required List<Map<String, String>> transcriptLines,
    String? title,
  }) {
    final buffer = StringBuffer();
    if (title != null && title.isNotEmpty) {
      buffer.writeln('# $title');
      buffer.writeln();
    }
    buffer.writeln('> 思维导图（基于逐句转写自动分组）');
    buffer.writeln();
    buffer.writeln('## 逐句要点');
    buffer.writeln();
    for (final line in transcriptLines) {
      final en = line['en']?.trim() ?? '';
      final zh = line['zh']?.trim() ?? '';
      if (en.isEmpty) continue;
      buffer.writeln('- **$en**${zh.isNotEmpty ? '（$zh）' : ''}');
    }
    buffer.writeln();
    return buffer.toString();
  }

  static void debug(String s) => debugPrint('[MindmapTree] $s');
}
