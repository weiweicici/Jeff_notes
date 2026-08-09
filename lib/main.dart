import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'recording_provider.dart';
import 'screens/academic_hub_screen.dart';
import 'screens/grammar_writing_screen.dart';
import 'services/supabase_config.dart';
import 'services/file_sync_agent.dart';
import 'services/grammar_repository.dart';
import 'services/grammar_writing_draft_service.dart';
import 'services/audio_handler.dart';
import 'data/grammar_content.dart';

import 'services/credential_store.dart';
import 'services/diagnostic_log_service.dart';
import 'models.dart';
import 'models/session_ready_event.dart';
import 'services/note_navigation_service.dart';
import 'services/foreground_display_service.dart';
import 'services/watch_sync_service.dart';

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
      fastForwardInterval: Duration(seconds: 5),
      rewindInterval: Duration(seconds: 5),
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
  StreamSubscription<WatchGrammarWritingRequest>? _watchWritingSubscription;
  RecordingProvider? _recordingProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ForegroundDisplayService.setActive(true));
    final provider = context.read<RecordingProvider>();
    _recordingProvider = provider;
    _readySubscription = provider.sessionReadyStream.listen((event) {
      unawaited(_surfaceReadyNote(provider, event));
    });
    _watchWritingSubscription = WatchSyncService.instance.grammarWritingRequests
        .listen((request) => unawaited(_openWatchGrammarWriting(request)));
    WatchSyncService.instance.initialize();
    WatchSyncService.instance.setRecordingCommandHandler(
      (command) => _handleWatchRecordingCommand(provider, command),
    );
    WatchSyncService.instance.setGrammarConfigRequestHandler(
      _pushWatchGrammarWritingConfig,
    );
    provider.addListener(_syncWatchRecordingState);
    unawaited(_pushWatchRecordingState(provider));
    unawaited(_pushWatchGrammarWritingConfig());
  }

  Future<void> _pushWatchGrammarWritingConfig() async {
    try {
      final parts = await GrammarRepository.loadParts();
      final draft = await GrammarWritingDraftService.instance.load();
      await WatchSyncService.instance.updateGrammarWritingConfig(
        draft.toWatchPayload(parts),
      );
    } catch (error) {
      debugPrint('[WatchSync] Grammar config refresh skipped: $error');
    }
  }

  Future<void> _handleWatchRecordingCommand(
    RecordingProvider provider,
    String command,
  ) async {
    switch (command) {
      case 'armListeningRecording':
        if (!await provider.enterRecordingStandby()) {
          throw StateError(provider.statusMessage ?? '无法进入录音待命');
        }
        break;
      case 'disarmListeningRecording':
        await provider.leaveRecordingStandby();
        break;
      case 'startListeningRecording':
        if (!provider.isRecordingStandby) {
          final armed = await provider.enterRecordingStandby();
          if (!armed) {
            throw StateError(provider.statusMessage ?? '手机未能进入录音待命');
          }
        }
        await provider.startRecording();
        if (!provider.isRecording) {
          throw StateError(provider.statusMessage ?? '手机未能开始录音');
        }
        break;
      case 'stopListeningRecording':
        if (!provider.isRecording) return;
        await provider.stopRecording();
        break;
      default:
        throw UnsupportedError('Unknown Watch recording command: $command');
    }
    await _pushWatchRecordingState(provider);
  }

  void _syncWatchRecordingState() {
    final provider = _recordingProvider;
    if (provider != null) unawaited(_pushWatchRecordingState(provider));
  }

  Future<void> _pushWatchRecordingState(RecordingProvider provider) async {
    final state = provider.isRecording
        ? (provider.isPaused ? 'paused' : 'recording')
        : provider.isRecordingStandby
        ? 'standby'
        : provider.isProcessingRecording
        ? 'processing'
        : provider.processingErrorMessage != null
        ? 'error'
        : 'idle';
    await WatchSyncService.instance.updateRecordingState({
      'state': state,
      'is_standby': provider.isRecordingStandby,
      'is_recording': provider.isRecording,
      'is_paused': provider.isPaused,
      'is_processing': provider.isProcessingRecording,
      'started_at_ms': provider.recordingStartedAt?.millisecondsSinceEpoch ?? 0,
      'progress': provider.processingProgress,
      'message': provider.statusMessage ?? '',
      'error': provider.processingErrorMessage ?? '',
      'latest_english': provider.latestLiveEnglish,
      'latest_chinese': provider.latestLiveChinese,
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    unawaited(ForegroundDisplayService.setActive(isForeground));
    if (isForeground) {
      final provider = _recordingProvider;
      if (provider != null) unawaited(provider.resumeInterruptedSessions());
    }
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

  Future<void> _openWatchGrammarWriting(
    WatchGrammarWritingRequest request,
  ) async {
    if (request.requestId.isNotEmpty) {
      await WatchSyncService.instance.updateGrammarWritingState(
        requestId: request.requestId,
        state: 'accepted',
        message: '手机已收到，准备生成',
      );
    }
    // Let the current frame finish so the global Navigator is always ready,
    // including when WatchConnectivity wakes the app during startup.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final navigator = NoteNavigationService.instance.navigatorKey.currentState;
    if (navigator == null) {
      if (request.requestId.isNotEmpty) {
        await WatchSyncService.instance.updateGrammarWritingState(
          requestId: request.requestId,
          state: 'error',
          message: '手机界面尚未准备好，请稍后重试',
        );
      }
      return;
    }
    final selectionMode = switch (request.selectionMode) {
      'automatic' => GrammarWritingSelectionMode.automatic,
      'custom' => GrammarWritingSelectionMode.custom,
      _ => GrammarWritingSelectionMode.phone,
    };
    await navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/watch-grammar-writing'),
        builder: (_) => GrammarWritingScreen(
          initialTopic: request.topic,
          autoGenerate: true,
          launchOptions: GrammarWritingLaunchOptions(
            selectionMode: selectionMode,
            selectedPartIds: request.selectedPartIds,
            selectedUnitIds: request.selectedUnitIds,
            contentType: request.contentType,
            requireAllSelectedGrammar: request.requireAllSelectedGrammar,
            requestId: request.requestId,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ForegroundDisplayService.setActive(false));
    _readySubscription?.cancel();
    _watchWritingSubscription?.cancel();
    _recordingProvider?.removeListener(_syncWatchRecordingState);
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
