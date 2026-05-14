import 'package:flutter/material.dart';

class RecordingPulseFAB extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onPressed;

  const RecordingPulseFAB({
    super.key,
    required this.isRecording,
    required this.onPressed,
  });

  @override
  State<RecordingPulseFAB> createState() => _RecordingPulseFABState();
}

class _RecordingPulseFABState extends State<RecordingPulseFAB> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isRecording) _controller.repeat();
  }

  @override
  void didUpdateWidget(RecordingPulseFAB oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _controller.repeat();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = widget.isRecording ? Colors.redAccent : (isDark ? Colors.blueAccent : Colors.black);

    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.isRecording)
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final progress = (_controller.value + (index / 3)) % 1.0;
                return Container(
                  width: 56 + (progress * 80),
                  height: 56 + (progress * 80),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withOpacity(1.0 - progress),
                  ),
                );
              },
            );
          }),
        FloatingActionButton(
          onPressed: widget.onPressed,
          backgroundColor: baseColor,
          elevation: 8,
          shape: const CircleBorder(),
          child: Icon(
            widget.isRecording ? Icons.stop_circle : Icons.mic,
            color: Colors.white,
            size: 32,
          ),
        ),
      ],
    );
  }
}
