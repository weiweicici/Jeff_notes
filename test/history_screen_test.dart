import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/screens/history_screen.dart';
import 'package:jeff_notes/services/file_sync_agent.dart';
import 'package:jeff_notes/services/note_deletion_store.dart';
import 'package:jeff_notes/services/note_library_service.dart';
import 'package:jeff_notes/services/upload_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeCloud implements HistoryCloudRepository {
  List<HistoryCloudNote> notes = [];
  final deleted = <HistoryCloudNote>[];
  Future<List<HistoryCloudNote>> Function(String)? onList;
  Future<void> Function(HistoryCloudNote)? onDelete;
  @override
  Future<List<HistoryCloudNote>> list(String ownerId) async =>
      onList != null ? onList!(ownerId) : notes;
  @override
  Future<void> delete(HistoryCloudNote note) async {
    await onDelete?.call(note);
    deleted.add(note);
  }
}

class GatedLibrary extends NoteLibraryService {
  GatedLibrary(Directory directory)
    : super(documentsDirectory: () async => directory);
  Completer<void>? importGate;
  @override
  Future<NoteLibraryItem?> importCloudNote({
    required String sessionId,
    required String content,
    required String title,
    required bool Function() allowed,
  }) async {
    if (importGate != null) await importGate!.future;
    return super.importCloudNote(
      sessionId: sessionId,
      content: content,
      title: title,
      allowed: allowed,
    );
  }
}

const session = '20260827_130412_468_468744';
HistoryCloudNote cloudNote([String id = session]) => HistoryCloudNote(
  ownerId: 'A',
  id: 'row-$id',
  sessionId: id,
  title: 'Cloud title',
  content: 'cloud content',
  modifiedAt: DateTime(2026),
);

Future<void> settle(WidgetTester tester) async {
  // Real filesystem IO is not driven by FakeAsync's clock.
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
}

void historyTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    await tester.runAsync(() => body(tester));
  });
}

