import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/nait_course.dart';
import '../models/nait_class_session.dart';
import '../nait_learning_provider.dart';
import '../widgets/nait_section_card.dart';
import '../widgets/nait_english_chunk_card.dart';
import '../widgets/nait_clip_player.dart';
import '../widgets/nait_processing_status.dart';

class NaitClassScreen extends StatefulWidget {
  final NaitCourse course;
  final NaitClassSession session;

  const NaitClassScreen({
    super.key,
    required this.course,
    required this.session,
  });

  @override
  State<NaitClassScreen> createState() => _NaitClassScreenState();
}

class _NaitClassScreenState extends State<NaitClassScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<NaitLearningProvider>();

    final session = provider.sessions.firstWhere(
      (s) => s.id == widget.session.id,
      orElse: () => widget.session,
    );

    final analysis = session.analysis;
    final clips = session.clips;

    // Build clip path map for quick chunk playback lookup
    final Map<String, String> clipPathMap = {};
    for (final clip in clips) {
      clipPathMap[clip.id] = clip.filePath;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.course.courseCode} · ${session.displayDate}'),
        actions: [
          if (session.status == NaitSessionStatus.failed)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Retry Analysis',
              onPressed: () => provider.retryProcessing(session.id),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // Processing status banner if running or failed
          if (session.isProcessing)
            NaitProcessingStatus(message: provider.processingMessage)
          else if (session.hasFailed)
            NaitProcessingStatus(
              message: '',
              isFailed: true,
              errorMessage: session.errorMessage,
              onRetry: () => provider.retryProcessing(session.id),
            ),

          if (analysis != null) ...[
            // 1. MUST DO (Highest Priority)
            if (analysis.mustDo.isNotEmpty)
              NaitSectionCard(
                title: 'Must Do',
                icon: Icons.assignment_turned_in,
                accentColor: Colors.amber.shade800,
                badgeCount: analysis.mustDo.length,
                child: Column(
                  children: analysis.mustDo.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline, size: 18, color: Colors.amber.shade800),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // 2. LAB STEPS
            if (analysis.lab.isNotEmpty)
              NaitSectionCard(
                title: 'Lab Procedures',
                icon: Icons.terminal,
                accentColor: Colors.teal,
                badgeCount: analysis.lab.length,
                child: Column(
                  children: analysis.lab.map((step) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.arrow_right, size: 20, color: Colors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              step,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // 3. IMPORTANT (Teacher Warnings)
            if (analysis.important.isNotEmpty)
              NaitSectionCard(
                title: 'Important Warnings',
                icon: Icons.warning_amber_rounded,
                accentColor: Colors.deepOrange,
                badgeCount: analysis.important.length,
                child: Column(
                  children: analysis.important.map((warn) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.priority_high, size: 18, color: Colors.deepOrange),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              warn,
                              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.deepOrange.shade900),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // 4. NEXT CLASS
            if (analysis.nextClass.isNotEmpty)
              NaitSectionCard(
                title: 'Next Class Preparation',
                icon: Icons.next_plan_outlined,
                accentColor: Colors.blue,
                badgeCount: analysis.nextClass.length,
                child: Column(
                  children: analysis.nextClass.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.calendar_month_outlined, size: 18, color: Colors.blue),
                          const SizedBox(width: 10),
                          Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // 5. CLASSROOM ENGLISH (Primary Learning Output)
            if (analysis.classroomEnglish.isNotEmpty)
              NaitSectionCard(
                title: 'Classroom English',
                icon: Icons.record_voice_over,
                accentColor: Colors.indigo,
                badgeCount: analysis.classroomEnglish.length,
                child: Column(
                  children: analysis.classroomEnglish.map((chunk) {
                    final clipPath = chunk.audioClipId != null ? clipPathMap[chunk.audioClipId] : null;
                    final isPlaying = provider.currentlyPlayingPath == clipPath && clipPath != null;

                    return NaitEnglishChunkCard(
                      chunk: chunk,
                      clipAudioPath: clipPath,
                      isPlaying: isPlaying,
                      onPlay: clipPath != null
                          ? () {
                              if (isPlaying) {
                                provider.stopAudio();
                              } else {
                                provider.playAudio(clipPath);
                              }
                            }
                          : null,
                      onSpeakTts: () => provider.playbackService.speakText(chunk.phrase),
                      onToggleLearned: () => provider.toggleChunkLearned(widget.course.id, chunk.id),
                      onToggleStarred: () => provider.toggleChunkStarred(widget.course.id, chunk.id),
                      isStarred: provider.reviewProgress?.starredChunkIds.contains(chunk.id) ?? false,
                    );
                  }).toList(),
                ),
              ),

            // 6. TECHNICAL POINTS (Collapsible)
            if (analysis.technicalPoints.isNotEmpty)
              NaitSectionCard(
                title: 'Technical Notes',
                icon: Icons.integration_instructions_outlined,
                accentColor: Colors.blueGrey,
                badgeCount: analysis.technicalPoints.length,
                initiallyExpanded: false,
                child: Column(
                  children: analysis.technicalPoints.map((pt) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.circle, size: 8, color: Colors.blueGrey),
                          const SizedBox(width: 10),
                          Expanded(child: Text(pt, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // 7. ASK THE TEACHER
            if (analysis.askTeacher.isNotEmpty)
              NaitSectionCard(
                title: 'Ask the Teacher',
                icon: Icons.help_outline,
                accentColor: Colors.purple,
                badgeCount: analysis.askTeacher.length,
                child: Column(
                  children: analysis.askTeacher.map((q) {
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purple.withOpacity(0.15)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.question_answer_outlined, size: 18, color: Colors.purple),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              q.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.volume_up_outlined, size: 18),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            onPressed: () => provider.playbackService.speakText(q.text),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // 8. TALK TO CLASSMATES
            if (analysis.classmateEnglish.isNotEmpty)
              NaitSectionCard(
                title: 'Talk to Classmates',
                icon: Icons.forum_outlined,
                accentColor: Colors.cyan.shade800,
                badgeCount: analysis.classmateEnglish.length,
                child: Column(
                  children: analysis.classmateEnglish.map((item) {
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.cyan.withOpacity(0.15)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 18, color: Colors.cyan.shade800),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.text,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.volume_up_outlined, size: 18),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            onPressed: () => provider.playbackService.speakText(item.text),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // 9. TEACHER MODE (Teach-Back Task)
            if (analysis.teacherMode != null)
              NaitSectionCard(
                title: 'Teacher Mode (60s Teach-back)',
                icon: Icons.record_voice_over_outlined,
                accentColor: Colors.deepPurple,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.deepPurple.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prompt:',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        analysis.teacherMode!.prompt,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (analysis.teacherMode!.suggestedOpening.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Suggested Opening:',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '"${analysis.teacherMode!.suggestedOpening}"',
                          style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                      if (analysis.teacherMode!.targetChunks.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Target Chunks to Use:',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: analysis.teacherMode!.targetChunks.map((chunk) {
                            return Chip(
                              label: Text(chunk, style: const TextStyle(fontSize: 12)),
                              backgroundColor: Colors.deepPurple.withOpacity(0.1),
                              padding: EdgeInsets.zero,
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // 10. ORIGINAL AUDIO CLIPS SECTION
            if (clips.isNotEmpty)
              NaitSectionCard(
                title: 'Extracted Audio Clips',
                icon: Icons.audiotrack,
                accentColor: Colors.green.shade800,
                badgeCount: clips.length,
                initiallyExpanded: false,
                child: Column(
                  children: clips.map((clip) {
                    final isPlaying = provider.currentlyPlayingPath == clip.filePath;
                    return NaitClipPlayer(
                      clip: clip,
                      isPlaying: isPlaying,
                      onPlay: () => provider.playAudio(clip.filePath),
                      onStop: () => provider.stopAudio(),
                    );
                  }).toList(),
                ),
              ),
          ] else if (!session.isProcessing) ...[
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.pending_actions, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('Class session ready to process.'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => provider.retryProcessing(session.id),
                      child: const Text('Start Processing'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
