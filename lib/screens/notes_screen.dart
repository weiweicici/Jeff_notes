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
import '../widgets/tts_player_bar.dart';
import '../models.dart'; // 包含 AIProvider 和 AppMode 枚举
import '../recording_provider.dart'; // 放在其他导入之后，避免冲突
import '../services/tts_service.dart';
import '../services/diagnostic_log_service.dart';
import '../services/note_navigation_service.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isSummaryPanelExpanded = false;

  String _historyFilterFor(RecordingProvider provider) =>
      provider.currentSessionMode == AppMode.freeTalk ? 'freetalk' : 'notes';

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
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) =>
          _SettingsDialog(provider: context.read<RecordingProvider>()),
    );
  }

  /// 从 MD 全文中提取"中文全文"或"中文翻译"节下的纯文本正文（不含标题和符号）
  String _extractChineseOnly(String fullText) {
    final lines = fullText.split('\n');
    bool inSection = false;
    final captured = <String>[];
    for (final line in lines) {
      final t = line.trim();
      if (t.contains('中文全文') || t.contains('中文翻译') || t.contains('Part 2')) {
        inSection = true;
        continue;
      }
      if (inSection &&
          (t.startsWith('### ') || t.startsWith('## ') || t.startsWith('# '))) {
        final isContinuation =
            t.contains('中文全文') ||
            t.contains('中文翻译') ||
            t.contains('Part 2') ||
            t.contains('翻译');
        if (!isContinuation) break;
        continue;
      }
      if (t.startsWith('---') || t.startsWith('===')) continue;
      if (inSection && t.isNotEmpty) captured.add(t);
    }
    if (captured.isNotEmpty) return captured.join('\n\n');

    // 兜底：提取含 >=3 个汉字的行
    final chineseLines = lines.where((line) {
      final t = line.trim();
      if (t.isEmpty ||
          t.startsWith('#') ||
          t.startsWith('**') ||
          t.startsWith('---'))
        return false;
      return RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]').allMatches(t).length >= 3;
    }).toList();
    return chineseLines.join('\n\n');
  }

  /// 从 MD 全文中提取"英文全文"或"English Transcript"节下的纯文本正文（不含标题和符号）
  String _extractEnglishOnly(String fullText) {
    final lines = fullText.split('\n');
    bool inSection = false;
    final captured = <String>[];
    for (final line in lines) {
      final t = line.trim();
      if (t.contains('英文全文') ||
          t.contains('English Transcript') ||
          t.contains('English Essay') ||
          t.contains('Part 1')) {
        inSection = true;
        continue;
      }
      if (inSection &&
          (t.startsWith('### ') || t.startsWith('## ') || t.startsWith('# '))) {
        final isContinuation =
            t.contains('英文全文') ||
            t.contains('English Transcript') ||
            t.contains('English Essay') ||
            t.contains('Part 1');
        if (!isContinuation) break;
        continue;
      }
      if (t.startsWith('---') || t.startsWith('===')) continue;
      if (inSection && t.isNotEmpty) captured.add(t);
    }
    if (captured.isNotEmpty) return captured.join('\n\n');

    // 兜底：提取纯英文行（不含汉字）
    final englishLines = lines.where((line) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#') || t.startsWith('---')) return false;
      final cjk = RegExp(r'[\u4e00-\u9fff\u3400-\u4dbf]').allMatches(t).length;
      return cjk == 0 && t.contains(RegExp(r'[a-zA-Z]'));
    }).toList();
    return englishLines.join('\n\n');
  }

  void _showFinalReviewModalWithContent(BuildContext context, String content) {
    final provider = Provider.of<RecordingProvider>(context, listen: false);

    // 从 MD content 中提取出纯中文和纯英文 Script，不包含标题、Markdown 符号等
    String chineseForTts;
    String englishForTts;

    if (provider.bilingualTtsText.isNotEmpty) {
      // 从 provider 拿到结构化的双语文本时，自己拆分
      final bText = provider.bilingualTtsText;
      final zhIdx = bText.indexOf('中文全文：');
      final enIdx = bText.indexOf('英文全文：');
      if (zhIdx >= 0 && enIdx > zhIdx) {
        chineseForTts = bText.substring(zhIdx + 4, enIdx).trim();
        englishForTts = bText.substring(enIdx + 4).trim();
      } else if (zhIdx >= 0) {
        chineseForTts = bText.substring(zhIdx + 4).trim();
        englishForTts = '';
      } else {
        chineseForTts = '';
        englishForTts = bText.trim();
      }
    } else {
      // 兜底：从 MD 原文中按节提取，完全不含标题/符号
      chineseForTts = _extractChineseOnly(content);
      englishForTts = _extractEnglishOnly(content);
    }

    Timer? scrollTimer;
    Timer? resumeTimer;
    bool isAutoScrolling = true;
    bool _timerStarted = false;
    bool _playerExpanded = false;
    Timer? _playerAutoHideTimer;

    Timer _startScrollTimer(
      ScrollController controller, {
      required void Function(void Function()) setModalState,
    }) {
      return Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!controller.hasClients) {
          timer.cancel();
          return;
        }
        final maxScroll = controller.position.maxScrollExtent;
        if (maxScroll <= 0) return;
        const ticksPerScreen =
            60 * 1000 ~/ 50; // 1200 ticks @ 50ms = 60s per viewport
        final increment =
            controller.position.viewportDimension / ticksPerScreen;
        final currentScroll = controller.position.pixels;
        if (currentScroll >= maxScroll) {
          controller.jumpTo(0);
          return;
        }
        controller.jumpTo((currentScroll + increment).clamp(0.0, maxScroll));
      });
    }

    void _toggleAutoScrollVia(
      Offset downPos,
      Offset upPos,
      ScrollController ctrl,
      void Function(void Function()) sms,
    ) {
      if ((upPos - downPos).distance > 10.0) return;
      sms(() {
        isAutoScrolling = !isAutoScrolling;
        if (isAutoScrolling) {
          resumeTimer?.cancel();
          resumeTimer = null;
          scrollTimer?.cancel();
          scrollTimer = _startScrollTimer(ctrl, setModalState: sms);
        } else {
          scrollTimer?.cancel();
          scrollTimer = null;
          resumeTimer?.cancel();
          resumeTimer = Timer(
            Duration(seconds: provider.autoScrollPauseDuration),
            () {
              sms(() {
                if (!isAutoScrolling) {
                  isAutoScrolling = true;
                  scrollTimer = _startScrollTimer(ctrl, setModalState: sms);
                }
              });
            },
          );
        }
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            if (!_timerStarted && scrollController.hasClients) {
              _timerStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                scrollTimer = _startScrollTimer(
                  scrollController,
                  setModalState: setModalState,
                );
              });
            }

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _toggleAutoScrollVia(
                        const Offset(0, 0),
                        const Offset(0, 0),
                        scrollController,
                        setModalState,
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      color: isAutoScrolling
                          ? Colors.blue.withOpacity(0.08)
                          : Colors.orange.withOpacity(0.08),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isAutoScrolling
                                ? Icons.keyboard_double_arrow_down
                                : Icons.pause_circle_outline,
                            size: 14,
                            color: isAutoScrolling
                                ? Colors.blueAccent[200]
                                : Colors.orange[300],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isAutoScrolling
                                ? '⏬ 自动滚屏中 · 点击暂停'
                                : '⏸ 已暂停 · ${provider.autoScrollPauseDuration}秒后自动恢复',
                            style: TextStyle(
                              fontSize: 11,
                              color: isAutoScrolling
                                  ? Colors.blueAccent[200]
                                  : Colors.orange[300],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (provider.identifiedLectureContext != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: const Color(0xFFFF9800).withOpacity(0.15),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.radar,
                            size: 16,
                            color: Color(0xFFFF9800),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Radar: ${provider.identifiedLectureContext}",
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF9800),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  Expanded(
                    child: NotificationListener<UserScrollNotification>(
                      onNotification: (notification) {
                        if (isAutoScrolling) {
                          _toggleAutoScrollVia(
                            const Offset(0, 0),
                            const Offset(0, 0),
                            scrollController,
                            setModalState,
                          );
                        }
                        return false;
                      },
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(24),
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                provider.currentSessionMode ==
                                        AppMode.discussion
                                    ? 'DISCUSSION SUMMARY'
                                    : provider.currentSessionMode ==
                                          AppMode.exam
                                    ? 'EXAM RECAP'
                                    : 'ACADEMIC RECAP',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                  color:
                                      provider.currentSessionMode ==
                                          AppMode.discussion
                                      ? Colors.deepPurpleAccent
                                      : Colors.blueAccent,
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setModalState(() {
                                _playerExpanded = !_playerExpanded;
                                if (_playerExpanded) {
                                  _playerAutoHideTimer?.cancel();
                                  _playerAutoHideTimer = Timer(
                                    const Duration(seconds: 30),
                                    () {
                                      setModalState(
                                        () => _playerExpanded = false,
                                      );
                                    },
                                  );
                                } else {
                                  _playerAutoHideTimer?.cancel();
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _playerExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.headphones,
                                    size: 14,
                                    color: Colors.blueAccent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _playerExpanded ? '点击收起播放器' : '🎧 TTS 播放器',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_playerExpanded) ...[
                            const SizedBox(height: 8),
                            TtsPlayerBar(
                              chineseText: chineseForTts,
                              englishText: englishForTts,
                              openRouterKey: provider.openRouterKey,
                            ),
                          ],
                          const SizedBox(height: 12),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              _toggleAutoScrollVia(
                                const Offset(0, 0),
                                const Offset(0, 0),
                                scrollController,
                                setModalState,
                              );
                            },
                            child: MarkdownBody(
                              data: content,
                              softLineBreak: true,
                              styleSheet: getAcademicMarkdownStyle(context),
                              selectable: false,
                              extensionSet: md.ExtensionSet(
                                [const md.FencedCodeBlockSyntax()],
                                [md.EmojiSyntax(), HighlightSyntax()],
                              ),
                              builders: {
                                'highlight': HighlightBuilder(context),
                              },
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).whenComplete(() {
      scrollTimer?.cancel();
      resumeTimer?.cancel();
      _playerAutoHideTimer?.cancel();
      TtsService().stop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recordingControlColor = isDark
        ? const Color(0xFF555563)
        : Colors.grey.shade600;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Jeff Notes',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                if (provider.isRecording)
                  Row(
                    children: [
                      // 录音状态标签：暂停中显示橙色 PAUSED，录音中显示蓝色 TRACKING
                      if (provider.isPaused)
                        const Text(
                          'PAUSED',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.orange,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        )
                      else
                        Text(
                          'TRACKING',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.blueAccent[200],
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      if (!provider.isPaused &&
                          provider.statusMessage != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• ${provider.statusMessage}',
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.white54,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ],
        ),
        actions: [
          // 暂停/继续按鈕：仅在录音中显示
          if (provider.isRecording)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton.filled(
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await provider.togglePause();
                },
                icon: Icon(
                  provider.isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  color: Colors.white,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: recordingControlColor,
                ),
                tooltip: provider.isPaused ? '继续录音' : '暂停录音',
              ),
            ),
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
                backgroundColor: recordingControlColor,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HistoryScreen(
                  initialModuleFilter: _historyFilterFor(provider),
                ),
              ),
            ),
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
          if (provider.isProcessingRecording ||
              provider.processingErrorMessage != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color:
                    (provider.processingErrorMessage == null
                            ? Colors.blueAccent
                            : Colors.redAccent)
                        .withOpacity(isDark ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      (provider.processingErrorMessage == null
                              ? Colors.blueAccent
                              : Colors.redAccent)
                          .withOpacity(isDark ? 0.4 : 0.24),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: provider.processingErrorMessage == null
                        ? const CircularProgressIndicator(strokeWidth: 2.5)
                        : const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 22,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.processingErrorMessage == null
                              ? '讲座处理中 · 第 ${provider.processingStep}/${RecordingProvider.processingStepCount} 步'
                              : '讲座处理没有完整完成',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          provider.processingErrorMessage ??
                              provider.statusMessage ??
                              '正在处理录音内容',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        if (provider.processingErrorMessage == null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: provider.processingProgress,
                              minHeight: 5,
                              backgroundColor: Colors.blueAccent.withOpacity(
                                0.12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (provider.lastReadyNotePath != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  final path = provider.lastReadyNotePath;
                  if (path == null) return;
                  final opened = await NoteNavigationService.instance.openNote(
                    path: path,
                    documentId: provider.lastReadySessionId ?? path,
                  );
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('最新保存文档不存在或尚未写入完成')),
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 38,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.blueAccent.withOpacity(0.24),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        color: Colors.blueAccent,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '打开最新保存文档',
                          style: TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.blueAccent,
                        size: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Consumer<RecordingProvider>(
            builder: (context, provider, _) => provider.hasRecoveredCache
                ? Container(
                    width: double.infinity,
                    color: Colors.blue.withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.restore, color: Colors.blue),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            "Unfinished lecture found. Recover?",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                          onPressed: () => provider.dismissRecovery(),
                          child: const Text(
                            "Dismiss",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => provider.recoverFromCache(),
                          child: const Text("Recover"),
                        ),
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
              final isAcademic =
                  provider.currentSessionMode != AppMode.discussion &&
                  provider.currentSessionMode != AppMode.freeTalk;
              final isExpanded = _isSummaryPanelExpanded;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                constraints: BoxConstraints(
                  maxHeight: isExpanded
                      ? MediaQuery.of(context).size.height * 0.3
                      : 48.0,
                ),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey[900]?.withOpacity(0.95)
                      : Colors.grey[50]?.withOpacity(0.95),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      offset: const Offset(0, 4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isSummaryPanelExpanded = !_isSummaryPanelExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isAcademic ? Icons.school : Icons.forum,
                                  size: 14,
                                  color: isAcademic
                                      ? Colors.blueAccent[200]
                                      : Colors.deepPurpleAccent[200],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isAcademic
                                      ? 'LATEST ACADEMIC INSIGHT'
                                      : 'DISCUSSION SNAPSHOT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: isAcademic
                                        ? Colors.blueAccent[200]
                                        : Colors.deepPurpleAccent[200],
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
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
                            styleSheet: getAcademicMarkdownStyle(context)
                                .copyWith(
                                  p: const TextStyle(fontSize: 14, height: 1.3),
                                  strong: TextStyle(
                                    color: isAcademic
                                        ? Colors.blueAccent[200]
                                        : Colors.deepPurpleAccent[200],
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
                if (next.transcripts.isNotEmpty &&
                    prev.transcripts.isNotEmpty) {
                  final prevMap = {
                    for (final n in prev.transcripts) n.id: n.translatedContent,
                  };
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
                        Icon(
                          Icons.mic_none,
                          size: 48,
                          color: isDark ? Colors.white10 : Colors.black12,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ready for Lecture',
                          style: TextStyle(
                            color: isDark ? Colors.white24 : Colors.black12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextButton.icon(
                          icon: Icon(
                            Icons.history_edu,
                            size: 18,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          label: Text(
                            '查看历史记录',
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HistoryScreen(
                                  initialModuleFilter: _historyFilterFor(
                                    provider,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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
                                  color: isDark
                                      ? Colors.white.withOpacity(0.9)
                                      : Colors.black87,
                                ),
                              ),
                              if (note.translatedContent != null &&
                                  note.translatedContent!.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  note.translatedContent!,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
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
        isPaused: provider.isPaused,
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
  late AppMode _tempMode;
  late PathwaysUnit _tempUnit;
  late int _tempDuration;
  late bool _tempIsDarkMode;
  late bool _tempEnableFinalRecap;
  late bool _tempEnableLectureDiscovery;
  late TextEditingController _groqController;
  late TextEditingController _openRouterController;
  late TextEditingController _geminiController;

  bool _obscureGroq = true;
  bool _obscureOpenRouter = true;
  bool _obscureGemini = true;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _tempMode = p.appMode;
    _tempUnit = p.currentUnit;
    _tempDuration = p.sliceDuration.clamp(5, 8);
    _tempIsDarkMode = p.isDarkMode;
    _tempEnableFinalRecap = p.enableFinalRecap;
    _tempEnableLectureDiscovery = p.enableLectureDiscovery;
    _groqController = TextEditingController(text: p.groqKey);
    _openRouterController = TextEditingController(text: p.openRouterKey);
    _geminiController = TextEditingController(text: p.geminiKey);
  }

  @override
  void dispose() {
    _groqController.dispose();
    _openRouterController.dispose();
    _geminiController.dispose();
    super.dispose();
  }

  void _save() {
    widget.provider.updateSettings(
      groqKey: _groqController.text,
      openRouterKey: _openRouterController.text,
      geminiKey: _geminiController.text,
      mode: _tempMode,
      unit: _tempUnit,
      duration: _tempDuration,
      isDarkMode: _tempIsDarkMode,
      enableFinalRecap: _tempEnableFinalRecap,
      enableLectureDiscovery: _tempEnableLectureDiscovery,
    );
    if (mounted) Navigator.pop(context);
  }

  void _cancel() {
    if (mounted) Navigator.pop(context);
  }

  String _unitLabel(PathwaysUnit u) {
    switch (u) {
      case PathwaysUnit.none:
        return '通用模式（无课本绑定）';
      case PathwaysUnit.unit1:
        return 'Unit 1: 消费心理学';
      case PathwaysUnit.unit2:
        return 'Unit 2: 基因科学';
      case PathwaysUnit.unit3:
        return 'Unit 3: 人口迁徙';
      case PathwaysUnit.unit4:
        return 'Unit 4: 气候变化';
      case PathwaysUnit.unit5:
        return 'Unit 5: 成功与领导力';
      case PathwaysUnit.unit6:
        return 'Unit 6: 设计思维';
      case PathwaysUnit.unit7:
        return 'Unit 7: 生态保护';
      case PathwaysUnit.unit8:
        return 'Unit 8: 传统与现代医学';
      case PathwaysUnit.unit9:
        return 'Unit 9: 考古与历史';
      case PathwaysUnit.unit10:
        return 'Unit 10: 情感与情绪';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: const Text('Settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              value: _tempDuration,
              decoration: const InputDecoration(labelText: 'STT Frequency'),
              items: [5, 6, 7, 8]
                  .map(
                    (d) =>
                        DropdownMenuItem(value: d, child: Text('$d seconds')),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _tempDuration = val);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AppMode>(
              value: _tempMode,
              decoration: const InputDecoration(labelText: 'Recording Mode'),
              items: AppMode.values
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(
                        m == AppMode.exam
                            ? '📝 Exam Listening'
                            : m == AppMode.lecture
                            ? '🎓 Academic Lecture'
                            : m == AppMode.discussion
                            ? '👥 Group Discussion'
                            : 'Free Talk',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _tempMode = val);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PathwaysUnit>(
              value: _tempUnit,
              decoration: const InputDecoration(labelText: 'Pathways Unit'),
              items: PathwaysUnit.values
                  .map(
                    (u) =>
                        DropdownMenuItem(value: u, child: Text(_unitLabel(u))),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _tempUnit = val);
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Dark Mode'),
              value: _tempIsDarkMode,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) => setState(() => _tempIsDarkMode = val),
            ),
            SwitchListTile(
              title: const Text('Final Academic Recap'),
              subtitle:
                  (_tempMode == AppMode.exam || _tempMode == AppMode.lecture)
                  ? const Text(
                      'Always enabled for Exam and Lecture first-listening notes',
                    )
                  : null,
              value: _tempMode == AppMode.exam || _tempMode == AppMode.lecture
                  ? true
                  : _tempEnableFinalRecap,
              contentPadding: EdgeInsets.zero,
              onChanged:
                  _tempMode == AppMode.exam || _tempMode == AppMode.lecture
                  ? null
                  : (val) => setState(() => _tempEnableFinalRecap = val),
            ),
            SwitchListTile(
              title: const Text('Academic Radar (Discovery)'),
              value: _tempEnableLectureDiscovery,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) =>
                  setState(() => _tempEnableLectureDiscovery = val),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 8),
            Text(
              'API KEYS CONFIGURATION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white60 : Colors.black54,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _groqController,
              obscureText: _obscureGroq,
              decoration: InputDecoration(
                labelText: 'Groq API Key',
                helperText: 'Required: for Whisper speech-to-text (STT)',
                helperStyle: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureGroq ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureGroq = !_obscureGroq),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _openRouterController,
              obscureText: _obscureOpenRouter,
              decoration: InputDecoration(
                labelText: 'OpenRouter API Key',
                helperText: 'Required: for Gemini translation & recap',
                helperStyle: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureOpenRouter
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscureOpenRouter = !_obscureOpenRouter),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _geminiController,
              obscureText: _obscureGemini,
              decoration: InputDecoration(
                labelText: 'Gemini API Key',
                helperText:
                    'Recommended: for Gemini 2.0 Flash HD Speech Synthesis',
                helperStyle: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureGemini ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscureGemini = !_obscureGemini),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 32),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Test diagnostic log',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Includes operation stages, session IDs, Bluetooth route types, '
              'and error types. It excludes note text, transcripts, API keys, '
              'cookies, and server response bodies.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy log'),
                  onPressed: () async {
                    final log = await DiagnosticLogService.instance
                        .readForSharing();
                    if (!context.mounted) return;
                    await Clipboard.setData(ClipboardData(text: log));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          log.isEmpty
                              ? 'The diagnostic log is empty.'
                              : 'Diagnostic log copied.',
                        ),
                      ),
                    );
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear log'),
                  onPressed: () async {
                    await DiagnosticLogService.instance.clear();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Diagnostic log cleared.')),
                    );
                  },
                ),
              ],
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
