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

late MyAudioHandler globalAudioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class JeffNotesApp extends StatelessWidget {
  const JeffNotesApp({super.key});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    return MaterialApp(
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
          surface: Colors.white
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white, 
          foregroundColor: Colors.black, 
          elevation: 0
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
          surface: const Color(0xFF1E1E1E)
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212), 
          foregroundColor: Colors.white, 
          elevation: 0
        ),
      ),
      themeMode: provider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const AcademicHubScreen(),
    );
  }
}
