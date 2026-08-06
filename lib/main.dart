import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'recording_provider.dart';
import 'screens/academic_hub_screen.dart';
import 'services/supabase_config.dart';
import 'services/file_sync_agent.dart';
import 'services/grammar_repository.dart';
import 'services/audio_handler.dart';
import 'data/grammar_content.dart';

import 'services/credential_store.dart';
import 'services/diagnostic_log_service.dart';
import 'models.dart';
import 'models/session_ready_event.dart';
import 'services/note_navigation_service.dart';
import 'services/foreground_display_service.dart';

late MyAudioHandler globalAudioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DiagnosticLogService.instance.initialize();
  await CredentialStore.instance.migrateFromSharedPreferences();
  await SupabaseConfig.init();
  await SupabaseConfig.signInAnonymously();
  GrammarRepository.setHardcodedProvider(() => GrammarContent.parts);

  globalAudioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.zhenfeng.jeffnotes.channel.audio',
      androidNotificationChannelName: 'Jeff Notes Playback',
      androidNotificationOngoing: true,
    ),
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => RecordingProvider(),
      child: const JeffNotesApp(),
    ),
  );
  FileSyncAgent.instance.start();
}

class JeffNotesApp extends StatefulWidget {
  const JeffNotesApp({super.key});

  @override
  State<JeffNotesApp> createState() => _JeffNotesAppState();
}

class _JeffNotesAppState extends State<JeffNotesApp>
    with WidgetsBindingObserver {
  StreamSubscription<SessionReadyEvent>? _readySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ForegroundDisplayService.setActive(true));
    final provider = context.read<RecordingProvider>();
    _readySubscription = provider.sessionReadyStream.listen((event) {
      unawaited(_surfaceReadyNote(provider, event));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    unawaited(ForegroundDisplayService.setActive(isForeground));
  }

  String _displayPathFor(SessionReadyEvent event) {
    if (event.mode != AppMode.exam) return event.exportPath;
    final parent = File(event.exportPath).parent.path;
    return '$parent/Jeff_速记_${event.sessionId}.md';
  }

  Future<void> _surfaceReadyNote(
    RecordingProvider provider,
    SessionReadyEvent event,
  ) async {
    if (!event.shouldPromoteReadyNote) return;

    final path = _displayPathFor(event);
    final promoted = await provider.promoteReadyNote(event, path);
    if (!promoted || !mounted) return;

    // FreeTalk should expose a persistent success/open entry without forcing
    // the reader screen on top of the user's current work.
    if (!event.shouldAutoOpen) return;

    await NoteNavigationService.instance.openNote(
      path: path,
      documentId: event.sessionId,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ForegroundDisplayService.setActive(false));
    _readySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    return MaterialApp(
      navigatorKey: NoteNavigationService.instance.navigatorKey,
      navigatorObservers: [NoteNavigationService.instance],
      title: 'Jeff Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey,
          brightness: Brightness.light,
          primary: Colors.black,
          onPrimary: Colors.white,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
          primary: Colors.white,
          onPrimary: Colors.black,
          surface: const Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      themeMode: provider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const AcademicHubScreen(),
    );
  }
}
