import 'package:flutter/material.dart';
import '../services/tts_service.dart';

class TtsPlayerBar extends StatefulWidget {
  /// 纯中文总结文本（使用本地系统 TTS 0毫秒播放）
  final String chineseText;

  /// 纯英文听力文本（使用 SiliconFlow AI 拟真音色 + 精确进度条）
  final String englishText;

  /// SiliconFlow API key
  final String siliconFlowKey;

  /// 当次讲座真实录音拼合后的 .wav 文件路径（若存在则直接放现场录音）
  final String? recordedAudioPath;

  const TtsPlayerBar({
    super.key,
    String? chineseText,
    String? englishText,
    String? text,
    this.recordedAudioPath,
    required this.siliconFlowKey,
  })  : chineseText = chineseText ?? text ?? '',
        englishText = englishText ?? text ?? '';


  @override
  State<TtsPlayerBar> createState() => _TtsPlayerBarState();
}

class _TtsPlayerBarState extends State<TtsPlayerBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  String _formatDuration(Duration? duration) {
    if (duration == null || duration == Duration.zero) return '00:00';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showNoHeadphonesSnackBar(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ 未检测到耳机，请连接耳机后播放'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tts = TtsService();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: tts,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2C) : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ════════════════════════════════════════════════════════
              // 🇨🇳 控制栏 1：中文大意（本地原生 TTS · 0 毫秒秒开）
              // ════════════════════════════════════════════════════════
              _buildChinesePlayerCard(context, tts, isDark),

              const SizedBox(height: 12),
              Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey[300]),
              const SizedBox(height: 12),

