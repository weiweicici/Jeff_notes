import 'package:flutter/material.dart';

class RecordingPulseFAB extends StatefulWidget {
  final bool isRecording;
  final bool isPaused;
  final VoidCallback onPressed;

  const RecordingPulseFAB({
    super.key,
    required this.isRecording,
    required this.onPressed,
    this.isPaused = false,
  });

  @override
  State<RecordingPulseFAB> createState() => _RecordingPulseFABState();
}

class _RecordingPulseFABState extends State<RecordingPulseFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  bool get _isActivelyRecording => widget.isRecording && !widget.isPaused;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (_isActivelyRecording) _controller.repeat();
  }

  @override
  void didUpdateWidget(RecordingPulseFAB oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasActive = oldWidget.isRecording && !oldWidget.isPaused;
    if (_isActivelyRecording && !wasActive) {
      _controller.repeat();
    } else if (!_isActivelyRecording && wasActive) {
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

    // 录音控制使用低饱和灰色，保留图标和轻微脉冲来区分状态。
    final baseColor = isDark ? const Color(0xFF555563) : Colors.grey.shade600;

    return Stack(
      alignment: Alignment.center,
      children: [
        // 录音中：低存在感的灰色脉冲扩散动画
        if (_isActivelyRecording)
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
                    color: baseColor.withOpacity((1.0 - progress) * 0.28),
                  ),
                );
              },
            );
          }),
        // 暂停中：静态灰色光晕（无动画，视觉区分）
        if (widget.isPaused)
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
            color: baseColor.withOpacity(0.12),
            ),
          ),
        FloatingActionButton(
          onPressed: widget.onPressed,
          backgroundColor: baseColor,
          elevation: 8,
          shape: const CircleBorder(),
          child: Icon(
            // 待机=mic, 录音中或暂停中=stop_circle（按下都会终止整个会话）
            widget.isRecording ? Icons.stop_circle : Icons.mic,
            color: Colors.white,
            size: 32,
          ),
        ),
      ],
    );
  }
}
