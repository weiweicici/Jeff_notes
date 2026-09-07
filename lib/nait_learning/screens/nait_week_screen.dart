import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/nait_course.dart';
import '../models/nait_week.dart';
import '../models/nait_class_session.dart';
import '../nait_learning_provider.dart';
import '../widgets/nait_class_card.dart';
import '../widgets/nait_pack_player_bar.dart';
import 'nait_class_screen.dart';
import 'nait_import_screen.dart';

class NaitWeekScreen extends StatefulWidget {
  final NaitCourse course;
  final NaitWeek week;

  const NaitWeekScreen({
    super.key,
    required this.course,
    required this.week,
  });

  @override
  State<NaitWeekScreen> createState() => _NaitWeekScreenState();
}

class _NaitWeekScreenState extends State<NaitWeekScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NaitLearningProvider>().selectWeek(widget.week.weekNumber);
    });
  }

  void _confirmDeleteSession(NaitClassSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Class Session?'),
        content: Text(
          'Delete class on ${session.displayDate}? This will remove its transcript, normalized audio, listening clips, and analysis JSON. Original audio copy will also be removed from the session folder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<NaitLearningProvider>().deleteSession(session.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteWeek() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Week?'),
        content: Text(
          'Are you sure you want to delete Week ${widget.week.weekNumber} and all its class sessions? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<NaitLearningProvider>().deleteWeek(
                widget.course.id,
                widget.week.weekNumber,
              );
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleConsolidate() async {
    final provider = context.read<NaitLearningProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Consolidating week and building listening pack...')),
    );
    try {
      final res = await provider.consolidateWeek(widget.week.weekNumber);
      if (mounted) {
        if (res?.listeningPackPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Weekly Listening Pack ready!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Consolidation complete (no audio clips available yet).')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Consolidation failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<NaitLearningProvider>();

    final week = provider.weeks.firstWhere(
      (w) => w.weekNumber == widget.week.weekNumber,
      orElse: () => widget.week,
    );

    final isPlayingPack = provider.currentlyPlayingPath == week.packAudioPath &&
        week.packAudioPath != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.course.courseCode} · Week ${widget.week.weekNumber}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'consolidate') _handleConsolidate();
              if (val == 'delete') _confirmDeleteWeek();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'consolidate',
                child: Text('Consolidate & Build Pack'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete Week', style: TextStyle(color: colorScheme.error)),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.loadSessionsForSelectedWeek(),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            // Weekly Listening Pack Player
            if (week.packAudioPath != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: NaitPackPlayerBar(
                  weekNumber: week.weekNumber,
                  packAudioPath: week.packAudioPath!,
                  isPlaying: isPlayingPack,
                  onPlay: () => provider.playAudio(week.packAudioPath!),
                  onStop: () => provider.stopAudio(),
                  onRebuildPack: _handleConsolidate,
                ),
              )
            else if (provider.sessions.any((s) => s.isProcessed))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.headphones_outlined, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Weekly Listening Pack',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Stitch top teacher clips with silence gaps',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: _handleConsolidate,
                        child: const Text('Build Pack'),
                      ),
                    ],
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Class Sessions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NaitImportScreen(
                            course: widget.course,
                            weekNumber: widget.week.weekNumber,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Class'),
                  ),
                ],
              ),
            ),

            if (provider.sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.mic_none_outlined,
                      size: 64,
                      color: colorScheme.outline.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Classes in Week ${widget.week.weekNumber}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap "+ Add Class" to import an MP4/M4A/MP3/WAV recording and Meetily transcript.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NaitImportScreen(
                              course: widget.course,
                              weekNumber: widget.week.weekNumber,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Class'),
                    ),
                  ],
                ),
              )
            else
              ...provider.sessions.map((session) {
                return NaitClassCard(
                  session: session,
                  onTap: () {
                    provider.selectSession(session.id);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NaitClassScreen(
                          course: widget.course,
                          session: session,
                        ),
                      ),
                    );
                  },
                  onRetry: () => provider.retryProcessing(session.id),
                  onDelete: () => _confirmDeleteSession(session),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NaitImportScreen(
                course: widget.course,
                weekNumber: widget.week.weekNumber,
              ),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Class'),
      ),
    );
  }
}
