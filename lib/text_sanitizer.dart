/// [Architect: Isolation Strategy]
/// 专门用于处理 AI 幻觉和文本杂质的工具类
class TextSanitizer {
  static String clean(String input) {
    if (input.isEmpty) return "";

    String result = input;

    // 1. [Architect: Anti-Hallucination] 强制剔除中、日文字符，防止噪音干扰
    final cjkRegex = RegExp(r'[\u4e00-\u9fa5\u3040-\u30ff\u31f0-\u31ff]+');
    result = result.replaceAll(cjkRegex, '');

    // 2. 只移除明确的转写噪声标记，保留 [Figure 1]、(see Appendix)
    // 等有语义的结构化注释。
    final systemMarkers = RegExp(
      r'\[(?:music|applause|silence|noise|inaudible|error[^\]]*)\]'
      r'|\((?:inaudible|unclear|background noise)\)',
      caseSensitive: false,
    );
    result = result.replaceAll(systemMarkers, '');

    // 3. 清理异常重复标点与不可见乱码
    result = result.replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '');
    result = result.replaceAllMapped(
      RegExp(r'([,.?!])\1+'),
      (match) => match.group(1)!,
    );
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    // 4. 叠词幻觉熔断 (Word Stutter)
    result = _removeWordStutter(result);

    return result.trim();
  }

  /// Cleans model output used as a Chinese translation. This intentionally
  /// does not apply the English transcript sanitizer (which removes CJK).
  /// Only structural wrappers and labels are removed; English terminology in
  /// the translated sentence is preserved.
  static String cleanTranslation(String input) {
    if (input.trim().isEmpty) return '';
    var result = input.trim();

    // Peel structural wrappers until no more remain. A model can nest a
    // fence, quotation marks, and repeated labels in one response. Labels
    // are only removed at the start of a line, so terminology in prose is
    // retained.
    const quotePairs = {'"': '"', "'": "'", '“': '”', '‘': '’'};
    final leadingFence = RegExp(r'^\s*```[^\r\n]*\r?\n?');
    final trailingFence = RegExp(r'(?:\r?\n)?\s*```\s*$');
    final leadingLabel = RegExp(
      r'^\s*(?:Translation|翻译|翻译结果|中文翻译)\s*[:：]\s*',
      caseSensitive: false,
      multiLine: true,
    );
    while (true) {
      final before = result;
      result = result.replaceFirst(leadingFence, '');
      result = result.replaceFirst(trailingFence, '');
      result = result.trim();
      if (result.length >= 2 &&
          quotePairs[result[0]] == result[result.length - 1]) {
        result = result.substring(1, result.length - 1).trim();
      }
      result = result.replaceAll(leadingLabel, '').trim();
      if (result == before) break;
    }

    return result.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  static String _removeWordStutter(String text) {
    if (text.isEmpty) return text;
    final List<String> words = text.split(' ');
    if (words.length < 2) return text;

    final List<String> result = [];
    for (int i = 0; i < words.length; i++) {
      String current = words[i].trim();
      if (current.isEmpty) continue;
      final repeatedTwice =
          result.length >= 2 &&
          current.toLowerCase() == result.last.toLowerCase() &&
          current.toLowerCase() == result[result.length - 2].toLowerCase();
      if (repeatedTwice) {
        continue;
      }
      result.add(current);
    }
    return result.join(' ');
  }

  /// [Architect: Overlap Duplication Fix]
  /// 使用滑动窗口寻找 prev 结尾与 current 开头的最长公共子串，并返回拼接后的文本
  static String mergeOverlappingText(String prev, String current) {
    if (prev.isEmpty) return current;
    if (current.isEmpty) return prev;

    List<String> prevWords = prev.split(' ');
    List<String> currWords = current.split(' ');

    // 限制搜索窗口为最后 10 个词，通常 1s 回填不会超过这个范围
    int maxSearch = prevWords.length > 10 ? 10 : prevWords.length;
    int bestMatchIndex = -1;

    for (int i = 1; i <= maxSearch; i++) {
      // 提取 prev 的末尾 i 个词
      String tail = prevWords
          .sublist(prevWords.length - i)
          .join(' ')
          .toLowerCase();
      // 提取 current 的开头 i 个词
      if (i <= currWords.length) {
        String head = currWords.sublist(0, i).join(' ').toLowerCase();
        if (tail == head) {
          bestMatchIndex = i;
        }
      }
    }

    if (bestMatchIndex != -1) {
      // 如果找到匹配，修剪 current 的开头并拼接
      String uniquePart = currWords.sublist(bestMatchIndex).join(' ');
      return "$prev $uniquePart".trim();
    }

    // 没找到重叠，直接拼接
    return "$prev $current".trim();
  }
}
