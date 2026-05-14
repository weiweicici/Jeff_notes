import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

MarkdownStyleSheet getAcademicMarkdownStyle(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final baseColor = isDark ? Colors.grey[300] : Colors.black87;
  final titleColor = isDark ? Colors.white : Colors.black;

  return MarkdownStyleSheet(
    p: TextStyle(fontSize: 20, height: 1.6, color: baseColor),
    h1: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: titleColor),
    h2: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: titleColor, height: 1.4),
    h3: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: titleColor, height: 1.4),
    listBullet: TextStyle(fontSize: 20, color: isDark ? Colors.blue[300] : Colors.blueAccent),
    strong: TextStyle(fontWeight: FontWeight.bold, color: titleColor, fontSize: 20),
    blockSpacing: 20.0,
    code: const TextStyle(
      backgroundColor: Colors.transparent, 
      fontSize: 18,
    ),
    listIndent: 30.0,
    tableBorder: TableBorder.all(color: isDark ? Colors.white24 : Colors.black12),
    tableBody: TextStyle(fontSize: 18, color: baseColor),
    tableHead: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor),
  );
}

class HighlightSyntax extends md.InlineSyntax {
  HighlightSyntax() : super(r'==(.+?)==');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('highlight', match[1]!));
    return true;
  }
}

class HighlightBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  HighlightBuilder(this.context);
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(isDark ? 0.4 : 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        element.textContent,
        style: TextStyle(
          color: isDark ? Colors.orange[300] : Colors.deepOrange[900],
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}
