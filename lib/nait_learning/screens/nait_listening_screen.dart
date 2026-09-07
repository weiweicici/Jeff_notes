import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/nait_audio_clip.dart';
import '../nait_learning_provider.dart';

class NaitListeningScreen extends StatefulWidget {
  final String title;
  final List<NaitAudioClip> clips;
  final String? packAudioPath;

  const NaitListeningScreen({
    super.key,
    required this.title,
    required this.clips,
    this.packAudioPath,
  });

  @override
  State<NaitListeningScreen> createState() => _NaitListeningScreenState();
}

class _NaitListeningScreenState extends State<NaitListeningScreen> {
  bool _showText = false;
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<NaitLearningProvider>();

    final hasClips = widget.clips.isNotEmpty;
    final currentClip = hasClips && _currentIndex < widget.clips.length
        ? widget.clips[_currentIndex]
        : null;

    final isPlayingCurrent = currentClip != null &&
        provider.currentlyPlayingPath == currentClip.filePath;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_showText ? Icons.visibility : Icons.visibility_off),
            tooltip: _showText ? 'Hide Transcript' : 'Show Transcript',
            onPressed: () => setState(() => _showText = !_showText),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Listening Card
            Expanded(
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.headphones,
                          size: 48,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (currentClip != null) ...[
                        Text(
                          'Clip ${_currentIndex + 1} of ${widget.clips.length}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_showText) ...[
                          Text(
                            currentClip.phrase,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ] else ...[
                          Text(
                            'Blind Listening Mode',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Listen closely to the teacher\'s authentic pronunciation.\nTap eye icon to reveal.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ] else ...[
                        Text(
                          widget.packAudioPath != null
                              ? 'Weekly Listening Pack'
                              : 'No Clips Available',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: hasClips && _currentIndex > 0
                      ? () {
                          setState(() => _currentIndex--);
                          provider.playAudio(widget.clips[_currentIndex].filePath);
                        }
                      : null,
                ),
                const SizedBox(width: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(20),
                    shape: const CircleBorder(),
                  ),
                  onPressed: () {
                    if (currentClip != null) {
                      if (isPlayingCurrent) {
                        provider.stopAudio();
                      } else {
                        provider.playAudio(currentClip.filePath);
                      }
                    } else if (widget.packAudioPath != null) {
                      if (provider.currentlyPlayingPath == widget.packAudioPath) {
                        provider.stopAudio();
                      } else {
                        provider.playAudio(widget.packAudioPath!);
                      }
                    }
                  },
                  child: Icon(
                    isPlayingCurrent || provider.currentlyPlayingPath == widget.packAudioPath
                        ? Icons.stop
                        : Icons.play_arrow,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 20),
                IconButton.filledTonal(
                  icon: const Icon(Icons.skip_next),
                  onPressed: hasClips && _currentIndex < widget.clips.length - 1
                      ? () {
                          setState(() => _currentIndex++);
                          provider.playAudio(widget.clips[_currentIndex].filePath);
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
