import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'academic_markdown.dart';

class FinalSummaryCard extends StatelessWidget {
  final String content;
  const FinalSummaryCard({super.key, required this.content});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.blueGrey[50], 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: isDark ? Colors.blue[900]! : Colors.blue[100]!),
        boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 10, spreadRadius: 2)]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 28, color: isDark ? Colors.blue[300] : Colors.blueAccent),
                  const SizedBox(width: 8),
                  Text('Master Recap', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.blue[300] : Colors.blueAccent, letterSpacing: -0.5)),
                ],
              ),
              const Icon(Icons.open_in_full, size: 18, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 16),
          MarkdownBody(
            data: content.length > 300 ? "${content.substring(0, 300)}..." : content, 
            selectable: false, 
            softLineBreak: true, 
            styleSheet: getAcademicMarkdownStyle(context)
          ),
        ],
      ),
    );
  }
}

class FinalSummaryPlaceholder extends StatefulWidget {
  const FinalSummaryPlaceholder({super.key});
  @override
  State<FinalSummaryPlaceholder> createState() => _FinalSummaryPlaceholderState();
}
class _FinalSummaryPlaceholderState extends State<FinalSummaryPlaceholder> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() { super.initState(); _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(_controller),
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: isDark ? Colors.blue.withOpacity(0.1) : Colors.blueAccent.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? Colors.blue[300] : Colors.blueAccent)),
            const SizedBox(width: 16),
            Text('Synthesizing Master Recap...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.blue[300] : Colors.blueAccent)),
          ],
        ),
      ),
    );
  }
}
