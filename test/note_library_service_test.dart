import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/note_library_service.dart';

void main() {
  late Directory documents;
  late NoteLibraryService library;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('jeff_library_test_');
    library = NoteLibraryService(documentsDirectory: () async => documents);
  });

  tearDown(() async {
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  Future<File> note(String name, [String body = 'body']) async {
    final file = File('${documents.path}/$name');
    await file.writeAsString(body);
    return file;
  }

  test('legacy root note is virtual Inbox and remains discoverable', () async {
    final file = await note('Jeff_Notes_20260906_142233_123_456789.md');
    final items = await library.listNotes('');
    expect(items, hasLength(1));
    expect(items.single.markdownFile.path, file.path);
    expect(items.single.isLegacy, isTrue);
    expect(items.single.stableSessionId, '20260906_142233_123_456789');
  });

  test('nested folders, title sidecar, and paired WAV move together', () async {
    await note('Jeff_Notes_20260906_142233_123_456789.md');
    final wav = File(
      '${documents.path}/Jeff_Notes_20260906_142233_123_456789.wav',
    );
    await wav.writeAsBytes([1, 2, 3]);
    await library.createFolder('', 'NAIT');
    await library.createFolder('NAIT', 'SYSA1010');
    final item = (await library.listNotes('')).single;
    await library.renameNoteDisplayTitle(item, 'Week 1 - VMware');
    await library.moveNote(item, 'NAIT/SYSA1010');

    final moved = (await library.listNotes('NAIT/SYSA1010')).single;
    expect(moved.displayTitle, 'Week 1 - VMware');
    expect(moved.stableSessionId, item.stableSessionId);
    expect(await moved.markdownFile.exists(), isTrue);
    expect(await moved.audioFile!.exists(), isTrue);
    expect(
      await File('${moved.markdownFile.path}.jeffnotes.json').exists(),
      isTrue,
    );
    expect(await library.searchAllNotes('vmware'), hasLength(1));
  });

  test(
    'folder rename and move support arbitrary nesting but reject descendants',
    () async {
      await library.createFolder('', 'A');
      await library.createFolder('A', 'B');
      await library.renameFolder('A/B', 'C');
      expect((await library.listFolders('A')).single.name, 'C');
      await expectLater(
        library.moveFolder('A', 'A/C'),
        throwsA(isA<NoteLibraryException>()),
      );
    },
  );

  test('interrupted bundle journal completes before discovery', () async {
    await library.createFolder('', 'Target');
    final from = await note('Jeff_Notes_20260906_142233_123_456789.md');
    final root = await library.managedRoot();
    await root.create(recursive: true);
    final to = '${root.path}/Target/${from.uri.pathSegments.last}';
    await File('${root.path}/.library-move.json').writeAsString(
      jsonEncode({
        'version': 1,
        'moves': [
          {'from': from.path, 'to': to},
        ],
      }),
    );
    final items = await library.listNotes('Target');
    expect(items, hasLength(1));
    expect(await File(to).exists(), isTrue);
    expect(await File('${root.path}/.library-move.json').exists(), isFalse);
  });

  test(
    'invalid names and protected recovery exports cannot be moved',
    () async {
      await expectLater(
        library.createFolder('', '../bad'),
        throwsA(isA<NoteLibraryException>()),
      );
      final file = await note('Jeff_Notes_20260906_142233_123_456789.md');
      await library.createFolder('', 'Target');
      await File('${documents.path}/shadow_draft_1.json').writeAsString(
        jsonEncode({
          'exportPath': file.path,
          'pendingAudioNotes': <String, String?>{},
        }),
      );
      await expectLater(
        library.moveNote((await library.listNotes('')).single, 'Target'),
        throwsA(isA<NoteLibraryException>()),
      );
    },
  );
}
