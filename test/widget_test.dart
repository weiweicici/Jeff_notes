import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jeff_notes/main.dart';
import 'package:jeff_notes/recording_provider.dart';
import 'package:jeff_notes/services/credential_store.dart';

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

  testWidgets('JeffNotesApp widget smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RecordingProvider(),
        child: const JeffNotesApp(),
      ),
    );

    expect(find.byType(JeffNotesApp), findsOneWidget);
  });
}
