import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class SubtitleArtworkService {
  static String? _lastGeneratedPath;

  static Future<String?> generateCardImage({
    required String docTitle,
    required String activeSentence,
    required List<String> upcomingSentences,
    required int activeIndex,
    required int totalCount,
  }) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 600, 600));

      // 1. Dark Modern Gradient Background
      final bgPaint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          const Offset(600, 600),
          [const Color(0xFF14142B), const Color(0xFF1E1E38), const Color(0xFF0F0F1A)],
        );
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 600, 600), const Radius.circular(32)),
        bgPaint,
      );

      // 2. Decorative Top Accent Line
      final linePaint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(40, 40),
          const Offset(560, 40),
          [Colors.blueAccent, Colors.deepPurpleAccent, Colors.pinkAccent],
        )
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke;
      canvas.drawLine(const Offset(40, 40), const Offset(560, 40), linePaint);

      // 3. Header Text (Doc Title + Index)
      final headerPainter = TextPainter(
        text: TextSpan(
          text: 'JEFF NOTES  •  $docTitle  [$activeIndex/$totalCount]',
          style: const TextStyle(
            color: Colors.blueAccent,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      headerPainter.layout(maxWidth: 520);
      headerPainter.paint(canvas, const Offset(40, 60));

      // 4. Highlighted Active Sentence Box Background
      final activeBoxPaint = Paint()
        ..color = const Color(0xFF2D2D4D)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(36, 105, 528, 240), const Radius.circular(16)),
        activeBoxPaint,
      );

      final borderPaint = Paint()
        ..color = Colors.blueAccent.withOpacity(0.5)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(36, 105, 528, 240), const Radius.circular(16)),
        borderPaint,
      );

      // Active Sentence Text
      final activePainter = TextPainter(
        text: TextSpan(
          children: [
            const TextSpan(
              text: '▶ ',
              style: TextStyle(color: Colors.blueAccent, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: activeSentence,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1.35,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
        maxLines: 6,
      );
      activePainter.layout(maxWidth: 496);
      activePainter.paint(canvas, const Offset(52, 120));

      // 5. Upcoming Sentences (Next 1-2 Sentences)
      double currentY = 365.0;
      if (upcomingSentences.isNotEmpty) {
        final upcomingHeader = TextPainter(
          text: const TextSpan(
            text: 'UPCOMING SENTENCES:',
            style: TextStyle(
              color: Colors.amberAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        upcomingHeader.layout(maxWidth: 520);
        upcomingHeader.paint(canvas, Offset(40, currentY));
        currentY += 30;

        for (int i = 0; i < upcomingSentences.length && i < 2; i++) {
          final upcomingPainter = TextPainter(
            text: TextSpan(
              text: '• ${upcomingSentences[i]}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 19,
                height: 1.3,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 3,
          );
          upcomingPainter.layout(maxWidth: 520);
          upcomingPainter.paint(canvas, Offset(40, currentY));
          currentY += upcomingPainter.height + 12;
          if (currentY > 550) break;
        }
      }

      // Render to Image PNG
      final picture = recorder.endRecording();
      final img = await picture.toImage(600, 600);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/lockscreen_card.png');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      _lastGeneratedPath = file.path;
      return file.path;
    } catch (e) {
      debugPrint('[SubtitleArtworkService] Error: $e');
      return _lastGeneratedPath;
    }
  }
}
