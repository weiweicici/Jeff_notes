import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfService {
  /// 过滤 PDF 渲染器无法处理的字符。
  /// [asciiOnly] = true：只保留基本 ASCII（Helvetica 兼容模式）。
  /// [asciiOnly] = false：保留 ASCII + 完整 CJK 字符集（NotoSansSC 模式）。
  static String _sanitize(String text,
      {bool keepLeadingSpaces = false, bool asciiOnly = false}) {
    // 第一步：替换常见特殊字符为 ASCII 等价物
    String sanitized = text
        .replaceAll('\u2013', '-')   // en-dash
        .replaceAll('\u2014', '-')   // em-dash
        .replaceAll('\u2022', '-')   // bullet •
        .replaceAll('\u00B7', '.')   // middle dot ·
        .replaceAll('\u2018', "'")   // left single quote
        .replaceAll('\u2019', "'")   // right single quote
        .replaceAll('\u201C', '"')   // left double quote
        .replaceAll('\u201D', '"')   // right double quote
        .replaceAll('\u2026', '...') // ellipsis …
        .replaceAll('\u00A0', ' ')   // non-breaking space
        .replaceAll('==', '');       // 移除高亮标签

    // 第二步：逐字符过滤
    final buffer = StringBuffer();
    for (final rune in sanitized.runes) {
      if (asciiOnly) {
        // ASCII-only 模式：只保留可打印 ASCII 和换行
        if ((rune >= 32 && rune <= 126) ||
            rune == 10 ||
            rune == 13 ||
            rune == 9) {
          buffer.writeCharCode(rune);
        }
      } else {
        // NotoSansSC 模式：支持 ASCII + 完整 CJK
        if (rune >= 32 && rune <= 0x024F) {
          buffer.writeCharCode(rune); // ASCII + Latin Extended
        } else if (rune >= 0x2E80 && rune <= 0x2EFF) {
          buffer.writeCharCode(rune); // CJK 部首补充
        } else if (rune >= 0x3000 && rune <= 0x9FFF) {
          buffer.writeCharCode(rune); // CJK 标点 + 汉字主区
        } else if (rune >= 0xF900 && rune <= 0xFAFF) {
          buffer.writeCharCode(rune); // CJK 兼容汉字
        } else if (rune >= 0xFF00 && rune <= 0xFFEF) {
          buffer.writeCharCode(rune); // 全角字符
        } else if (rune == 10 || rune == 13 || rune == 9) {
          buffer.writeCharCode(rune);
        } else {
          buffer.write(' '); // 其它（Emoji 等）替换为空格
        }
      }
    }

    // 第三步：去除残余 HTML 标签
    String result = buffer.toString().replaceAll(RegExp(r'<[^>]+>'), '');
    if (keepLeadingSpaces) {
      return result.replaceAll(RegExp(r' +$'), '');
    } else {
      return result.replaceAll(RegExp(r'  +'), ' ').trim();
    }
  }

  /// 解析行内 ** 加粗语法
  static pw.InlineSpan _parseInlineMarkdown(
    String text,
    pw.Font baseFont,
    pw.Font boldFont, {
    bool asciiOnly = false,
  }) {
    final List<pw.InlineSpan> spans = [];
    final parts = text.split('**');
    for (int i = 0; i < parts.length; i++) {
      // ASCII-only 兜底：确保行内文字也经过 sanitize
      var part = asciiOnly ? _sanitize(parts[i], asciiOnly: true) : parts[i];
      if (part.isEmpty) continue;
      if (i % 2 == 1) {
        spans.add(pw.TextSpan(
          text: part,
          style: pw.TextStyle(
              font: boldFont,
              fontSize: 11,
              color: PdfColors.black,
              lineSpacing: 3),
        ));
      } else {
        spans.add(pw.TextSpan(
          text: part,
          style: pw.TextStyle(
              font: baseFont,
              fontSize: 11,
              color: PdfColors.grey900,
              lineSpacing: 3),
        ));
      }
    }
    return pw.TextSpan(children: spans);
  }

  /// 构建 PDF 字节流。
  /// [asciiOnly] = true：强制 Helvetica + ASCII-only，用于兜底重试。
  static Future<Uint8List> _buildPdfBytes(
      String content, pw.Font baseFont, pw.Font boldFont,
      {bool asciiOnly = false}) async {
    final pdf = pw.Document();
    final List<pw.Widget> widgets = [];

    // ASCII-only 兜底时加提示横幅
    if (asciiOnly) {
      widgets.add(pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        margin: const pw.EdgeInsets.only(bottom: 16),
        decoration: pw.BoxDecoration(
          color: PdfColors.amber50,
          border: pw.Border.all(color: PdfColors.amber, width: 1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Text(
          'Note: PDF rendered in ASCII-only mode. Open the .md file in-app for full bilingual content.',
          style: pw.TextStyle(
              font: baseFont,
              fontSize: 9,
              color: PdfColors.brown700),
        ),
      ));
    }

    final lines = content.split('\n');
    for (var rawLine in lines) {
      final line = _sanitize(rawLine,
          keepLeadingSpaces: true, asciiOnly: asciiOnly);

      if (line.trim().isEmpty) {
        widgets.add(pw.SizedBox(height: 6));
        continue;
      }

      int leadingSpaces = 0;
      while (leadingSpaces < line.length &&
          line.codeUnitAt(leadingSpaces) == 32) {
        leadingSpaces++;
      }
      final trimmed = line.trim();

      if (trimmed.startsWith('# ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12, top: 16),
          child: pw.Text(trimmed.substring(2),
              style: pw.TextStyle(font: boldFont, fontSize: 20)),
        ));
      } else if (trimmed.startsWith('## ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8, top: 12),
          child: pw.Text(trimmed.substring(3),
              style: pw.TextStyle(font: boldFont, fontSize: 15)),
        ));
      } else if (trimmed.startsWith('### ')) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6, top: 10),
          child: pw.Text(trimmed.substring(4),
              style: pw.TextStyle(font: boldFont, fontSize: 13)),
        ));
      } else if (trimmed.startsWith('---')) {
        widgets.add(pw.Divider(thickness: 0.5, color: PdfColors.grey400));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        widgets.add(pw.Padding(
          padding:
              pw.EdgeInsets.only(left: 12.0 + leadingSpaces * 2.0, bottom: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 5.5, right: 6),
                width: 4,
                height: 4,
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey700,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.Expanded(
                child: pw.RichText(
                  text: _parseInlineMarkdown(
                    trimmed.substring(2),
                    baseFont,
                    boldFont,
                    asciiOnly: asciiOnly,
                  ),
                ),
              ),
            ],
          ),
        ));
      } else {
        final match = RegExp(r'^(\d+)\.\s+').firstMatch(trimmed);
        if (match != null) {
          final numStr = match.group(1)!;
          final listText = trimmed.substring(match.group(0)!.length);
          widgets.add(pw.Padding(
            padding: pw.EdgeInsets.only(
                left: 12.0 + leadingSpaces * 2.0, bottom: 5),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 16,
                  child: pw.Text('$numStr.',
                      style: pw.TextStyle(font: boldFont, fontSize: 11)),
                ),
                pw.Expanded(
                  child: pw.RichText(
                    text: _parseInlineMarkdown(
                      listText,
                      baseFont,
                      boldFont,
                      asciiOnly: asciiOnly,
                    ),
                  ),
                ),
              ],
            ),
          ));
        } else {
          widgets.add(pw.Padding(
            padding: pw.EdgeInsets.only(left: leadingSpaces * 2.0, bottom: 5),
            child: pw.RichText(
              text: _parseInlineMarkdown(
                trimmed,
                baseFont,
                boldFont,
                asciiOnly: asciiOnly,
              ),
            ),
          ));
        }
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

    return pdf.save();
  }

  /// 主入口：两级容错
  /// 第1级：尝试用 NotoSansSC + 中英双语内容
  /// 第2级：如果 save() 仍然抛错，降级为 Helvetica + ASCII-only 重试
  /// [bounds] 为触发按钮的屏幕坐标矩形，用于 iPad 上分享 Popover 的锚定位置。
  static Future<void> exportToPdf(
    String title,
    String content, {
    Rect? bounds,
  }) async {
    final pdfName = title.replaceAll('.md', '.pdf');
    // iPad 分享 Popover 锚点：若调用方未提供则默认屏幕右上角位置
    final shareBounds =
        bounds ?? const Rect.fromLTWH(0, 0, 100, 50);

    // ── 步骤 1：加载字体 ──────────────────────────────
    pw.Font baseFont;
    pw.Font boldFont;
    bool useNoto = false;

    try {
      final fontData =
          await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      final boldFontData =
          await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf');
      baseFont = pw.Font.ttf(fontData);
      boldFont = pw.Font.ttf(boldFontData);
      useNoto = true;
      debugPrint('[PDF] NotoSansSC loaded from assets.');
    } catch (e) {
      debugPrint('[PDF] Asset font load failed: $e — trying Google Fonts.');
      try {
        baseFont = await PdfGoogleFonts.notoSansSCRegular();
        boldFont = await PdfGoogleFonts.notoSansSCBold();
        useNoto = true;
        debugPrint('[PDF] NotoSansSC loaded from Google Fonts.');
      } catch (e2) {
        debugPrint('[PDF] Google Fonts load failed: $e2 — falling back to Helvetica.');
        baseFont = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }
    }

    // ── 步骤 2：尝试完整渲染（含中文），使用 sharePdf 弹出 iOS 分享面板 ─────
    if (useNoto) {
      try {
        final bytes = await _buildPdfBytes(content, baseFont, boldFont,
            asciiOnly: false);
        await Printing.sharePdf(
          bytes: bytes,
          filename: pdfName,
          bounds: shareBounds,
        );
        debugPrint('[PDF] Export succeeded with NotoSansSC (sharePdf).');
        return;
      } catch (e) {
        debugPrint('[PDF] NotoSansSC render failed: $e — retrying ASCII-only.');
      }
    }

    // ── 步骤 3：兜底 — Helvetica + ASCII-only ────────────
    try {
      final helvetica = pw.Font.helvetica();
      final helveticaBold = pw.Font.helveticaBold();
      final bytes = await _buildPdfBytes(content, helvetica, helveticaBold,
          asciiOnly: true);
      await Printing.sharePdf(
        bytes: bytes,
        filename: pdfName,
        bounds: shareBounds,
      );
      debugPrint('[PDF] Export succeeded in ASCII-only fallback mode (sharePdf).');
    } catch (e) {
      debugPrint('[PDF] ASCII-only fallback also failed: $e');
      rethrow; // 向上传播，NoteDetailScreen 的 catch 块会显示 SnackBar
    }
  }
}
