import 'package:flutter/material.dart';
import '../models/nait_english_chunk.dart';

class NaitEnglishChunkCard extends StatelessWidget {
  final NaitEnglishChunk chunk;
  final String? clipAudioPath;
  final bool isPlaying;
  final VoidCallback? onPlay;
  final VoidCallback? onSpeakTts;
  final VoidCallback? onToggleLearned;
  final VoidCallback? onToggleStarred;
  final bool isStarred;

  const NaitEnglishChunkCard({
    super.key,
    required this.chunk,
    this.clipAudioPath,
    this.isPlaying = false,
    this.onPlay,
    this.onSpeakTts,
    this.onToggleLearned,
    this.onToggleStarred,
    this.isStarred = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: chunk.learned
              ? Colors.green.withOpacity(0.3)
              : colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chunk.phrase,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: chunk.learned
                              ? colorScheme.onSurface.withOpacity(0.7)
                              : colorScheme.primary,
                        ),
                      ),
                      if (chunk.chineseMeaning.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          chunk.chineseMeaning,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onToggleStarred != null)
                  IconButton(
                    icon: Icon(
                      isStarred ? Icons.star : Icons.star_border,
                      color: isStarred ? Colors.amber : colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    onPressed: onToggleStarred,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
              ],
            ),
            if (chunk.context.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '"${chunk.context}"',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                // Source badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: chunk.sourceType == 'teacher_original'
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    chunk.sourceType == 'teacher_original' ? 'Teacher Original' : 'Practice',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: chunk.sourceType == 'teacher_original'
                          ? Colors.blue.shade700
                          : Colors.purple.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
                if (chunk.appearanceCount > 1) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Heard in ${chunk.appearanceCount} classes',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
                if (chunk.sourceTimestamp != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '[${NaitEnglishChunk.formatDuration(chunk.sourceTimestamp)}]',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                      fontSize: 10,
                    ),
                  ),
                ],
                const Spacer(),
                // Star rating (1-5)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    chunk.priority.clamp(1, 5),
                    (index) => const Icon(Icons.star, size: 12, color: Colors.amber),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                if (clipAudioPath != null && onPlay != null)
                  FilledButton.tonalIcon(
                    onPressed: onPlay,
                    icon: Icon(
                      isPlaying ? Icons.stop : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(isPlaying ? 'Stop' : 'Teacher Audio'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: theme.textTheme.labelMedium,
                    ),
                  )
                else if (onSpeakTts != null)
                  OutlinedButton.icon(
                    onPressed: onSpeakTts,
                    icon: const Icon(Icons.volume_up, size: 18),
                    label: const Text('Listen (TTS)'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: theme.textTheme.labelMedium,
                    ),
                  ),
                const Spacer(),
                if (onToggleLearned != null)
                  TextButton.icon(
                    onPressed: onToggleLearned,
                    icon: Icon(
                      chunk.learned ? Icons.check_circle : Icons.circle_outlined,
                      size: 18,
                      color: chunk.learned ? Colors.green : colorScheme.outline,
                    ),
                    label: Text(
                      chunk.learned ? 'Learned' : 'Mark Learned',
                      style: TextStyle(
                        color: chunk.learned ? Colors.green : colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
