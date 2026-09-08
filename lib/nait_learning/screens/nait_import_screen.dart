import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/nait_course.dart';
import '../nait_learning_provider.dart';
import 'nait_class_screen.dart';

class NaitImportScreen extends StatefulWidget {
  final NaitCourse course;
  final int weekNumber;

  const NaitImportScreen({
    super.key,
    required this.course,
    required this.weekNumber,
  });

  @override
  State<NaitImportScreen> createState() => _NaitImportScreenState();
}

class _NaitImportScreenState extends State<NaitImportScreen> {
  DateTime _classDate = DateTime.now();
  File? _selectedAudioFile;
  File? _selectedTranscriptFile;
  String? _errorMessage;

  Future<void> _pickClassDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _classDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _classDate = picked);
    }
  }

  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'm4a', 'mp3', 'wav'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedAudioFile = File(result.files.single.path!);
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error selecting audio: $e');
    }
  }

  Future<void> _pickTranscriptFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'json'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedTranscriptFile = File(result.files.single.path!);
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error selecting transcript: $e');
    }
  }

  Future<void> _processClass() async {
    if (_selectedAudioFile == null) {
      setState(() => _errorMessage = 'Please select an audio file (MP4, M4A, MP3, or WAV)');
      return;
    }
    if (_selectedTranscriptFile == null) {
      setState(() => _errorMessage = 'Please select a transcript file (Meetily TXT or MD)');
      return;
    }

    setState(() => _errorMessage = null);
    final provider = context.read<NaitLearningProvider>();

    try {
      final session = await provider.importAndProcessClass(
        courseId: widget.course.id,
        weekNumber: widget.weekNumber,
        classDate: _classDate,
        audioSource: _selectedAudioFile!,
        transcriptSource: _selectedTranscriptFile!,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => NaitClassScreen(
              course: widget.course,
              session: session,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<NaitLearningProvider>();

    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateStr = '${months[_classDate.month - 1]} ${_classDate.day}, ${_classDate.year}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Import Class · Week ${widget.weekNumber}'),
      ),
      body: provider.isProcessing
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(
                      provider.processingMessage.isNotEmpty
                          ? provider.processingMessage
                          : 'Processing Class Session...',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Extracting Must Do, Lab steps, and North-American classroom English...',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Class Date Selector
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Class Date'),
                    subtitle: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: _pickClassDate,
                  ),
                ),
                const SizedBox(height: 16),

                // Audio File Picker Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: _selectedAudioFile != null
                          ? colorScheme.primary
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.audiotrack,
                              color: _selectedAudioFile != null ? colorScheme.primary : colorScheme.outline,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Original Recording',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'MP4 · M4A · MP3 · WAV',
                                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_selectedAudioFile != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.basename(_selectedAudioFile!.path),
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                _formatFileSize(_selectedAudioFile!.lengthSync()),
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        OutlinedButton.icon(
                          onPressed: _pickAudioFile,
                          icon: const Icon(Icons.file_upload_outlined, size: 18),
                          label: Text(_selectedAudioFile != null ? 'Change Audio' : 'Select Audio File'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Transcript File Picker Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: _selectedTranscriptFile != null
                          ? colorScheme.primary
                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.description_outlined,
                              color: _selectedTranscriptFile != null ? colorScheme.primary : colorScheme.outline,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Meetily Transcript',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'TXT · MD · JSON',
                                style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_selectedTranscriptFile != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.basename(_selectedTranscriptFile!.path),
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                _formatFileSize(_selectedTranscriptFile!.lengthSync()),
                                style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        OutlinedButton.icon(
                          onPressed: _pickTranscriptFile,
                          icon: const Icon(Icons.file_upload_outlined, size: 18),
                          label: Text(
                            _selectedTranscriptFile != null ? 'Change Transcript' : 'Select Transcript File',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _processClass,
                  icon: const Icon(Icons.bolt),
                  label: const Text('Process Class Session', style: TextStyle(fontSize: 16)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
    );
  }
}
