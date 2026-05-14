import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfService {

  /// 过滤 PDF 渲染器无法处理的字符：
  /// 1. Emoji & 补充平面字符（代码点 > U+FFFF，即 4 字节 surrogate pair）
  /// 2. XML/HTML 标签（如 <part1_paraphrasing>）
  static String _sanitize(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune <= 0xFFFF) {
        buffer.writeCharCode(rune);
      } else {
        buffer.write(' '); // 用空格替换 emoji
      }
    }
    return buffer.toString()
        .replaceAll(RegExp(r'<[^>]+>'), '') // 移除 XML 标签
        .replaceAll('==', '')
        .replaceAll(RegExp(r'  +'), ' ')
        .trim();
  }

  static Future<void> exportToPdf(String title, String content) async {
    final pdf = pw.Document();

    pw.Font baseFont;
    pw.Font boldFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      final boldFontData = await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf');
      baseFont = pw.Font.ttf(fontData);
      boldFont = pw.Font.ttf(boldFontData);
    } catch (_) {
      baseFont = pw.Font.helvetica();
      boldFont = pw.Font.helveticaBold();
    }

    final List<pw.Widget> widgets = [];
    final lines = content.split('\n');

    for (var rawLine in lines) {
      final line = _sanitize(rawLine); // 每行先过滤非法字符

      if (line.isEmpty) {
        widgets.add(pw.SizedBox(height: 6));
        continue;
      }
      if (line.startsWith('# ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12, top: 16),
          child: pw.Text(_sanitize(line.substring(2)), style: pw.TextStyle(font: boldFont, fontSize: 22)),
        ));
      } else if (line.startsWith('## ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8, top: 12),
          child: pw.Text(_sanitize(line.substring(3)), style: pw.TextStyle(font: boldFont, fontSize: 16)),
        ));
      } else if (line.startsWith('### ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6, top: 10),
          child: pw.Text(_sanitize(line.substring(4)), style: pw.TextStyle(font: boldFont, fontSize: 13)),
        ));
      } else if (line.startsWith('---')) {
        widgets.add(pw.Divider(thickness: 0.5, color: PdfColors.grey400));
      } else if (line.startsWith('**') && line.endsWith('**')) {
        final clean = _sanitize(line.replaceAll('**', ''));
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(clean, style: pw.TextStyle(font: boldFont, fontSize: 12)),
        ));
      } else {
        final cleanedLine = _sanitize(line.replaceAll('**', '').replaceAll('*', ''));
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Text(cleanedLine, style: pw.TextStyle(font: baseFont, fontSize: 11, lineSpacing: 3)),
        ));
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 52),
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        build: (pw.Context context) => widgets,
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: title.replaceAll('.md', '.pdf'),
    );
  }
}
