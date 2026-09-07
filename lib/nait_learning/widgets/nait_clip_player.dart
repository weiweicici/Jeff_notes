import 'package:flutter/material.dart';
import '../models/nait_audio_clip.dart';

class NaitClipPlayer extends StatelessWidget {
  final NaitAudioClip clip;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onStop;

  const NaitClipPlayer({
    super.key,
    required this.clip,
    required this.isPlaying,
    required this.onPlay,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final durationSec = (clip.durationMs / 1000).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPlaying ? colorScheme.primaryContainer.withOpacity(0.5) : colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPlaying ? colorScheme.primary : colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              isPlaying ? Icons.stop_circle : Icons.play_circle_fill,
              color: isPlaying ? colorScheme.primary : colorScheme.primary,
              size: 32,
            ),
            onPressed: isPlaying ? onStop : onPlay,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clip.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${durationSec}s · ${clip.phrase}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${durationSec}s',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
