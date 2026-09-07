# Note library upgrade handoff

## Design and inventory

The previous History and `FileSyncAgent` scans were limited to top-level
`Documents/*.md`; generated Markdown/WAV names carry the recording session ID.
This upgrade preserves that contract. New completed recordings continue writing
to Documents root and appear in a virtual **Inbox**; no recording-time folder
choice and no automatic migration were introduced.

`NoteLibraryService` adds generic managed folders below `Documents/JeffNotes/`.
It does not create business/example folders. Markdown remains the recoverable
source of truth. A sibling `*.md.jeffnotes.json` sidecar contains only
`stableSessionId` (for non-standard legacy names) and `displayTitle`.
Corrupt/missing metadata falls back to the Markdown filename and discovery.

## Changed files

* Added `lib/services/note_library_service.dart` — discovery, title metadata,
  generic nested folders, move journal/replay, path/link checks, and recovery
  draft protection.
* Replaced `lib/screens/history_screen.dart` flat root list with mobile folder
  browsing, breadcrumb/back navigation, global search, persisted sort, folder
  and note actions, confirmation counts for non-empty folders, and restored
  cloud-only archive list/download opening.
* Updated `lib/services/file_sync_agent.dart` to discover both virtual Inbox
  and recursive managed notes via the library service.
* Added/updated `test/note_library_service_test.dart` and
  `test/file_sync_agent_retry_test.dart`.

## Storage, migration, and sync compatibility

* Existing root Markdown/WAV files are never moved on launch. Their generated
  basename/session ID stays unchanged and they continue to open through the
  absolute-path `NoteDetailScreen`/`NoteNavigationService` route.
* A note move carries Markdown, same-basename WAV, and sidecar as one logical
  bundle. Before the first rename, a persistent `JeffNotes/.library-move.json`
  journal is atomically written; discovery/sync replays it before scanning.
  Move recovery either completes all source-to-target pairs or stops scanning
  with a clear error on conflict/missing data. Symlinks and escaping paths are
  rejected.
* A currently processing/recoverable export referenced by a shadow draft cannot
  be moved or deleted. Folder recursive deletion checks the same condition.
* `FileSyncAgent` keeps the pre-existing `user_id,session_id` upsert identity.
  The cache fingerprint includes display title, so title-only edits re-upsert
  the existing row despite identical Markdown `file_hash`; moving does not
  generate another session ID. No Supabase schema or live data was changed.
* Cloud reads capture the authenticated identity and discard an old result
  after logout/account switching. Local stable session IDs hide matching cloud
  rows, so a moved note cannot be downloaded again to root. A cloud-only note
  materializes once locally before standard rename/move actions are available.

## Verification evidence

| Requirement area | Evidence |
| --- | --- |
| Legacy root discovery / virtual Inbox / stable ID | `note_library_service_test.dart` |
| Create/nest/rename/move folders and descendant guard | `note_library_service_test.dart` |
| Rename display title, move Markdown+WAV+sidecar, global search | `note_library_service_test.dart` |
| Journal replay before discovery, invalid paths, recovery-draft move block | `note_library_service_test.dart` |
| Same cloud session ID after content/title operations | `file_sync_agent_retry_test.dart` |
| Title-only sync update without content-hash change | added `renaming display title...` test |
| Cloud-only merge/download and account-generation guard | restored in `HistoryScreen`; live Supabase/widget fake remains manual verification |
| Existing recording/recovery/TTS/audio regressions | full `flutter test`: 248 passing |
| Static analysis | `flutter analyze`: no errors; pre-existing info/warnings remain |

## Known limits and device checks

No real device audio playback, Supabase request, or crash-kill test was run;
unit tests use filesystem/auth/upload doubles. Verify on iPhone:

1. Complete a Lecture and a Free Talk recording; ensure both appear in virtual
   Inbox without a folder prompt, can open, and still play audio through the
   existing headphone policy.
2. Create arbitrary nested folders; move a completed Markdown/WAV pair;
   relaunch during a move only after making a backup, then verify journal
   recovery has one pair and no duplicate cloud row.
3. Rename a note, trigger authenticated sync, and verify the existing
   `archives` row (same `session_id`) has the new title.
4. Try moving/deleting an item while its shadow draft is pending; ensure the
   action is blocked. Confirm folder recursive-delete count and account/logout
   isolation with two users before release.

RecordingProvider, SessionBackgroundProcessor, ShadowDraftService,
RecordingSessionContext, InsightNote, TTS, route/audio handlers, prompts,
exports, and NAIT Learning were not modified.