              // ════════════════════════════════════════════════════════
              // 🇬🇧 控制栏 2：英文原声（AI 拟真音色 + 精确进度条）
              // ════════════════════════════════════════════════════════
              _buildEnglishPlayerCard(context, tts, isDark),
            ],
          ),
        );
      },
    );
  }

  /// 构建中文控制卡片
  Widget _buildChinesePlayerCard(BuildContext context, TtsService tts, bool isDark) {
    final isPlaying = tts.isChinesePlaying;
    final currentSpeed = tts.chineseSpeed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flash_on_rounded, size: 16, color: Colors.amber),
            const SizedBox(width: 6),
            const Text(
              '🇨🇳 中文大意 (0秒秒开 · 本地原生)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            // 速度选择器
            PopupMenuButton<double>(
              initialValue: currentSpeed,
              tooltip: '播放速度',
              onSelected: (s) => tts.setChineseSpeed(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${currentSpeed}x',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              itemBuilder: (_) => [0.75, 1.0, 1.25, 1.5, 2.0]
                  .map((s) => PopupMenuItem<double>(value: s, child: Text('${s}x')))
                  .toList(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              isPlaying ? '🔊 正在使用本地引擎朗读中...' : '点击播放按钮即刻出声',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const Spacer(),
            IconButton.filled(
              iconSize: 22,
              icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              style: IconButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (isPlaying) {
                  await tts.pauseChinese();
                } else {
                  try {
                    await tts.speakChinese(widget.chineseText);
                  } catch (e) {
                    if (e.toString().contains('NoHeadphones')) {
                      _showNoHeadphonesSnackBar(context);
                    }
                  }
                }
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.stop_rounded, color: Colors.redAccent, size: 22),
              onPressed: () => tts.stopChinese(),
            ),
          ],
        ),
        if (isPlaying || tts.chineseProgress > 0) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: tts.chineseProgress,
            backgroundColor: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ],
    );
  }

  /// 构建英文 AI 控制卡片
  Widget _buildEnglishPlayerCard(BuildContext context, TtsService tts, bool isDark) {
    final isSynthesizing = tts.isEnglishSynthesizing;
    final isPlaying = tts.isEnglishPlaying;
    final currentSpeed = tts.englishSpeed;
    final hasRecordedAudio = widget.recordedAudioPath != null && widget.recordedAudioPath!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              hasRecordedAudio ? Icons.graphic_eq_rounded : Icons.auto_awesome,
              size: 16,
              color: hasRecordedAudio ? Colors.green : Colors.blueAccent,
            ),
            const SizedBox(width: 6),
            Text(
              hasRecordedAudio ? '🇬🇧 英文原声音频 (真实课堂原音)' : '🇬🇧 英文原声 (AI 拟真音色 + 进度条)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            // 速度选择器
            PopupMenuButton<double>(
              initialValue: currentSpeed,
              tooltip: '播放速度',
              onSelected: (s) => tts.setEnglishSpeed(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${currentSpeed}x',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              itemBuilder: (_) => [0.75, 1.0, 1.25, 1.5, 2.0]
                  .map((s) => PopupMenuItem<double>(value: s, child: Text('${s}x')))
                  .toList(),
            ),
          ],
        ),

        // 进度条（针对 AI 包含精准 Seek 功能）
        StreamBuilder<Duration?>(
          stream: tts.englishDurationStream,
          builder: (context, durationSnap) {
            final duration = durationSnap.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: tts.englishPositionStream,
              builder: (context, posSnap) {
                final position = posSnap.data ?? Duration.zero;
                final maxMs = duration.inMilliseconds.toDouble();
                final streamMs = position.inMilliseconds
                    .toDouble()
                    .clamp(0.0, maxMs > 0 ? maxMs : 1.0);

                final displayMs = _isDragging ? _dragValue : streamMs;

                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: Colors.blueAccent,
                        inactiveTrackColor: isDark ? Colors.white24 : Colors.grey[300],
                        thumbColor: Colors.blueAccent,
                      ),
                      child: Slider(
                        min: 0.0,
                        max: maxMs > 0 ? maxMs : 1.0,
                        value: displayMs,
                        onChangeStart: maxMs > 0
                            ? (val) => setState(() {
                                  _isDragging = true;
                                  _dragValue = val;
                                })
                            : null,
                        onChanged: maxMs > 0
                            ? (val) => setState(() => _dragValue = val)
                            : null,
                        onChangeEnd: maxMs > 0
                            ? (val) {
                                tts.seekEnglish(Duration(milliseconds: val.toInt()));
                                setState(() => _isDragging = false);
                              }
                            : null,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(
                              _isDragging ? Duration(milliseconds: _dragValue.toInt()) : position,
                            ),
                            style: TextStyle(fontSize: 9, color: isDark ? Colors.white54 : Colors.black54),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: TextStyle(fontSize: 9, color: isDark ? Colors.white54 : Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),

        const SizedBox(height: 4),

        // 控制动作按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.replay_10_rounded),
              iconSize: 22,
              onPressed: () async {
                final pos = await tts.englishPositionStream.first;
                final newPos = pos - const Duration(seconds: 10);
                await tts.seekEnglish(newPos < Duration.zero ? Duration.zero : newPos);
              },
            ),
            const SizedBox(width: 8),

            if (isSynthesizing)
              const Padding(
                padding: EdgeInsets.all(6.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton.filled(
                iconSize: 24,
                icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (isPlaying) {
                    await tts.pauseEnglish();
                  } else {
                    try {
                      if (hasRecordedAudio) {
                        await tts.speakRecordedAudio(widget.recordedAudioPath!);
                      } else {
                        await tts.speakEnglish(
                          widget.englishText,
                          siliconFlowKey: widget.siliconFlowKey,
                        );
                      }
                    } catch (e) {
                      if (e.toString().contains('NoHeadphones')) {
                        _showNoHeadphonesSnackBar(context);
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('播放错误: $e')),
                        );
                      }
                    }
                  }
                },
              ),

            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.forward_10_rounded),
              iconSize: 22,
              onPressed: () async {
                final pos = await tts.englishPositionStream.first;
                await tts.seekEnglish(pos + const Duration(seconds: 10));
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.stop_rounded, color: Colors.redAccent, size: 22),
              onPressed: () => tts.stopEnglish(),
            ),
          ],
        ),
      ],
    );
  }
}
