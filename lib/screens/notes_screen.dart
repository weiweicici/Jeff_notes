import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'history_screen.dart';
import '../widgets/academic_markdown.dart';
import '../widgets/fade_in_slide_up.dart';
import '../widgets/recording_pulse_fab.dart';
import '../models.dart'; // 包含 AIProvider 和 AppMode 枚举
import '../recording_provider.dart'; // 放在其他导入之后，避免冲突

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<String>? _sessionReadySub;
  String? _pendingSummaryContent;
  bool _isSummaryPanelExpanded = false;

  /// 帧安全顺滑滚动 —— 在当前帧布局完成后再执行滚动，
  /// 彻底防止由于高度未更新导致的计算偏差或 jumpTo 引起的界面突变。
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final provider = context.read<RecordingProvider>();
    _sessionReadySub = provider.sessionReadyStream.listen((content) {
      if (!mounted) return;
      setState(() {
        _pendingSummaryContent = content;
      });
      // ✅ 智能自动弹窗保护：直接自动触发显示，免除用户二次点击步骤，实现“零等待”无缝体验
      _showFinalReviewModalWithContent(context, content);
    });
  }

  @override
  void dispose() {
    _sessionReadySub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _SettingsDialog(
        provider: context.read<RecordingProvider>(),
      ),
    );
  }

  void _showFinalReviewModalWithContent(BuildContext context, String content) {
    final provider = Provider.of<RecordingProvider>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
          if (provider.identifiedLectureContext != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFFFF9800).withOpacity(0.15),
              child: Row(
                children: [
                  const Icon(Icons.radar, size: 16, color: Color(0xFFFF9800)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Radar: ${provider.identifiedLectureContext}",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF9800)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          provider.currentSessionMode == AppMode.lecture ? 'ACADEMIC RECAP' : 'DISCUSSION SUMMARY', 
                          style: TextStyle(
                            fontSize: 12, 
                            fontWeight: FontWeight.w900, 
                            letterSpacing: 2, 
                            color: provider.currentSessionMode == AppMode.lecture ? Colors.blueAccent : Colors.deepPurpleAccent
                          )
                        ),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    MarkdownBody(
                      data: content,
                      softLineBreak: true,
                      styleSheet: getAcademicMarkdownStyle(context),
                      selectable: true,
                      extensionSet: md.ExtensionSet(
                        [const md.FencedCodeBlockSyntax()],
                        [md.EmojiSyntax(), HighlightSyntax()],
                      ),
                      builders: {
                        'highlight': HighlightBuilder(context),
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Jeff Notes', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -1)),
                if (provider.isRecording)
                  Row(
                    children: [
                      Text('TRACKING', style: TextStyle(fontSize: 8, color: Colors.blueAccent[200], fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      if (provider.statusMessage != null) ...[
                        const SizedBox(width: 8),
                        Text('• ${provider.statusMessage}', style: const TextStyle(fontSize: 8, color: Colors.white54, letterSpacing: 0.5)),
                      ],
                    ],
                  ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filled(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                await provider.toggleRecording();
              },
              icon: Icon(
                provider.isRecording ? Icons.stop_circle : Icons.mic,
                color: Colors.white,
              ),
              style: IconButton.styleFrom(
                backgroundColor: provider.isRecording ? Colors.redAccent : (isDark ? Colors.blueAccent : Colors.black),
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen())),
            icon: const Icon(Icons.history_edu),
          ),
          IconButton(
            onPressed: () => _showSettingsDialog(context),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_pendingSummaryContent != null)
            GestureDetector(
              onTap: () {
                final content = _pendingSummaryContent!;
                setState(() {
                  _pendingSummaryContent = null;
                });
                _showFinalReviewModalWithContent(context, content);
              },
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: provider.currentSessionMode == AppMode.lecture
                        ? [Colors.blueAccent, Colors.blue]
                        : [Colors.deepPurpleAccent, Colors.deepPurple],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (provider.currentSessionMode == AppMode.lecture
                              ? Colors.blueAccent
                              : Colors.deepPurpleAccent)
                          .withOpacity(0.3),
                      offset: const Offset(0, 4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      provider.currentSessionMode == AppMode.lecture ? Icons.school : Icons.forum,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '新总结已完成，点击查看',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white70,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          Consumer<RecordingProvider>(
            builder: (context, provider, _) => provider.hasRecoveredCache
                ? Container(
                    width: double.infinity,
                    color: Colors.blue.withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.restore, color: Colors.blue),
                        const SizedBox(width: 12),
                        const Expanded(child: Text("Unfinished lecture found. Recover?", style: TextStyle(fontWeight: FontWeight.bold))),
                        TextButton(onPressed: () => provider.dismissRecovery(), child: const Text("Dismiss", style: TextStyle(color: Colors.grey))),
                        ElevatedButton(onPressed: () => provider.recoverFromCache(), child: const Text("Recover")),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          Selector<RecordingProvider, List<InsightNote>>(
            selector: (_, p) => p.notes.where((n) => n.isSummary).toList(),
            builder: (context, summaries, _) {
              if (summaries.isEmpty) return const SizedBox.shrink();
              final latestSummary = summaries.first; 
              final isLecture = provider.currentSessionMode == AppMode.lecture;
              final isExpanded = isLecture || _isSummaryPanelExpanded;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: BoxConstraints(
                  maxHeight: isExpanded ? MediaQuery.of(context).size.height * 0.3 : 48.0,
                ),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900]?.withOpacity(0.95) : Colors.grey[50]?.withOpacity(0.95),
                  border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(0, 4), blurRadius: 10),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: isLecture ? null : () {
                        setState(() {
                          _isSummaryPanelExpanded = !_isSummaryPanelExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isLecture ? Icons.school : Icons.forum, 
                                  size: 14, 
                                  color: isLecture ? Colors.blueAccent[200] : Colors.deepPurpleAccent[200]
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isLecture ? 'LATEST ACADEMIC INSIGHT' : 'DISCUSSION SNAPSHOT', 
                                  style: TextStyle(
                                    fontSize: 10, 
                                    fontWeight: FontWeight.w900, 
                                    color: isLecture ? Colors.blueAccent[200] : Colors.deepPurpleAccent[200], 
                                    letterSpacing: 1.5
                                  )
                                ),
                              ],
                            ),
                            if (!isLecture)
                              Icon(
                                isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                size: 16,
                                color: Colors.grey,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (isExpanded)
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                          child: MarkdownBody(
                            data: latestSummary.summary,
                            softLineBreak: true,
                            styleSheet: getAcademicMarkdownStyle(context).copyWith(
                              p: const TextStyle(fontSize: 14, height: 1.3),
                              strong: TextStyle(
                                color: isLecture ? Colors.blueAccent[200] : Colors.deepPurpleAccent[200],
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          Expanded(
            child: Selector<RecordingProvider, _TranscriptData>(
              selector: (_, p) => _TranscriptData(
                p.notes.where((n) => !n.isSummary).toList(),
                p.isRecording,
              ),
              shouldRebuild: (prev, next) {
                // 新切片到达：触发重绘 + 滚动到底部
                if (prev.transcripts.length != next.transcripts.length) {
                  _scrollToBottom();
                  return true;
                }
                if (prev.isRecording != next.isRecording) return true;
                // 翻译异步到达（切片数相同但内容有变化）：触发重绘 + 滚动
                if (next.transcripts.isNotEmpty && prev.transcripts.isNotEmpty) {
                  final prevMap = {for (final n in prev.transcripts) n.id: n.translatedContent};
                  final hasNewTranslation = next.transcripts.any(
                    (note) => prevMap[note.id] != note.translatedContent,
                  );
                  if (hasNewTranslation) {
                    _scrollToBottom();
                    return true;
                  }
                }
                return false;
              },
              builder: (context, data, _) {
                final transcripts = data.transcripts;

                if (transcripts.isEmpty && !data.isRecording) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic_none, size: 48, color: isDark ? Colors.white10 : Colors.black12),
                        const SizedBox(height: 16),
                        Text('Ready for Lecture', style: TextStyle(color: isDark ? Colors.white24 : Colors.black12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  // ClampingScrollPhysics：防止翻译延迟到达时引发的剧烈回弹震动
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
                  itemCount: transcripts.length,
                  itemBuilder: (context, index) {
                    final note = transcripts[index];
                    return RepaintBoundary(
                      // RepaintBoundary Key 绑定到 note.id，防止翻译更新引发全列表重绘
                      key: ValueKey(note.id),
                      child: FadeInSlideUp(
                        key: ValueKey("anim_${note.id}"),
                        child: Padding(
                          // ValueKey 绑定到 item 容器，让 Flutter 稳定追踪每块的位置，不引发树抖动
                          key: ValueKey("item_${note.id}"),
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                note.transcript,
                                style: TextStyle(
                                  fontSize: 18,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
                                ),
                              ),
                              if (note.translatedContent != null && note.translatedContent!.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  note.translatedContent!,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: RecordingPulseFAB(
        isRecording: provider.isRecording,
        onPressed: () async {
          HapticFeedback.mediumImpact();
          await provider.toggleRecording();
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

class _TranscriptData {
  final List<InsightNote> transcripts;
  final bool isRecording;
  _TranscriptData(this.transcripts, this.isRecording);
}

// ─── Settings Dialog ────────────────────────────────────────────────────────
// 独立 StatefulWidget，让 TextEditingController 的生命周期
// 绑定到 State 的 dispose()，彻底消除 "use-after-dispose" 黑屏 Bug。
class _SettingsDialog extends StatefulWidget {
  final RecordingProvider provider;
  const _SettingsDialog({required this.provider});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late AIProvider _tempProvider;
  late AppMode _tempMode;
  late int _tempDuration;
  late bool _tempUseBluetooth;
  late bool _tempIsDarkMode;
  late bool _tempEnableFinalRecap;
  late bool _tempEnableLectureDiscovery;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _tempProvider = p.selectedProvider;
    _tempMode = p.appMode;
    _tempDuration = p.sliceDuration;
    _tempUseBluetooth = p.useBluetooth;
    _tempIsDarkMode = p.isDarkMode;
    _tempEnableFinalRecap = p.enableFinalRecap;
    _tempEnableLectureDiscovery = p.enableLectureDiscovery;
    _controller = TextEditingController(text: p.getApiKeyFor(_tempProvider));
  }

  @override
  void dispose() {
    _controller.dispose(); // 由 State.dispose() 统一调用，安全
    super.dispose();
  }

  void _save() {
    widget.provider.updateSettings(
      provider: _tempProvider,
      mode: _tempMode,
      key: _controller.text,
      duration: _tempDuration,
      useBluetooth: _tempUseBluetooth,
      isDarkMode: _tempIsDarkMode,
      enableFinalRecap: _tempEnableFinalRecap,
      enableLectureDiscovery: _tempEnableLectureDiscovery,
      geminiBaseUrl: null,
    );
    if (mounted) Navigator.pop(context);
  }

  void _cancel() {
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<AIProvider>(
              value: _tempProvider,
              decoration: const InputDecoration(labelText: 'AI Provider'),
              items: AIProvider.values
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name.toUpperCase())))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _tempProvider = val;
                    _controller.text = widget.provider.getApiKeyFor(val);
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _tempDuration,
              decoration: const InputDecoration(labelText: 'STT Frequency'),
              items: [5, 8, 10, 12, 15]
                  .map((d) => DropdownMenuItem(value: d, child: Text('$d seconds')))
                  .toList(),
              onChanged: (val) { if (val != null) setState(() => _tempDuration = val); },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AppMode>(
              value: _tempMode,
              decoration: const InputDecoration(labelText: 'Recording Mode'),
              items: AppMode.values.map((m) => DropdownMenuItem(
                value: m,
                child: Text(
                  m == AppMode.lecture
                      ? '🎓 Academic Lecture'
                      : m == AppMode.discussion
                          ? '👥 Group Discussion'
                          : 'Free Talk',
                ),
              )).toList(),
              onChanged: (val) { if (val != null) setState(() => _tempMode = val); },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Dark Mode'),
              value: _tempIsDarkMode,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) => setState(() => _tempIsDarkMode = val),
            ),
            SwitchListTile(
              title: const Text('Use Bluetooth Mic'),
              value: _tempUseBluetooth,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) => setState(() => _tempUseBluetooth = val),
            ),
            SwitchListTile(
              title: const Text('Final Academic Recap'),
              value: _tempEnableFinalRecap,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) => setState(() => _tempEnableFinalRecap = val),
            ),
            SwitchListTile(
              title: const Text('Academic Radar (Discovery)'),
              value: _tempEnableLectureDiscovery,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) => setState(() => _tempEnableLectureDiscovery = val),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: '${_tempProvider.name.toUpperCase()} API Key',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _cancel, child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}