import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../recording_provider.dart';
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
  }) : chineseText = chineseText ?? text ?? '',
       englishText = englishText ?? text ?? '';

  @override
  State<TtsPlayerBar> createState() => _TtsPlayerBarState();
}

class _TtsPlayerBarState extends State<TtsPlayerBar> {
  @override
  void initState() {
    super.initState();
    final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(widget.chineseText);
    if (!hasChinese) {
      final hasRecorded =
          widget.recordedAudioPath != null &&
          widget.recordedAudioPath!.isNotEmpty;
      _selectedTab = hasRecorded ? 2 : 1;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerEnglishPrefetch();
    });
  }

  void _triggerEnglishPrefetch() {
    if (widget.englishText.isNotEmpty && context.mounted) {
      final provider = Provider.of<RecordingProvider>(context, listen: false);
      TtsService().prefetchEnglish(
        widget.englishText,
        geminiKey: provider.geminiKey,
        siliconFlowKey: widget.siliconFlowKey,
      );
    }
  }

  bool _isDragging = false;
  double _dragValue = 0.0;

  bool _isChineseDragging = false;
  double _chineseDragValue = 0.0;

  bool _isRecordedDragging = false;
  double _recordedDragValue = 0.0;

  String _formatDuration(Duration? duration) {
    if (duration == null || duration == Duration.zero) return '00:00';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showNoHeadphonesSnackBar(BuildContext context, {String debug = ''}) {
    if (!context.mounted) return;
    final msg = debug.isNotEmpty ? '⚠️ 未检测到耳机 ($debug)' : '⚠️ 未检测到耳机，请连接耳机后播放';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final tts = TtsService();
    final recordingActive = context.select<RecordingProvider, bool>(
      (provider) => provider.isRecording,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasRecordedAudio =
        widget.recordedAudioPath != null &&
        widget.recordedAudioPath!.isNotEmpty;
    final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(widget.chineseText);

    // 自动跟随正在播放的声道无缝切换 Tab
    if (tts.isChinesePlaying && hasChinese) {
      _selectedTab = 0;
    } else if (tts.isRecordedPlaying && hasRecordedAudio) {
      _selectedTab = hasChinese ? 1 : 0;
    } else if (tts.isEnglishPlaying) {
      _selectedTab = (hasChinese ? 1 : 0) + (hasRecordedAudio ? 1 : 0);
    }

    return ListenableBuilder(
      listenable: tts,
      builder: (context, _) {
        final playbackLocked =
            recordingActive || tts.playbackBlockedForRecording;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2C) : Colors.grey[100],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部极简分段选择标签栏（仅占用一行 32px）
              _buildSegmentedHeader(
                context,
                tts,
                isDark,
                hasRecordedAudio,
                hasChinese,
              ),
              const SizedBox(height: 10),

              if (playbackLocked) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text(
                    '🔒 录音进行中，停止录音后可播放',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // 下方仅渲染当前选中的 1 个播放控制卡片（大幅省下 65% 屏幕垂直空间）
              IgnorePointer(
                ignoring: playbackLocked,
                child: Opacity(
                  opacity: playbackLocked ? 0.45 : 1,
                  child: hasChinese && _selectedTab == 0
                      ? _buildChinesePlayerCard(context, tts, isDark)
                      : hasRecordedAudio && _selectedTab == (hasChinese ? 1 : 0)
                      ? _buildRecordedPlayerCard(context, tts, isDark)
                      : _buildEnglishPlayerCard(context, tts, isDark),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 极简水平分段选择器
  Widget _buildSegmentedHeader(
    BuildContext context,
    TtsService tts,
    bool isDark,
    bool hasRecordedAudio,
    bool hasChinese,
  ) {
    final tabs = [
      if (hasChinese) {'label': '🇨🇳 中文', 'index': 0},
      if (hasRecordedAudio) {'label': '🎙️ 原音', 'index': hasChinese ? 1 : 0},
      {
        'label': '🇬🇧 英文',
        'index': (hasChinese ? 1 : 0) + (hasRecordedAudio ? 1 : 0),
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14141E) : Colors.grey[250],
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: tabs.map((tab) {
          final idx = tab['index'] as int;
          final isSelected = _selectedTab == idx;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedTab = idx;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? const Color(0xFF2E2E42) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    tab['label'] as String,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black87)
                          : (isDark ? Colors.white54 : Colors.black54),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 构建中文控制卡片
  Widget _buildChinesePlayerCard(
    BuildContext context,
    TtsService tts,
    bool isDark,
  ) {
    final isSynthesizing = tts.isChineseSynthesizing;
    final isPlaying = tts.isChinesePlaying;
    final currentSpeed = tts.chineseSpeed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.interpreter_mode_rounded,
              size: 16,
              color: Colors.teal,
            ),
            const SizedBox(width: 6),
            Text(
              tts.chineseEngine == ChineseTtsEngine.iosNative
                  ? '🇨🇳 中文(iOS)'
                  : '🇨🇳 中文(Edge)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            _buildLoopModeButton(tts, isDark),
            const SizedBox(width: 6),
            // 速度选择器（默认 1.25x）
            PopupMenuButton<double>(
              initialValue: currentSpeed,
              tooltip: '播放速度',
              onSelected: (s) => tts.setChineseSpeed(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(
                    0.08,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${currentSpeed}x',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              itemBuilder: (_) => [0.75, 1.0, 1.25, 1.5, 2.0]
                  .map(
                    (s) =>
                        PopupMenuItem<double>(value: s, child: Text('${s}x')),
                  )
                  .toList(),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // 中文方案一与方案二极简选择按钮
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF14141E) : Colors.grey[250],
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => tts.setChineseEngine(ChineseTtsEngine.iosNative),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: tts.chineseEngine == ChineseTtsEngine.iosNative
                          ? (isDark ? const Color(0xFF2E2E42) : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: tts.chineseEngine == ChineseTtsEngine.iosNative
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 3,
                              ),
                            ]
                          : [],
                    ),
                    child: Center(
                      child: Text(
                        '📱 iOS原生',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              tts.chineseEngine == ChineseTtsEngine.iosNative
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: tts.chineseEngine == ChineseTtsEngine.iosNative
                              ? (isDark ? Colors.amberAccent : Colors.teal)
                              : (isDark ? Colors.white54 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      tts.setChineseEngine(ChineseTtsEngine.edgeNeural),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: tts.chineseEngine == ChineseTtsEngine.edgeNeural
                          ? (isDark ? const Color(0xFF2E2E42) : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow:
                          tts.chineseEngine == ChineseTtsEngine.edgeNeural
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 3,
                              ),
                            ]
                          : [],
                    ),
                    child: Center(
                      child: Text(
                        '🌐 微软Edge',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              tts.chineseEngine == ChineseTtsEngine.edgeNeural
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color:
                              tts.chineseEngine == ChineseTtsEngine.edgeNeural
                              ? (isDark ? Colors.cyanAccent : Colors.teal)
                              : (isDark ? Colors.white54 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 进度条（支持 60fps 动态实时刷新及精准 Seek）
        StreamBuilder<Duration?>(
          stream: tts.chineseDurationStream,
          builder: (context, durationSnap) {
            return StreamBuilder<Duration>(
              stream: tts.chinesePositionStream,
              builder: (context, posSnap) {
                final isActive =
                    tts.currentAudioType == ActiveAudioType.chinese;
                final duration = isActive
                    ? (tts.currentDuration ??
                          durationSnap.data ??
                          Duration.zero)
                    : Duration.zero;
                final position = isActive
                    ? (posSnap.data ?? tts.currentPosition)
                    : Duration.zero;
                final maxMs = duration.inMilliseconds.toDouble();
                final streamMs = position.inMilliseconds.toDouble().clamp(
                  0.0,
                  maxMs > 0 ? maxMs : 1.0,
                );

                final displayMs = _isChineseDragging
                    ? _chineseDragValue
                    : streamMs;

                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                        activeTrackColor: Colors.teal,
                        inactiveTrackColor: isDark
                            ? Colors.white24
                            : Colors.grey[300],
                        thumbColor: Colors.teal,
                      ),
                      child: Slider(
                        min: 0.0,
                        max: maxMs > 0 ? maxMs : 1.0,
                        value: displayMs.clamp(0.0, maxMs > 0 ? maxMs : 1.0),
                        onChangeStart: maxMs > 0
                            ? (val) => setState(() {
                                _isChineseDragging = true;
                                _chineseDragValue = val;
                              })
                            : null,
                        onChanged: maxMs > 0
                            ? (val) => setState(() => _chineseDragValue = val)
                            : null,
                        onChangeEnd: maxMs > 0
                            ? (val) {
                                tts.seekChinese(
                                  Duration(milliseconds: val.toInt()),
                                );
                                setState(() => _isChineseDragging = false);
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
                              _isChineseDragging
                                  ? Duration(
                                      milliseconds: _chineseDragValue.toInt(),
                                    )
                                  : position,
                            ),
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
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
                final pos = tts.currentPosition;
                final newPos = pos - const Duration(seconds: 10);
                await tts.seekChinese(
                  newPos < Duration.zero ? Duration.zero : newPos,
                );
              },
            ),
            const SizedBox(width: 8),

            if (isSynthesizing)
              const Padding(
                padding: EdgeInsets.all(6.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.teal,
                  ),
                ),
              )
            else
              IconButton.filled(
                iconSize: 22,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (isPlaying) {
                    await tts.pauseChinese();
                  } else {
                    try {
                      if (tts.currentAudioType == ActiveAudioType.chinese &&
                          tts.currentPosition > Duration.zero) {
                        await tts.playChinese();
                      } else {
                        final provider = Provider.of<RecordingProvider>(
                          context,
                          listen: false,
                        );
                        await tts.speakChinese(
                          widget.chineseText,
                          geminiKey: provider.geminiKey,
                          siliconFlowKey: widget.siliconFlowKey,
                        );
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      if (e.toString().contains('NoHeadphones')) {
                        _showNoHeadphonesSnackBar(context, debug: e.toString());
                      } else {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('播放错误: $e')));
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
                final pos = tts.currentPosition;
                await tts.seekChinese(pos + const Duration(seconds: 10));
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.stop_rounded,
                color: Colors.redAccent,
                size: 22,
              ),
              onPressed: () => tts.stopChinese(),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建真实课堂现场录音卡片
  Widget _buildRecordedPlayerCard(
    BuildContext context,
    TtsService tts,
    bool isDark,
  ) {
    final isPlaying = tts.isRecordedPlaying;
    final currentSpeed = tts.englishSpeed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.graphic_eq_rounded, size: 16, color: Colors.green),
            const SizedBox(width: 6),
            const Text(
              '🎙️ 现场原音',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            _buildLoopModeButton(tts, isDark),
            const SizedBox(width: 6),
            PopupMenuButton<double>(
              initialValue: currentSpeed,
              tooltip: '播放速度',
              onSelected: (s) => tts.setEnglishSpeed(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(
                    0.08,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${currentSpeed}x',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              itemBuilder: (_) => [0.75, 1.0, 1.25, 1.5, 2.0]
                  .map(
                    (s) =>
                        PopupMenuItem<double>(value: s, child: Text('${s}x')),
                  )
                  .toList(),
            ),
          ],
        ),
        StreamBuilder<Duration?>(
          stream: tts.englishDurationStream,
          builder: (context, durationSnap) {
            final isActive = tts.currentAudioType == ActiveAudioType.recorded;
            final duration = isActive
                ? (durationSnap.data ?? Duration.zero)
                : Duration.zero;
            return StreamBuilder<Duration>(
              stream: tts.englishPositionStream,
              builder: (context, posSnap) {
                final position = isActive
                    ? (posSnap.data ?? Duration.zero)
                    : Duration.zero;
                final maxMs = duration.inMilliseconds.toDouble();
                final streamMs = position.inMilliseconds.toDouble().clamp(
                  0.0,
                  maxMs > 0 ? maxMs : 1.0,
                );
                final displayMs = _isRecordedDragging
                    ? _recordedDragValue
                    : streamMs;

                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                        activeTrackColor: Colors.green,
                        inactiveTrackColor: isDark
                            ? Colors.white24
                            : Colors.grey[300],
                        thumbColor: Colors.green,
                      ),
                      child: Slider(
                        min: 0.0,
                        max: maxMs > 0 ? maxMs : 1.0,
                        value: displayMs,
                        onChangeStart: maxMs > 0
                            ? (val) => setState(() {
                                _isRecordedDragging = true;
                                _recordedDragValue = val;
                              })
                            : null,
                        onChanged: maxMs > 0
                            ? (val) => setState(() => _recordedDragValue = val)
                            : null,
                        onChangeEnd: maxMs > 0
                            ? (val) {
                                tts.seekEnglish(
                                  Duration(milliseconds: val.toInt()),
                                );
                                setState(() => _isRecordedDragging = false);
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
                              _isRecordedDragging
                                  ? Duration(
                                      milliseconds: _recordedDragValue.toInt(),
                                    )
                                  : position,
                            ),
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.replay_10_rounded),
              iconSize: 22,
              onPressed: () async {
                final pos = tts.currentPosition;
                final newPos = pos - const Duration(seconds: 10);
                await tts.seekEnglish(
                  newPos < Duration.zero ? Duration.zero : newPos,
                );
              },
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              iconSize: 24,
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (isPlaying) {
                  await tts.pauseEnglish();
                } else {
                  try {
                    await tts.speakRecordedAudio(widget.recordedAudioPath!);
                  } catch (e) {
                    if (!context.mounted) return;
                    if (e.toString().contains('NoHeadphones')) {
                      _showNoHeadphonesSnackBar(context, debug: e.toString());
                    } else {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('播放错误: $e')));
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
                final pos = tts.currentPosition;
                await tts.seekEnglish(pos + const Duration(seconds: 10));
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.stop_rounded,
                color: Colors.redAccent,
                size: 22,
              ),
              onPressed: () => tts.stopEnglish(),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建英文 AI 控制卡片
  Widget _buildEnglishPlayerCard(
    BuildContext context,
    TtsService tts,
    bool isDark,
  ) {
    final isSynthesizing = tts.isEnglishSynthesizing;
    final isPlaying = tts.isEnglishPlaying;
    final currentSpeed = tts.englishSpeed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: Colors.blueAccent),
            const SizedBox(width: 6),
            const Text(
              '🇬🇧 英文AI',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            _buildLoopModeButton(tts, isDark),
            const SizedBox(width: 6),
            // 速度选择器
            PopupMenuButton<double>(
              initialValue: currentSpeed,
              tooltip: '播放速度',
              onSelected: (s) => tts.setEnglishSpeed(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(
                    0.08,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${currentSpeed}x',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              itemBuilder: (_) => [0.75, 1.0, 1.25, 1.5, 2.0]
                  .map(
                    (s) =>
                        PopupMenuItem<double>(value: s, child: Text('${s}x')),
                  )
                  .toList(),
            ),
          ],
        ),

        // 进度条（针对 AI 包含精准 Seek 功能）
        StreamBuilder<Duration?>(
          stream: tts.englishDurationStream,
          builder: (context, durationSnap) {
            final isActive = tts.currentAudioType == ActiveAudioType.english;
            final duration = isActive
                ? (durationSnap.data ?? Duration.zero)
                : Duration.zero;
            return StreamBuilder<Duration>(
              stream: tts.englishPositionStream,
              builder: (context, posSnap) {
                final position = isActive
                    ? (posSnap.data ?? Duration.zero)
                    : Duration.zero;
                final maxMs = duration.inMilliseconds.toDouble();
                final streamMs = position.inMilliseconds.toDouble().clamp(
                  0.0,
                  maxMs > 0 ? maxMs : 1.0,
                );

                final displayMs = _isDragging ? _dragValue : streamMs;

                return Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                        activeTrackColor: Colors.blueAccent,
                        inactiveTrackColor: isDark
                            ? Colors.white24
                            : Colors.grey[300],
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
                                tts.seekEnglish(
                                  Duration(milliseconds: val.toInt()),
                                );
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
                              _isDragging
                                  ? Duration(milliseconds: _dragValue.toInt())
                                  : position,
                            ),
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
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
                final pos = tts.currentPosition;
                final newPos = pos - const Duration(seconds: 10);
                await tts.seekEnglish(
                  newPos < Duration.zero ? Duration.zero : newPos,
                );
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
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (isPlaying) {
                    await tts.pauseEnglish();
                  } else {
                    try {
                      if (tts.currentAudioType == ActiveAudioType.english &&
                          tts.currentPosition > Duration.zero) {
                        await tts.playEnglish();
                      } else {
                        final provider = Provider.of<RecordingProvider>(
                          context,
                          listen: false,
                        );
                        await tts.speakEnglish(
                          widget.englishText,
                          geminiKey: provider.geminiKey,
                          siliconFlowKey: widget.siliconFlowKey,
                        );
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      if (e.toString().contains('NoHeadphones')) {
                        _showNoHeadphonesSnackBar(context, debug: e.toString());
                      } else {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('播放错误: $e')));
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
                final pos = tts.currentPosition;
                await tts.seekEnglish(pos + const Duration(seconds: 10));
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.stop_rounded,
                color: Colors.redAccent,
                size: 22,
              ),
              onPressed: () => tts.stopEnglish(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoopModeButton(TtsService tts, bool isDark) {
    final isLoop = tts.isLoopMode;
    return GestureDetector(
      onTap: () => tts.toggleLoopMode(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color:
              (isLoop
                      ? Colors.blueAccent
                      : (isDark ? Colors.white : Colors.black))
                  .withOpacity(isLoop ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(8),
          border: isLoop
              ? Border.all(color: Colors.blueAccent.withOpacity(0.4), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLoop ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              size: 13,
              color: isLoop
                  ? Colors.blueAccent
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(width: 3),
            Text(
              isLoop ? '无限循环' : '播放1次',
              style: TextStyle(
                fontSize: 10,
                fontWeight: isLoop ? FontWeight.bold : FontWeight.normal,
                color: isLoop
                    ? Colors.blueAccent
                    : (isDark ? Colors.white70 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
