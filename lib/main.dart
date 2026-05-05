import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'recording_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => RecordingProvider(),
      child: const JeffNotesApp(),
    ),
  );
}

class JeffNotesApp extends StatelessWidget {
  const JeffNotesApp({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    return MaterialApp(
      title: 'Jeff Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.grey, brightness: Brightness.light, primary: Colors.black, onPrimary: Colors.white, surface: Colors.white),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey, brightness: Brightness.dark, primary: Colors.white, onPrimary: Colors.black, surface: const Color(0xFF1E1E1E)),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF121212), foregroundColor: Colors.white, elevation: 0),
      ),
      themeMode: provider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const NotesScreen(),
    );
  }
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isAtBottom = true;

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 50;
    if (_isAtBottom != atBottom) {
      setState(() => _isAtBottom = atBottom);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }


  void _showSettingsDialog(BuildContext context) {
    final provider = context.read<RecordingProvider>();
    AIProvider tempProvider = provider.selectedProvider;
    int tempDuration = provider.sliceDuration;
    bool tempUseBluetooth = provider.useBluetooth;
    bool tempIsDarkMode = provider.isDarkMode;
    bool tempEnableFinalRecap = provider.enableFinalRecap;
    bool tempEnableLectureDiscovery = provider.enableLectureDiscovery;
    final TextEditingController controller = TextEditingController(text: provider.getApiKeyFor(tempProvider));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<AIProvider>(
                  value: tempProvider,
                  decoration: const InputDecoration(labelText: 'AI Provider'),
                  items: AIProvider.values.map((p) => DropdownMenuItem(value: p, child: Text(p.name.toUpperCase()))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        tempProvider = val;
                        controller.text = provider.getApiKeyFor(val);
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: tempDuration,
                  decoration: const InputDecoration(labelText: 'STT Frequency'),
                  items: [5, 8, 10, 12, 15].map((d) => DropdownMenuItem(value: d, child: Text('$d seconds'))).toList(),
                  onChanged: (val) { if (val != null) setDialogState(() => tempDuration = val); },
                ),
                const SizedBox(height: 12),
                SwitchListTile(title: const Text('Dark Mode'), value: tempIsDarkMode, contentPadding: EdgeInsets.zero, onChanged: (val) { setDialogState(() => tempIsDarkMode = val); }),
                SwitchListTile(title: const Text('Use Bluetooth Mic'), value: tempUseBluetooth, contentPadding: EdgeInsets.zero, onChanged: (val) { setDialogState(() => tempUseBluetooth = val); }),
                SwitchListTile(title: const Text('Final Academic Recap'), value: tempEnableFinalRecap, contentPadding: EdgeInsets.zero, onChanged: (val) { setDialogState(() => tempEnableFinalRecap = val); }),
                SwitchListTile(title: const Text('Academic Radar (Discovery)'), value: tempEnableLectureDiscovery, contentPadding: EdgeInsets.zero, onChanged: (val) { setDialogState(() => tempEnableLectureDiscovery = val); }),
                const SizedBox(height: 12),
                TextField(controller: controller, decoration: InputDecoration(labelText: '${tempProvider.name.toUpperCase()} API Key')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                provider.updateSettings(
                  provider: tempProvider,
                  key: controller.text,
                  duration: tempDuration,
                  useBluetooth: tempUseBluetooth,
                  isDarkMode: tempIsDarkMode,
                  enableFinalRecap: tempEnableFinalRecap,
                  enableLectureDiscovery: tempEnableLectureDiscovery,
                );
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFinalReviewModal(BuildContext context) {
    final provider = Provider.of<RecordingProvider>(context, listen: false);
    if (provider.finalReviewContent == null || provider.finalReviewContent!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Final recap still generating...")));
      return;
    }
    
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
              // [Architect: Academic Radar Banner]
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
                        const Text('ACADEMIC RECAP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.blueAccent)),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    MarkdownBody(
                      data: provider.finalReviewContent!,
                      softLineBreak: true,
                      styleSheet: getAcademicMarkdownStyle(context),
                      selectable: true,
                      extensionSet: md.ExtensionSet(
                        [const md.FencedCodeBlockSyntax()],
                        [md.EmojiSyntax(), _HighlightSyntax()],
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
                final wasRecording = provider.isRecording;
                await provider.toggleRecording();
                
                // [Architect: UX Auto-Trigger] 如果刚刚结束录音，且已经生成了复盘内容，立即弹出 Modal
                if (wasRecording && context.mounted) {
                  _showFinalReviewModal(context);
                }
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
          // [Layer 1] 影子恢复/状态栏 (如有)
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

          // [Layer 2] 固定顶栏：最新的 60s 小结
          Selector<RecordingProvider, List<InsightNote>>(
            selector: (_, p) => p.notes.where((n) => n.isSummary).toList(),
            builder: (context, summaries, _) {
              if (summaries.isEmpty) return const SizedBox.shrink();
              final latestSummary = summaries.first; // Provider 已 reversed

              return Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900]?.withOpacity(0.95) : Colors.grey[50]?.withOpacity(0.95),
                  border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(0, 4), blurRadius: 10),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: Colors.blueAccent[200]),
                          const SizedBox(width: 8),
                          Text('LATEST 60S INSIGHT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueAccent[200], letterSpacing: 1.5)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      MarkdownBody(
                        data: latestSummary.summary,
                        softLineBreak: true,
                        styleSheet: getAcademicMarkdownStyle(context).copyWith(
                          p: const TextStyle(fontSize: 14, height: 1.3),
                          strong: TextStyle(
                            color: Colors.blueAccent[200],
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // [Layer 3] 字幕滚动区
          Expanded(
            child: Consumer<RecordingProvider>(
              builder: (context, provider, _) {
                final transcripts = provider.notes.reversed.where((n) => !n.isSummary).toList();

                if (transcripts.isEmpty && !provider.isRecording) {
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
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
                  itemCount: transcripts.length,
                  itemBuilder: (context, index) {
                    final note = transcripts[index];
                    return RepaintBoundary(
                      key: ValueKey(note.id),
                      child: Padding(
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
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


MarkdownStyleSheet getAcademicMarkdownStyle(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final baseColor = isDark ? Colors.grey[300] : Colors.black87;
  final titleColor = isDark ? Colors.white : Colors.black;

  return MarkdownStyleSheet(
    p: TextStyle(fontSize: 20, height: 1.6, color: baseColor),
    h1: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: titleColor),
    h2: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: titleColor, height: 1.4),
    h3: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: titleColor, height: 1.4),
    listBullet: TextStyle(fontSize: 20, color: isDark ? Colors.blue[300] : Colors.blueAccent),
    strong: TextStyle(fontWeight: FontWeight.bold, color: titleColor, fontSize: 20),
    blockSpacing: 20.0,
    code: TextStyle(
      backgroundColor: Colors.transparent, 
      color: titleColor,
      fontSize: 18,
    ),
    listIndent: 30.0,
    tableBorder: TableBorder.all(color: isDark ? Colors.white24 : Colors.black12),
    tableBody: TextStyle(fontSize: 18, color: baseColor),
    tableHead: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor),
  );
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<FileSystemEntity> _files = [];
  bool _isLoading = true;
  @override
  void initState() { super.initState(); _loadFiles(); }
  Future<void> _loadFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync().where((f) => f.path.endsWith('.md')).toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      if (mounted) setState(() { _files = files; _isLoading = false; });
    } catch (e) {
      debugPrint("Load History Error: $e");
      if (mounted) setState(() { _isLoading = false; });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lecture History')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('No recorded lectures found'))
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    return ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: Text(file.path.split('/').last),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NoteDetailScreen(file: File(file.path)))),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await file.delete(); _loadFiles(); }),
                    );
                  },
                ),
    );
  }
}

class NoteDetailScreen extends StatelessWidget {
  final File file;
  const NoteDetailScreen({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(file.path.split('/').last),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              try {
                final content = await file.readAsString();
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
              } catch (e) {
                debugPrint("Copy Error: $e");
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: file.readAsString(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error loading file: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
            children: [
              MarkdownBody(
                data: snapshot.data!,
                selectable: true,
                softLineBreak: true,
                styleSheet: getAcademicMarkdownStyle(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

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
                        [md.EmojiSyntax(), _HighlightSyntax()],
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

/// [Architect: Custom Syntax] 为 ==考点== 提供渲染支持
class _HighlightSyntax extends md.InlineSyntax {
  _HighlightSyntax() : super(r'==(.+?)==');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('highlight', match[1]!));
    return true;
  }
}

class HighlightBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  HighlightBuilder(this.context);
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(isDark ? 0.4 : 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        element.textContent,
        style: TextStyle(
          color: isDark ? Colors.orange[300] : Colors.deepOrange[900],
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}
