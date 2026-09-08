import 'package:flutter/material.dart';
import '../models/nait_class_session.dart';

class NaitClassCard extends StatelessWidget {
  final NaitClassSession session;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;

  const NaitClassCard({
    super.key,
    required this.session,
    required this.onTap,
    this.onDelete,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (session.status) {
      case NaitSessionStatus.processed:
        statusColor = Colors.green;
        statusLabel = 'Processed';
        statusIcon = Icons.check_circle_outline;
        break;
      case NaitSessionStatus.processing:
      case NaitSessionStatus.importing:
        statusColor = Colors.orange;
        statusLabel = 'Processing...';
        statusIcon = Icons.hourglass_top;
        break;
      case NaitSessionStatus.partial:
        statusColor = Colors.amber.shade700;
        statusLabel = 'Partial';
        statusIcon = Icons.warning_amber_rounded;
        break;
      case NaitSessionStatus.failed:
        statusColor = Colors.red;
        statusLabel = 'Failed';
        statusIcon = Icons.error_outline;
        break;
      case NaitSessionStatus.readyToProcess:
        statusColor = Colors.blue;
        statusLabel = 'Ready to Process';
        statusIcon = Icons.play_circle_outline;
        break;
    }

    final chunkCount = session.analysis?.classroomEnglish.length ?? 0;
    final mustDoCount = session.analysis?.mustDo.length ?? 0;
    final clipCount = session.clips.length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      session.displayDate,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (session.status == NaitSessionStatus.failed && onRetry != null)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Retry Analysis',
                      onPressed: onRetry,
                    ),
                  if (onDelete != null)
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
                      tooltip: 'Delete Class',
                      onPressed: onDelete,
                    ),
                ],
              ),
              if (session.analysis != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if (mustDoCount > 0)
                      _buildPill(
                        context,
                        icon: Icons.assignment_outlined,
                        label: '$mustDoCount Must Do',
                        color: Colors.amber.shade800,
                      ),
                    if (chunkCount > 0)
                      _buildPill(
                        context,
                        icon: Icons.record_voice_over_outlined,
                        label: '$chunkCount Chunks',
                        color: Colors.indigo,
                      ),
                    if (clipCount > 0)
                      _buildPill(
                        context,
                        icon: Icons.audiotrack_outlined,
                        label: '$clipCount Audio Clips',
                        color: Colors.teal,
                      ),
                  ],
                ),
              ],
              if (session.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  session.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
