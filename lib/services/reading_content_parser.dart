class ReadingContentParser {
  const ReadingContentParser._();

  /// Removes only an explicit exercises section. Page separators (`---`) are
  /// retained because imported PDF/OCR documents use them between pages.
  static String extractArticle(String markdown) {
    final exerciseHeading = RegExp(
      r'^\s*#{1,6}\s*(?:📝\s*)?(?:练习|exercises?|questions?)\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(markdown);
    if (exerciseHeading == null) return markdown.trim();
    return markdown.substring(0, exerciseHeading.start).trim();
  }
}
