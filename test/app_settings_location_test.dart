import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/recording_provider.dart';
import 'package:jeff_notes/screens/academic_hub_screen.dart';
import 'package:jeff_notes/services/credential_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CredentialStore.instance.setAdapter(InMemorySecureStorageAdapter());
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });

  testWidgets('global settings opens from the app home screen', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RecordingProvider(),
        child: const MaterialApp(home: AcademicHubScreen()),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('设置'), findsOneWidget);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Recording Mode'), findsOneWidget);

    final notesSource = File(
      'lib/screens/notes_screen.dart',
    ).readAsStringSync();
    expect(
      notesSource,
      isNot(contains('icon: const Icon(Icons.settings_outlined)')),
    );
  });
}
