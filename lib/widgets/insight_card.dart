import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:intl/intl.dart';
import 'academic_markdown.dart';

class InsightCard extends StatefulWidget {
  final String summary;
  final String transcript;
  final String? translatedContent;
  final DateTime timestamp;
  final bool isProcessing;
  final bool isSummary;
  
  const InsightCard({
    super.key, 
    required this.summary, 
    required this.transcript, 
    this.translatedContent,
    required this.timestamp, 
    required this.isProcessing,
    required this.isSummary,
  });

  @override
  State<InsightCard> createState() => _InsightCardState();
}

class _InsightCardState extends State<InsightCard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    if (widget.isProcessing) _pulseController.repeat(reverse: true);
  }
  @override
  void didUpdateWidget(InsightCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isProcessing && !oldWidget.isProcessing) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isProcessing && oldWidget.isProcessing) {
      _pulseController.stop();
    }
  }
  @override
  void dispose() { _pulseController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr = DateFormat('HH:mm:ss').format(widget.timestamp);
    
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white, 
            borderRadius: BorderRadius.circular(16), 
            border: Border.all(
              color: widget.isProcessing 
                ? (isDark ? Colors.blue[900]! : Colors.blue[100]!).withOpacity(0.3 + 0.7 * _pulseController.value) 
                : (isDark ? Colors.white10 : Colors.grey[200]!)
            ),
            boxShadow: widget.isProcessing 
              ? [BoxShadow(color: Colors.blue.withOpacity(0.05 * _pulseController.value), blurRadius: 10, spreadRadius: 2)] 
              : null,
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isProcessing)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? Colors.blue[300] : Colors.blueAccent)),
                  const SizedBox(width: 8),
                  Text('Thinking...', style: TextStyle(fontSize: 12, color: isDark ? Colors.blue[300] : Colors.blueAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: widget.summary.isNotEmpty 
                  ? MarkdownBody(
                      data: widget.summary, 
                      selectable: true,
                      styleSheet: getAcademicMarkdownStyle(context),
                      extensionSet: md.ExtensionSet(
                        [const md.FencedCodeBlockSyntax()],
                        [md.EmojiSyntax(), HighlightSyntax()],
                      ),
                      builders: {
                        'highlight': HighlightBuilder(context),
                      },
                    )
                  : Text('Capturing live lecture...', style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.grey[500])),
              ),
              const SizedBox(width: 8),
              Text(timeStr, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
          if (!widget.isSummary)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.transcript, style: TextStyle(fontSize: 18, color: isDark ? Colors.grey[400] : Colors.grey[700], height: 1.5)),
                  if (widget.translatedContent != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        widget.translatedContent!, 
                        style: TextStyle(fontSize: 14, color: Colors.grey[500], fontStyle: FontStyle.italic)
                      ),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text("Lecture insights synced.", style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
