import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nait_learning_provider.dart';
import '../services/nait_english_bank_service.dart';

class NaitEnglishBankScreen extends StatefulWidget {
  final String? courseId;

  const NaitEnglishBankScreen({super.key, this.courseId});

  @override
  State<NaitEnglishBankScreen> createState() => _NaitEnglishBankScreenState();
}

class _NaitEnglishBankScreenState extends State<NaitEnglishBankScreen> {
  String _searchQuery = '';
  String _filter = 'all'; // 'all', 'unlearned', 'starred'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NaitLearningProvider>().loadEnglishBank(courseId: widget.courseId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<NaitLearningProvider>();

    var items = provider.bankItems;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = items.where((item) {
        return item.phrase.toLowerCase().contains(q) ||
            item.chineseMeaning.toLowerCase().contains(q) ||
            item.context.toLowerCase().contains(q);
      }).toList();
    }

    // Apply category filter
    if (_filter == 'unlearned') {
      items = items.where((item) => !item.learned).toList();
    } else if (_filter == 'starred') {
      items = items.where((item) => item.isStarred).toList();
    }

    final learnedCount = provider.bankItems.where((i) => i.learned).length;
    final totalCount = provider.bankItems.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.courseId != null
            ? '${widget.courseId} English Bank'
            : 'NAIT English Bank'),
      ),
      body: Column(
        children: [
          // Search & Filter header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search chunks or phrases...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: colorScheme.surfaceVariant.withOpacity(0.4),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: Text('All ($totalCount)'),
                      selected: _filter == 'all',
                      onSelected: (_) => setState(() => _filter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text('Unlearned (${totalCount - learnedCount})'),
                      selected: _filter == 'unlearned',
                      onSelected: (_) => setState(() => _filter = 'unlearned'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Starred'),
                      selected: _filter == 'starred',
                      onSelected: (_) => setState(() => _filter = 'starred'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Chunks list
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 64,
                            color: colorScheme.outline.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No English Chunks Found',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Import and process class lectures to accumulate authentic North-American classroom English.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      final isPlaying = provider.currentlyPlayingPath == item.audioClipPath &&
                          item.audioClipPath != null;

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: item.learned
                                ? Colors.green.withOpacity(0.3)
                                : colorScheme.outlineVariant.withOpacity(0.4),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.phrase,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: item.learned
                                        ? colorScheme.onSurface.withOpacity(0.6)
                                        : colorScheme.primary,
                                  ),
                                ),
                              ),
                              if (item.appearanceCount > 1)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Heard ${item.appearanceCount}x',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.chineseMeaning.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.chineseMeaning,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              if (item.context.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '"${item.context}"',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.audioClipPath != null)
                                IconButton(
                                  icon: Icon(
                                    isPlaying ? Icons.stop_circle : Icons.play_circle_outline,
                                    color: colorScheme.primary,
                                  ),
                                  onPressed: () {
                                    if (isPlaying) {
                                      provider.stopAudio();
                                    } else {
                                      provider.playAudio(item.audioClipPath!);
                                    }
                                  },
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.volume_up_outlined),
                                  onPressed: () => provider.playbackService.speakText(item.phrase),
                                ),
                              IconButton(
                                icon: Icon(
                                  item.isStarred ? Icons.star : Icons.star_border,
                                  color: item.isStarred ? Colors.amber : colorScheme.onSurfaceVariant,
                                ),
                                onPressed: () {
                                  final cId = item.coursesSeen.isNotEmpty
                                      ? item.coursesSeen.first
                                      : (widget.courseId ?? '');
                                  provider.toggleChunkStarred(cId, item.id);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