void main() {
  late Directory directory;
  late GatedLibrary library;
  late FakeCloud cloud;
  late List<NoteLibraryItem> opened;
  String? owner;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('history_widget_');
    library = GatedLibrary(directory);
    cloud = FakeCloud();
    opened = [];
    owner = 'A';
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          library: library,
          cloudRepository: cloud,
          captureIdentity: () => owner,
          isCurrentIdentity: (id) => id == owner,
          openNote: (item) async => opened.add(item),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> deleteFirst(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await settle(tester);
    await tester.tap(find.text('删除').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await settle(tester);
  }

  Future<File> local([String id = session]) async {
    final file = File('${directory.path}/Jeff_Notes_$id.md');
    await file.writeAsString('local original');
    return file;
  }

  historyTest(
    'cloud-only note is visible and opens a materialized stable note',
    (tester) async {
      cloud.notes = [cloudNote()];
      await mount(tester);
      expect(find.text('Cloud title'), findsOneWidget);
      await tester.tap(find.text('Cloud title'));
      await settle(tester);
      expect(opened, hasLength(1));
      expect(opened.single.stableSessionId, session);
      expect(opened.single.markdownFile.readAsStringSync(), 'cloud content');
      expect(opened.single.displayTitle, 'Cloud title');
    },
  );

  historyTest(
    'stale cloud click after local move never overwrites or duplicates',
    (tester) async {
      cloud.notes = [cloudNote()];
      await mount(tester);
      await (() async {
        await local();
        await library.createFolder('', 'Course');
        final note = (await library.listNotes('')).single;
        await library.moveNote(note, 'Course');
      })();
      await tester.tap(find.text('Cloud title'));
      await settle(tester);
      expect(opened.single.relativeFolderPath, 'Course');
      expect(opened.single.markdownFile.readAsStringSync(), 'local original');
      final notes = await library.searchAllNotes('');
      expect(notes, hasLength(1));
    },
  );

  for (final replacement in <String?>['B', null]) {
    historyTest(
      'late list after identity changes to $replacement is discarded',
      (tester) async {
        final pending = Completer<List<HistoryCloudNote>>();
        cloud.onList = (_) => pending.future;
        await mount(tester);
        owner = replacement;
        pending.complete([cloudNote()]);
        await settle(tester);
        expect(find.text('Cloud title'), findsNothing);
        expect(opened, isEmpty);
      },
    );

    historyTest(
      'identity change to $replacement during download prevents file/navigation/cache',
      (tester) async {
        cloud.notes = [cloudNote()];
        library.importGate = Completer<void>();
        await mount(tester);
        await tester.tap(find.text('Cloud title'));
        await tester.pump();
        owner = replacement;
        library.importGate!.complete();
        await settle(tester);
        expect(opened, isEmpty);
        expect(await library.searchAllNotes(''), isEmpty);
        expect(await UploadCache.load(userId: 'A'), isEmpty);
        expect(await UploadCache.load(userId: 'B'), isEmpty);
      },
    );
  }

  historyTest('offline local delete succeeds', (tester) async {
    final file = await local();
    cloud.notes = [cloudNote()];
    cloud.onDelete = (_) async => throw StateError('offline');
    await mount(tester);
    await deleteFirst(tester);
    expect(file.existsSync(), isFalse);
    expect(NoteDeletionStore(directory).read(session)?['state'], 'pending');
    expect(NoteDeletionStore(directory).read(session)?['owner'], 'A');
    expect(find.text('Jeff_Notes_$session'), findsNothing);
    expect(find.text('Cloud title'), findsNothing);
  });

  historyTest('unauthenticated local-only note delete succeeds', (
    tester,
  ) async {
    owner = null;
    final file = await local();
    await mount(tester);
    await deleteFirst(tester);
    expect(file.existsSync(), isFalse);
    expect(NoteDeletionStore(directory).blocksUpload(session), isTrue);
    expect(find.text('Jeff_Notes_$session'), findsNothing);
  });

  historyTest('Markdown + WAV + sidecar all delete', (tester) async {
    final md = await local();
    final wav = File('${directory.path}/Jeff_Notes_$session.wav');
    await wav.writeAsBytes([1, 2, 3]);
    final sidecar =
        File('${directory.path}/Jeff_Notes_$session.md.jeffnotes.json');
    await sidecar.writeAsString(
      '{"stableSessionId":"$session","displayTitle":"Custom Title"}',
    );

    await mount(tester);
    await deleteFirst(tester);

    expect(md.existsSync(), isFalse);
    expect(wav.existsSync(), isFalse);
    expect(sidecar.existsSync(), isFalse);
  });

  historyTest('same owner later completes cloud deletion', (tester) async {
    final file = await local();
    cloud.notes = [cloudNote()];
    cloud.onDelete = (_) async => throw StateError('offline');
    await mount(tester);
    await deleteFirst(tester);
    expect(file.existsSync(), isFalse);
    expect(NoteDeletionStore(directory).read(session)?['state'], 'pending');

    cloud.onDelete = null;
    await tester.pumpWidget(const SizedBox());
    await mount(tester);

    expect(cloud.deleted, hasLength(1));
    expect(cloud.deleted.single.ownerId, 'A');
    expect(NoteDeletionStore(directory).read(session)?['state'], 'completed');
  });

  historyTest('different account cannot consume another owner\'s tombstone', (
    tester,
  ) async {
    await local();
    cloud.notes = [cloudNote()];
    cloud.onDelete = (_) async => throw StateError('offline');
    await mount(tester);
    await deleteFirst(tester);
    expect(NoteDeletionStore(directory).read(session)?['owner'], 'A');
    expect(NoteDeletionStore(directory).read(session)?['state'], 'pending');

    cloud.onDelete = null;
    owner = 'B';
    await tester.pumpWidget(const SizedBox());
    await mount(tester);

    expect(cloud.deleted, isEmpty);
    expect(NoteDeletionStore(directory).pendingSessionIdsFor('B'), isEmpty);
    expect(
      () => NoteDeletionStore(directory).complete('B', session),
      throwsA(isA<StateError>()),
    );
  });

  historyTest(
    'UI no longer reports deletion failure when only cloud cleanup is pending',
    (tester) async {
      await local();
      cloud.notes = [cloudNote()];
      cloud.onDelete = (_) async => throw StateError('offline');
      await mount(tester);
      await deleteFirst(tester);

      expect(find.textContaining('操作未完整完成'), findsNothing);
      expect(find.textContaining('删除未完成，请重试'), findsNothing);
    },
  );

  historyTest(
    'nonempty folder offline delete succeeds locally and removes folder',
    (tester) async {
      await library.createFolder('', 'Course');
      await library.createFolder('Course', 'Nested');
      await local();
      await library.moveNote(
        (await library.listNotes('')).single,
        'Course/Nested',
      );
      cloud.onDelete = (_) async => throw StateError('offline');
      await mount(tester);
      await deleteFirst(tester);
      expect(
        Directory('${directory.path}/JeffNotes/Course').existsSync(),
        isFalse,
      );
      expect(await library.searchAllNotes(''), isEmpty);
      expect(NoteDeletionStore(directory).read(session)?['state'], 'pending');
    },
  );

  historyTest('recovery protected notes are never marked or remotely deleted', (
    tester,
  ) async {
    final file = await local();
    await File(
      '${directory.path}/shadow_draft_test.json',
    ).writeAsString('{"exportPath":"${file.path}"}');
    await mount(tester);
    await deleteFirst(tester);
    expect(cloud.deleted, isEmpty);
    expect(NoteDeletionStore(directory).blocksUpload(session), isFalse);
    expect(file.existsSync(), isTrue);
  });

  historyTest(
    'cloud-only failed delete stays retryable and completed tombstone hides stale result',
    (tester) async {
      cloud.notes = [cloudNote()];
      cloud.onDelete = (_) async => throw StateError('offline');
      await mount(tester);
      await deleteFirst(tester);
      expect(find.text('Cloud title'), findsOneWidget);
      expect(find.textContaining('删除未完成，请重试'), findsOneWidget);
      expect(NoteDeletionStore(directory).read(session)?['state'], 'pending');
      cloud.onDelete = null;
      await deleteFirst(tester);
      expect(find.text('Cloud title'), findsNothing);
      expect(NoteDeletionStore(directory).read(session)?['state'], 'completed');
    },
  );

  historyTest(
    'folder account change after first remote delete stops remaining deletes',
    (tester) async {
      await library.createFolder('', 'Course');
      await local();
      await local('20260828_130412_468_468744');
      for (final item in await library.listNotes('')) {
        await library.moveNote(item, 'Course');
      }
      cloud.onDelete = (_) async {
        owner = 'B';
      };
      await mount(tester);
      await deleteFirst(tester);
      expect(cloud.deleted, hasLength(1));
      expect(cloud.deleted.single.ownerId, 'A');
      expect(
        NoteDeletionStore(directory).read('20260828_130412_468_468744')?['state'],
        'pending',
      );
      expect(
        NoteDeletionStore(directory).read('20260828_130412_468_468744')?['owner'],
        'A',
      );
    },
  );

  historyTest('delete waits for in-flight upload before remote deletion', (
    tester,
  ) async {
    final file = await local();
    final uploadStarted = Completer<void>();
    final uploadRelease = Completer<void>();
    final uploading = UploadCache.runSingleFlight(
      'in-flight',
      userId: 'A',
      sessionId: session,
      operation: () async {
        uploadStarted.complete();
        await uploadRelease.future;
        return true;
      },
    );
    await uploadStarted.future;
    await mount(tester);
    await deleteFirst(tester);
    expect(cloud.deleted, isEmpty);
    expect(file.existsSync(), isFalse);
    expect(NoteDeletionStore(directory).blocksUpload(session), isTrue);
    uploadRelease.complete();
    await uploading;
    await settle(tester);
    expect(cloud.deleted, hasLength(1));
  });

  test('tombstoned note is not re-uploaded', () async {
    await local();
    NoteDeletionStore(directory).begin('A', session, localDeleted: true);
    var uploads = 0;
    await FileSyncAgent.forTesting(
      authenticatedUser: () async => 'A',
      archiveUpload: (payload) async {
        uploads++;
        return payload;
      },
      documentsDirectory: () async => directory,
    ).syncNow();
    expect(uploads, 0);
  });

  historyTest('nested folder create browse rename and delete remain usable', (
    tester,
  ) async {
    await mount(tester);
    Future<void> create(String name) async {
      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, name);
      await tester.tap(find.text('保存'));
      await settle(tester);
    }

    await create('Course');
    await tester.tap(find.text('Course'));
    await settle(tester);
    await create('Nested');
    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester);
    await tester.tap(find.text('重命名'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Renamed');
    await tester.tap(find.text('保存'));
    await settle(tester);
    expect(find.text('Renamed'), findsOneWidget);
    await deleteFirst(tester);
    expect(find.text('Renamed'), findsNothing);
    expect(
      Directory('${directory.path}/JeffNotes/Course').existsSync(),
      isTrue,
    );
  });
}
