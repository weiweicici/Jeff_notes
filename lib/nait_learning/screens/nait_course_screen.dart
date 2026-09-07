import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/nait_course.dart';
import '../nait_learning_provider.dart';
import 'nait_week_screen.dart';
import 'nait_english_bank_screen.dart';

class NaitCourseScreen extends StatefulWidget {
  final NaitCourse course;

  const NaitCourseScreen({super.key, required this.course});

  @override
  State<NaitCourseScreen> createState() => _NaitCourseScreenState();
}

class _NaitCourseScreenState extends State<NaitCourseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NaitLearningProvider>().selectCourse(widget.course.id);
    });
  }

  void _showAddWeekDialog() {
    final provider = context.read<NaitLearningProvider>();
    final nextWeekNum = (provider.weeks.isNotEmpty)
        ? provider.weeks.map((w) => w.weekNumber).reduce((a, b) => a > b ? a : b) + 1
        : 1;

    final controller = TextEditingController(text: '$nextWeekNum');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Week'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Week Number',
            hintText: 'e.g. 1, 2, 3...',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final numVal = int.tryParse(controller.text.trim());
              if (numVal != null && numVal > 0) {
                Navigator.pop(ctx);
                await provider.createWeek(
                  courseId: widget.course.id,
                  weekNumber: numVal,
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditCourseDialog() {
    final codeCtrl = TextEditingController(text: widget.course.courseCode);
    final nameCtrl = TextEditingController(text: widget.course.displayName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Course'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Course Code'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Display Name'),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final code = codeCtrl.text.trim();
              final name = nameCtrl.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(ctx);
                await context.read<NaitLearningProvider>().updateCourse(
                  courseId: widget.course.id,
                  courseCode: code,
                  displayName: name,
                );
                setState(() {});
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCourse() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Course?'),
        content: Text(
          'Are you sure you want to delete ${widget.course.courseCode} (${widget.course.displayName}) and all its weeks, classes, transcripts, and audio clips? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<NaitLearningProvider>().deleteCourse(widget.course.id);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<NaitLearningProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.courseCode),
        actions: [
          IconButton(
            icon: const Icon(Icons.school_outlined),
            tooltip: 'Course English Bank',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NaitEnglishBankScreen(courseId: widget.course.id),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'edit') _showEditCourseDialog();
              if (val == 'delete') _confirmDeleteCourse();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit Course')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete Course', style: TextStyle(color: colorScheme.error)),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.loadWeeksForSelectedCourse(),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.course.displayName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Weeks & Lecture Sessions',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (provider.weeks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.calendar_view_week,
                      size: 64,
                      color: colorScheme.outline.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Weeks Added Yet',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap "+ Add Week" to create Week 1.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _showAddWeekDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Week 1'),
                    ),
                  ],
                ),
              )
            else
              ...provider.weeks.map((week) {
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withOpacity(0.4),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'W${week.weekNumber}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    title: Text(
                      'Week ${week.weekNumber}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      week.packAudioPath != null
                          ? 'Listening pack ready · Tap to open'
                          : 'Classes & listening clips',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      provider.selectWeek(week.weekNumber);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NaitWeekScreen(
                            course: widget.course,
                            week: week,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddWeekDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Week'),
      ),
    );
  }
}
