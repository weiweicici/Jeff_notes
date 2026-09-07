import 'package:flutter/material.dart';

class NaitPackPlayerBar extends StatelessWidget {
  final int weekNumber;
  final String packAudioPath;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback? onRebuildPack;

  const NaitPackPlayerBar({
    super.key,
    required this.weekNumber,
    required this.packAudioPath,
    required this.isPlaying,
    required this.onPlay,
    required this.onStop,
    this.onRebuildPack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.headphones,
              color: colorScheme.onPrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Week $weekNumber Original Listening Pack',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPlaying ? 'Playing weekly classroom pack...' : 'Complete week review audio',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filled(
            icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
            onPressed: isPlaying ? onStop : onPlay,
          ),
          if (onRebuildPack != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Re-consolidate Pack',
              onPressed: onRebuildPack,
            ),
          ],
        ],
      ),
    );
  }
}
