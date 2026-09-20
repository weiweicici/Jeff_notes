# JEFF NOTES — NAIT CLASSROOM MODULE AUDIT REPORT

**Date of Audit**: September 20, 2026  
**Auditor**: Antigravity Pair-Programming Agent  
**Target Codebase**: `d:\Jeff_notes_project`  
**Status**: AUDIT ONLY (Zero code modifications, zero package installations, zero refactoring)

---

## 1. PROJECT OVERVIEW

### Core Technology Stack
* **Language**: Dart (SDK `^3.11.5`)
* **Framework**: Flutter (Material 3 UI, Provider `^6.1.2` state management)
* **Frontend**: Flutter cross-platform client (iOS, Android, macOS, Windows, Linux)
* **Backend / Cloud**: Supabase Flutter SDK (`supabase_flutter: ^2.6.0`) for anonymous authentication, cloud account sync, and storage; local filesystem for persistent document and audio caching.
* **Runtime**: Flutter Engine / Dart VM on mobile and desktop runtimes.
* **Package Manager**: Dart Pub (`pubspec.yaml`).

### Key Dependencies
* **Audio & Playback**:
  * `ffmpeg_kit_flutter_new_audio: ^2.5.2` (audio format normalization: MP4/M4A/MP3/WAV → mono 16kHz 16-bit PCM WAV)
  * `just_audio: ^0.9.39` (multi-source audio player)
  * `audio_session: ^0.1.25` (iOS/Android audio session routing, category management, headphone enforcement)
  * `audio_service: ^0.18.15` (background playback service and lockscreen/notification controls)
  * `record: 5.1.0` (in-app audio recording)
  * `flutter_tts: ^4.1.0` (client-side text-to-speech engine for practice items)
* **AI & LLM Services**:
  * `google_generative_ai: ^0.4.5` & direct REST HTTP clients via `http: ^1.2.1`
  * Primary Model: Google Gemini (`gemini-2.5-flash`)
  * Fallback Model: Groq Cloud (`openai/gpt-oss-120b`, formerly `llama-3.3-70b-versatile`)
* **ASR (Automated Speech Recognition)**:
  * For live lecture/free-talk recording: OpenAI Whisper / Groq Whisper endpoint via `OpenAIService`.
  * For the **NAIT classroom processing module**: ASR is performed *externally* (e.g. Meetily timestamped JSON or timestamped TXT export) and parsed on import by `NaitTranscriptParser`.
* **FFmpeg Usage**:
  * Managed via `ffmpeg_kit_flutter_new_audio`.
  * Primary execution in `NaitAudioImportService.normalizeAudio`: Converts any incoming classroom audio/video (`.mp4`, `.m4a`, `.mp3`, `.wav`) to standardized mono, 16kHz, 16-bit PCM WAV (`normalized.wav`).
  * Includes local system `ffmpeg` binary fallback for desktop/macOS dev environments.
* **Storage & Persistence**:
  * `path_provider: ^2.1.5` (local documents directory)
  * `flutter_secure_storage: ^9.2.2` (API keys: Gemini, Groq, OpenRouter, Supabase)
  * `shared_preferences: ^2.5.2` (user settings)
  * `uuid: ^4.5.1` (unique session and entity IDs)

### Concise Project Directory Tree
```text
d:\Jeff_notes_project\
├── .agents\
│   └── AGENTS.md                          # Project rules & audio safety policies
├── assets\
│   └── fonts\                             # NotoSansSC fonts
├── lib\
│   ├── main.dart                          # App entry point & provider initialization
│   ├── ai_orchestrator_service.dart       # Live STT & translation pipeline
│   ├── prompt_provider.dart               # Prompts for NAIT & live lecture notes
│   ├── recording_provider.dart            # Live recording state machine
│   ├── models\                            # Core note & sync data models
│   ├── services\                          # App-wide services
│   │   ├── credential_store.dart          # Secure API key storage
│   │   ├── tts_service.dart               # Headphone-safe TTS & audio playback
│   │   ├── wav_stitch_service.dart        # Pure Dart PCM WAV concatenation
│   │   └── ...
│   ├── screens\                           # Main app screens (AcademicHub, Notes, etc.)
│   └── nait_learning\                     # *** NAIT CLASSROOM MODULE ***
│       ├── nait_learning_provider.dart    # NAIT state coordinator
│       ├── models\
│       │   ├── nait_course.dart           # Course entity
│       │   ├── nait_week.dart             # Week entity & weekly pack path
│       │   ├── nait_class_session.dart    # Session entity (audio, transcript, analysis)
│       │   ├── nait_class_analysis.dart   # Summary & English extraction container
│       │   ├── nait_english_chunk.dart    # Extracted phrase, context, audio timestamps
│       │   ├── nait_audio_clip.dart       # Audio clip file metadata
│       │   ├── nait_transcript_entry.dart # Timestamped transcript entry
│       │   ├── nait_teacher_mode_task.dart# 60s teach-back prompt
│       │   └── nait_review_progress.dart  # Review & starred state
│       ├── services\
│       │   ├── nait_audio_import_service.dart     # Preserves original audio, normalizes WAV
│       │   ├── nait_transcript_parser.dart        # Parses Meetily JSON & TXT timestamps
│       │   ├── nait_chunking_service.dart         # ~17m overlapping transcript chunker
│       │   ├── nait_processing_service.dart       # Sequential AI chunk runner & clip extractor
│       │   ├── nait_consolidation_service.dart    # Multi-chunk deduplication & merge
│       │   ├── nait_audio_extract_service.dart    # Binary WAV slice extraction & silence gen
│       │   ├── nait_week_consolidation_service.dart# Weekly clip stitcher & pack builder
│       │   ├── nait_audio_playback_service.dart   # Playback router via TtsService
│       │   ├── nait_storage_service.dart          # Disk directory layout & atomic JSON writes
│       │   └── nait_english_bank_service.dart     # Course-wide English vocabulary queries
│       ├── screens\
│       │   ├── nait_home_screen.dart              # NAIT Course selection
│       │   ├── nait_course_screen.dart            # Course Week list
│       │   ├── nait_week_screen.dart              # Week sessions & weekly pack player
│       │   ├── nait_import_screen.dart            # Import Audio + Transcript dialog
│       │   ├── nait_class_screen.dart             # Full class summary & clip inventory UI
│       │   ├── nait_listening_screen.dart         # Blind listening screen
│       │   └── nait_english_bank_screen.dart      # Bank of learned/starred expressions
│       └── widgets\
│           ├── nait_class_card.dart
│           ├── nait_clip_player.dart
│           ├── nait_english_chunk_card.dart
│           ├── nait_pack_player_bar.dart
│           ├── nait_processing_status.dart
│           └── nait_section_card.dart
└── real_class_test\                               # Acceptance test harness with 107m class
    ├── audio.mp4                                  # Real 107-minute classroom video/audio
    ├── transcripts.json                           # Real 1,534-entry Meetily transcript
    └── acceptance\
        ├── runner.dart                            # Full E2E acceptance test script
        └── single_chunk_runner.dart               # Isolated chunk test runner
```

---

## 2. IDENTIFY THE NAIT MODULE

### Complete File Manifest of the NAIT Module
| Layer | Files |
| :--- | :--- |
| **Screens & UI** | `lib/nait_learning/screens/nait_home_screen.dart`<br>`lib/nait_learning/screens/nait_course_screen.dart`<br>`lib/nait_learning/screens/nait_week_screen.dart`<br>`lib/nait_learning/screens/nait_import_screen.dart`<br>`lib/nait_learning/screens/nait_class_screen.dart`<br>`lib/nait_learning/screens/nait_listening_screen.dart`<br>`lib/nait_learning/screens/nait_english_bank_screen.dart` |
| **Widgets** | `lib/nait_learning/widgets/nait_class_card.dart`<br>`lib/nait_learning/widgets/nait_clip_player.dart`<br>`lib/nait_learning/widgets/nait_english_chunk_card.dart`<br>`lib/nait_learning/widgets/nait_pack_player_bar.dart`<br>`lib/nait_learning/widgets/nait_processing_status.dart`<br>`lib/nait_learning/widgets/nait_section_card.dart` |
| **State / Provider** | `lib/nait_learning/nait_learning_provider.dart` |
| **Services** | `lib/nait_learning/services/nait_audio_import_service.dart`<br>`lib/nait_learning/services/nait_transcript_parser.dart`<br>`lib/nait_learning/services/nait_chunking_service.dart`<br>`lib/nait_learning/services/nait_processing_service.dart`<br>`lib/nait_learning/services/nait_consolidation_service.dart`<br>`lib/nait_learning/services/nait_audio_extract_service.dart`<br>`lib/nait_learning/services/nait_week_consolidation_service.dart`<br>`lib/nait_learning/services/nait_storage_service.dart`<br>`lib/nait_learning/services/nait_audio_playback_service.dart`<br>`lib/nait_learning/services/nait_english_bank_service.dart`<br>`lib/services/wav_stitch_service.dart` |
| **Prompts** | `lib/prompt_provider.dart` (`getNaitClassAnalysisPrompt()`, `getNaitChunkAnalysisPrompt()`) |
| **Models** | `lib/nait_learning/models/nait_course.dart`<br>`lib/nait_learning/models/nait_week.dart`<br>`lib/nait_learning/models/nait_class_session.dart`<br>`lib/nait_learning/models/nait_class_analysis.dart`<br>`lib/nait_learning/models/nait_english_chunk.dart`<br>`lib/nait_learning/models/nait_audio_clip.dart`<br>`lib/nait_learning/models/nait_transcript_entry.dart`<br>`lib/nait_learning/models/nait_listening_timestamp.dart`<br>`lib/nait_learning/models/nait_review_progress.dart`<br>`lib/nait_learning/models/nait_teacher_mode_task.dart` |

### The Real NAIT Execution Chain
```text
[User in NaitImportScreen]
   Selects: Course, Week, Class Date, Audio File (MP4/M4A/MP3/WAV), Transcript (JSON/TXT/MD)
   Taps: "Import & Process Class"
       ↓
[NaitLearningProvider.importAndProcessClass()]
   Generates sessionId (e.g. "20260904_a1b2")
   Resolves session directory: Documents/nait/<courseId>/week_<weekNumber>/class_<sessionId>/
       ↓
1. [NaitAudioImportService.preserveOriginalAudio()]
   Copies raw recording file to: class_<sessionId>/original_audio.<ext>
       ↓
2. [NaitAudioImportService.importTranscript()]
   Copies transcript file to: class_<sessionId>/transcript.<json|txt>
       ↓
3. [NaitAudioImportService.normalizeAudio()]
   Calls FFmpegKit to extract audio and re-encode to:
   class_<sessionId>/normalized.wav (16,000 Hz, 16-bit Mono PCM)
       ↓
4. [NaitProcessingService.processClassSession()]
   a. NaitTranscriptParser.parseFile()
      -> Parses entries into List<NaitTranscriptEntry> with millisecond timestamps
   b. NaitChunkingService.createChunks()
      -> Divides entries into ~17 min overlapping chunks (90s overlap, <=6000 tokens)
   c. Sequential Chunk Loop (0 to N-1):
      - Checks cache in class_<sessionId>/chunks/chunk_manifest.json & chunk_XX.json
      - If not cached, sends prompt (getNaitChunkAnalysisPrompt) to Gemini 2.5 Flash
      - On transient error (503/429), performs exponential retry (up to 2 retries)
      - If Gemini fails, automatically falls back to Groq Cloud (openai/gpt-oss-120b)
      - Writes chunk result atomically to class_<sessionId>/chunks/chunk_XX.json
   d. NaitConsolidationService.consolidate()
      - Merges MustDo, Lab, Important, NextClass, TechnicalPoints
      - Deduplicates English chunks; boosts priority & appearance count for repeats
      - Enforces strict separation: teacher_original vs practice_sentence
   e. Audio Extraction Loop:
      - Iterates over consolidated classroomEnglish items with valid audioStart & audioEnd
      - NaitAudioExtractService.extractClip() opens normalized.wav via RandomAccessFile
      - Writes individual PCM WAV clips: class_<sessionId>/clips/clip_001.wav, clip_002.wav, etc.
   f. Saves unified session metadata:
      - Writes class_<sessionId>/session.json
       ↓
[UI: NaitClassScreen]
   Renders 10 distinct sections including:
   - Must Do, Lab, Warnings, Next Class, Classroom English, Technical Notes,
     Ask Teacher, Talk to Classmates, Teacher Mode, and individual "Extracted Audio Clips" list.
```

---

## 3. CURRENT INPUTS

| Input Type | Supported Formats | Handling Function / Class | Destination / Storage |
| :--- | :--- | :--- | :--- |
| **Class Recording** | `.mp4`, `.m4a`, `.mp3`, `.wav` | `FilePicker.platform.pickFiles()` in `NaitImportScreen`<br>`NaitAudioImportService.preserveOriginalAudio()` | `nait/<courseId>/week_<W>/class_<S>/original_audio.<ext>` |
| **Class Transcript** | `.json` (Meetily export), `.txt`, `.md` (timestamped text) | `FilePicker.platform.pickFiles()` in `NaitImportScreen`<br>`NaitAudioImportService.importTranscript()`<br>`NaitTranscriptParser.parseFile()` | `nait/<courseId>/week_<W>/class_<S>/transcript.<json\|txt>` |
| **Course Metadata** | `courseId` (e.g. `ANIT101`), `displayName` | `NaitLearningProvider.createCourse()` | `nait/<courseId>/course.json` and `nait/index.json` |
| **Week Metadata** | `weekNumber` (integer, e.g. `1`) | `NaitLearningProvider.createWeek()` | `nait/<courseId>/week_<W>/week.json` |
| **Class Date** | `DateTime` (selected via date picker) | `NaitImportScreen._pickClassDate()` | `nait/<courseId>/week_<W>/class_<S>/session.json` |

---

## 4. TRANSCRIPT PIPELINE

1. **Source of Transcription**:
   * English transcription does **NOT** originate from live in-app speech recognition within the NAIT module.
   * Transcripts are generated externally (e.g., via the Meetily desktop recording app or Whisper CLI) and imported into Jeff_Notes.
2. **Parser Schema & Timestamps**:
   * **Parser**: `NaitTranscriptParser.parseFile()` (`lib/nait_learning/services/nait_transcript_parser.dart`).
   * **JSON Support**: Parses Meetily JSON schema: `{"segments": [{"audio_start_time": 12.34, "text": "..."}]}`.
   * **Text Support**: Parses line-based timestamps matching `[HH:MM:SS]` or `[MM:SS]`, with optional speaker labels `Speaker: text`.
   * **Granularity**: Timestamps are **segment/sentence-level**. Word-level timestamps are `Unknown / not found` in the current parser schema.
   * **Schema**: `NaitTranscriptEntry(timestamp: Duration, text: String, speaker: String?)`.
3. **Storage**:
   * Stored locally at `Documents/nait/<courseId>/week_<weekNumber>/class_<sessionId>/transcript.json` (or `.txt`).
4. **Chinese Translation & Alignment**:
   * **Line-by-line translation**: There is **no line-by-line Chinese transcript translation** performed in the NAIT module.
   * **Vocabulary translation**: For selected high-value English expressions, Chinese translations (`chineseMeaning`) are generated directly by the LLM during the chunk analysis pass.
   * **LLM Models**:
     * Primary: Google Gemini `gemini-2.5-flash`
     * Secondary / Fallback: Groq Cloud `openai/gpt-oss-120b`
   * **Text Alignment**: The prompt instructs the LLM to locate the exact absolute timestamps (`sourceTimestamp`, `audioStart`, `audioEnd`) corresponding to where the teacher spoke the phrase in the transcript.

---

## 5. CURRENT CLASSROOM SUMMARY PIPELINE

### Architecture & Service
* **Service**: `NaitProcessingService.processClassSession()` calling `NaitConsolidationService.consolidate()`.
* **LLM Engine**: Gemini `gemini-2.5-flash` (Primary) with Groq `openai/gpt-oss-120b` (Fallback).
* **Prompt Definition**: `PromptProvider.getNaitChunkAnalysisPrompt()` (`lib/prompt_provider.dart`, line 1067).
* **Input Data**: Text of transcript chunk formatted with bracketed timestamps: `[HH:MM:SS] <text>`.

### Output Schema (`NaitClassAnalysis`)
```json
{
  "mustDo": ["Assignment 1 due Friday..."],
  "lab": ["Step 1: Set VM network adapter to NAT..."],
  "important": ["Always take a snapshot before promoting to DC..."],
  "nextClass": ["Bring completed DC setup..."],
  "technicalPoints": ["DNS reverse lookup zone requirement..."],
  "classroomEnglish": [
    {
      "phrase": "leave it at the default",
      "chineseMeaning": "保持默认设置，不要改动",
      "context": "When installing IIS, you can just leave it at the default.",
      "priority": 5,
      "sourceType": "teacher_original",
      "sourceTimestamp": "00:23:10",
      "audioStart": "00:23:04",
      "audioEnd": "00:23:22"
    }
  ],
  "askTeacher": [
    {
      "text": "Are we supposed to keep the default subnet mask?",
      "sourceType": "practice_sentence"
    }
  ],
  "classmateEnglish": [
    {
      "text": "Did you get the second network adapter showing up?",
      "sourceType": "practice_sentence"
    }
  ],
  "teacherMode": {
    "prompt": "Explain the difference between Workgroup and AD Domain...",
    "suggestedOpening": "So the fundamental difference...",
    "targetChunks": ["centralized management", "out of the box"]
  }
}
```

### Storage Location & Format
* **Format**: Structured JSON embedded directly inside `session.json`.
* **File Path**: `Documents/nait/<courseId>/week_<weekNumber>/class_<sessionId>/session.json`.
* **Intermediate Cache**: `Documents/nait/<courseId>/week_<weekNumber>/class_<sessionId>/chunks/chunk_XX.json`.

### Content Audit: What Exists vs. What is Missing
* **Currently Extracted & Structured**:
  * [x] **Must-Do**: Assignments, download requirements, deadlines, submission rules.
  * [x] **Lab Procedures**: Step-by-step technical procedures, commands, network configurations.
  * [x] **Important Warnings**: Pitfalls, DC setup rules, snapshot requirements.
  * [x] **Next Class**: Preparation requirements, preview topics.
  * [x] **Technical Points**: Concise technical highlights and architecture notes.
  * [x] **Classroom English**: Phrasal verbs, idioms, spoken chunks, natural instructor expressions.
  * [x] **Chinese Explanations**: Accurate contextual Chinese translations for extracted chunks.
  * [x] **Practice Dialogue**: "Ask Teacher" and "Talk to Classmates" practice questions.
  * [x] **Teach-Back Prompt**: "Teacher Mode" 60-second explanation task.
* **What is Missing**:
  * There is **no standalone exported summary document** (such as a clean `Classroom_Summary.md` or printable PDF document). The summary exists only as JSON data rendered on the Flutter `NaitClassScreen`.

---

## 6. CURRENT SHADOWING / MP3 PIPELINE

### Selection & Timestamp Determination
* The LLM identifies high-priority spoken expressions during chunk analysis.
* The LLM provides absolute timestamps:
  * `sourceTimestamp`: Exact moment phrase was uttered.
  * `audioStart` & `audioEnd`: Padded audio window (approximately 5–25 seconds) capturing the surrounding teacher sentence context.

### Audio Extraction Engine
* **Source Audio**: `normalized.wav` (16,000 Hz, 16-bit mono PCM).
* **Extraction Service**: `NaitAudioExtractService.extractClip()` (`lib/nait_learning/services/nait_audio_extract_service.dart`).
* **Implementation**: Uses pure Dart streaming `RandomAccessFile`. It calculates exact sample-aligned byte offsets (`bytesPerSecond = 32000`), writes a 44-byte WAV header, and streams the PCM bytes directly from the normalized master WAV into individual fragment files: `clips/clip_001.wav`, `clips/clip_002.wav`, etc.

### Concatenation & Normalization
* **Per-Session Processing**: During a single class session run, **no merged audio file is created**. Only individual fragment WAV clips are extracted.
* **Weekly Consolidation**: Concatenation currently occurs **only at the Week level** via `NaitWeekConsolidationService.consolidateWeek()`.
* **Stitching Implementation**: `WavStitchService.stitch()` (`lib/services/wav_stitch_service.dart`) concatenates individual clip WAV files interleaved with a generated 0.8-second silence gap (`silence_gap.wav`) into `listening_pack.wav`.
* **Audio Format**: Output is **PCM WAV**, NOT MP3.
* **Configured Audio Specs**: Sample rate: `16000 Hz`, Channels: `1 (Mono)`, Bit depth: `16-bit PCM` (32,000 bytes/sec). Encoding bitrate for MP3: `Unknown / not found` (currently WAV only).
* **Duration Control**: There is currently **no duration cap or target budgeting algorithm** (e.g. 8–10 minutes) in place. It simply extracts all phrases identified by the LLM and (at the week level) stitches all of them together.

### Teacher Original Voice vs. TTS Confirmation
* **CONFIRMED**: The extracted audio clips and stitched listening pack use **100% TEACHER ORIGINAL CLASSROOM AUDIO** extracted directly from the imported classroom recording file.
* **TTS Usage**: Text-to-Speech (`flutter_tts`) is strictly isolated and used *only* when the user voluntarily taps the speaker icon next to generated practice questions ("Ask Teacher" / "Talk to Classmates") or taps "Speak TTS" on an expression card.

---

## 7. ALL AUDIO FILES CURRENTLY GENERATED

Inventory for ONE NAIT Classroom Processing Job:

### 1. `original_audio.<ext>` (e.g. `original_audio.mp4` or `.m4a`)
* **Filename pattern**: `original_audio.<ext>` (e.g. `original_audio.mp4`)
* **Example**: `nait/real_class/week_01/class_20260904/original_audio.mp4`
* **Purpose**: Preserved exact copy of user-provided classroom recording.
* **Created by**: `NaitAudioImportService.preserveOriginalAudio()`
* **Consumed by**: `NaitAudioImportService.normalizeAudio()`
* **Temporary or final**: Persistent source master
* **Shown to user?**: No direct in-app video player, but listed in import metadata
* **Required after job completes?**: Yes (safeguards original user data)
* **Safe to delete after final MP3 exists?**: **NO** (never delete raw master source)

### 2. `normalized.wav`
* **Filename pattern**: `normalized.wav`
* **Example**: `nait/real_class/week_01/class_20260904/normalized.wav`
* **Purpose**: FFmpeg-standardized 16kHz 16-bit mono PCM master from which all audio clips are sliced.
* **Created by**: `NaitAudioImportService.normalizeAudio()` via FFmpegKit
* **Consumed by**: `NaitAudioExtractService.extractClip()`
* **Temporary or final**: Intermediate working audio
* **Shown to user?**: No
* **Required after job completes?**: No (if all clipping / merging is finished), but retaining it avoids re-running FFmpeg normalization on retries.
* **Safe to delete after final MP3 exists?**: **Yes**, once the final Shadowing MP3 is successfully generated and verified.

### 3. Audio Fragment Clips (`clip_001.wav` ... `clip_NNN.wav`)
* **Filename pattern**: `clips/clip_<XXX>.wav`
* **Example**: `nait/real_class/week_01/class_20260904/clips/clip_001.wav`
* **Purpose**: Individual extracted teacher audio slices (5–25 seconds each) for each extracted phrase.
* **Created by**: `NaitAudioExtractService.extractClip()`
* **Consumed by**: `NaitClassScreen` (individual clip player widgets), `NaitWeekConsolidationService`
* **Temporary or final**: **Currently treated as FINAL and persistent**.
* **Shown to user?**: **YES** (displayed as a long list of audio players in `NaitClassScreen`).
* **Required after job completes?**: Currently required by the current UI, but **under the desired 2-output architecture, these are intermediate fragments that should be merged into the single final Shadowing MP3 and deleted**.
* **Safe to delete after final MP3 exists?**: **YES**, once stitched into the final 8–10 minute Shadowing MP3.

### 4. `silence_gap.wav` (Generated at Week level)
* **Filename pattern**: `silence_gap.wav`
* **Example**: `nait/real_class/week_01/silence_gap.wav`
* **Purpose**: 800ms of PCM silence inserted between speech clips during stitching.
* **Created by**: `NaitAudioExtractService.createSilenceWav()`
* **Consumed by**: `WavStitchService.stitch()`
* **Temporary or final**: Intermediate working file
* **Shown to user?**: No
* **Required after job completes?**: No
* **Safe to delete after final MP3 exists?**: **YES**

### 5. `listening_pack.wav` (Generated at Week level)
* **Filename pattern**: `listening_pack.wav`
* **Example**: `nait/real_class/week_01/listening_pack.wav`
* **Purpose**: Merged listening audio across multiple class sessions in a week.
* **Created by**: `NaitWeekConsolidationService.consolidateWeek()`
* **Consumed by**: `NaitWeekScreen`, `NaitListeningScreen`
* **Temporary or final**: Final (at week level)
* **Shown to user?**: Yes (Week player bar)
* **Required after job completes?**: Yes (at week level)
* **Safe to delete?**: No

---

## 8. TEMPORARY FILE LIFECYCLE

```text
[1. CREATION]
   • original_audio.mp4 copied into session dir
   • normalized.wav created by FFmpegKit (~200 MB for a 107m class)
   • chunk_00.json ... chunk_06.json created in chunks/
   • clip_001.wav ... clip_068.wav created in clips/ (~20 MB total)

[2. PROCESSING & EXTRACTION]
   • All chunks analyzed and consolidated into session.json
   • Clips extracted from normalized.wav

[3. MERGE / CONCATENATION]
   • Currently occurs ONLY at the Week level (listening_pack.wav)
   • No per-class merged audio is created during session processing

[4. CLEANUP]
   • CURRENT STATUS: NO CLEANUP CURRENTLY EXISTS.
   • All intermediate files (normalized.wav, chunk_XX.json, clips/*.wav)
     remain on disk indefinitely in the application documents directory.
```

### Why Do Fragment Files Currently Remain?
1. The class session processor (`NaitProcessingService`) was designed to save individual clips into `clips/` so that `NaitClassScreen` could offer individual play buttons for every phrase card and display a dedicated "Extracted Audio Clips" section.
2. The concatenation logic was placed in `NaitWeekConsolidationService` (at the week level) rather than inside `NaitProcessingService` (at the single class session level).
3. No cleanup routine was ever implemented in `NaitProcessingService`.

---

## 9. FINAL OUTPUT INVENTORY

### Current System Outputs After Processing One Class Session:

| Output Entity | Category | Description / UI Location |
| :--- | :--- | :--- |
| `session.json` | Internal Artifact | Complete session metadata, consolidated analysis, clip definitions |
| `chunk_manifest.json` & `chunk_XX.json` | Internal Artifact | Cached LLM responses for each ~17m slice |
| `original_audio.<ext>` | Internal Master | Preserved copy of original input recording |
| `normalized.wav` | Internal Working File | 16kHz mono PCM master (~200 MB) |
| `clips/clip_001.wav` ... `clip_068.wav` | **Exposed to User (Currently)** | 68 individual WAV files rendered as audio players in UI |
| **Classroom Summary Cards** | **Exposed to User (Currently)** | UI rendering of MustDo, Lab, Warnings, NextClass, ClassroomEnglish, TechnicalPoints, Practice in `NaitClassScreen` |
| `listening_pack.wav` | **Exposed to User (Week Level)** | Stitched listening pack (only generated if user triggers week consolidation) |

---

## 10. COMPARE CURRENT BEHAVIOR WITH TARGET

| Area | Current Behavior | Target Behavior | Change Needed |
| :--- | :--- | :--- | :--- |
| **Final Deliverable #1: Classroom Summary** | Rendered only as Flutter UI widgets in `NaitClassScreen` from `session.json`. No standalone exportable document file. | A complete, beautifully formatted **Classroom Summary** document (e.g. Markdown / printable report). | Add a generator to produce a standalone `summary.md` document during consolidation and provide a direct view/copy/share action. |
| **Final Deliverable #2: Shadowing MP3** | 30–70 individual `.wav` fragment files (`clip_001.wav` ...) exposed directly in the UI. Merged audio only exists at the week level in `.wav` format without duration limits. | Exactly **ONE 8–10 minute Shadowing MP3** per class session made from teacher's original audio. | Sift top high-value clips to fill an 8–10 minute budget, stitch them with silence gaps, encode/export as `shadowing.mp3`, and associate it directly with the session. |
| **Fragment Exposure** | `clips/clip_XXX.wav` are surfaced as user-facing audio players in `NaitClassScreen`. | Fragment audio files are purely internal and intermediate. The UI displays ONE session audio player. | Remove/hide the individual clips list from user-facing UI; update UI cards to reference seek offsets in the single MP3 if needed, or simplify player to the main Shadowing MP3. |
| **Audio Encoding** | Uncompressed PCM WAV (`.wav`). | Compressed MP3 (`.mp3`) for compact size and standard device compatibility. | Utilize FFmpegKit to encode the stitched PCM audio into standard 128kbps/192kbps MP3 (`shadowing.mp3`). |
| **Duration Control** | No duration budgeting. All detected phrases extracted indefinitely. | Algorithms enforce an **8–10 minute** cumulative duration cap based on priority and appearance count. | Implement priority-ranked duration budgeting during clip selection for the session MP3. |
| **Disk Cleanup** | No cleanup. All intermediate chunks, clips, and normalized WAV files remain forever. | Safe cleanup of intermediate clip WAVs and temporary files after verified MP3 generation. | Implement safe post-processing cleanup hook preserving `original_audio`, `transcript`, `summary.md`, and `shadowing.mp3`. |

---

## 11. MINIMUM-CHANGE PLAN

To achieve the exact two-file user-facing rule while preserving 100% of the proven, accepted chunk-and-consolidate pipeline:

### Execution Strategy
1. **Reuse Existing Chunking & LLM Analysis**: Keep `NaitChunkingService`, per-chunk Gemini/Groq execution, and `NaitConsolidationService` exactly as they are.
2. **Add 8–10 Min Budgeting & Per-Session Stitching**:
   * In `NaitProcessingService`, after consolidation, select the top-ranked `classroomEnglish` phrases whose cumulative duration equals 8–10 minutes (approx. 480–600 seconds).
   * Extract those clips, stitch them with 0.8s silence gaps using `WavStitchService`, and encode to `shadowing.mp3` via FFmpeg.
3. **Generate Exportable Summary Document**:
   * Add a lightweight markdown formatter that exports `NaitClassAnalysis` into `summary.md` inside the session directory.
4. **Update UI**:
   * In `NaitClassScreen`, display the **Classroom Summary** and the single **Shadowing MP3 Player Bar**. Remove the raw fragment audio cards.
5. **Safe Cleanup**:
   * Delete intermediate `.wav` clips from `clips/` only after `shadowing.mp3` exists and passes length validation (> 44 bytes).

### File Impact Analysis
* **Files Likely Modified**:
  * `lib/nait_learning/services/nait_processing_service.dart`: Add duration budgeting, session-level stitching + MP3 encoding call, and markdown summary generation.
  * `lib/nait_learning/models/nait_class_session.dart`: Add `shadowingAudioPath` and `summaryMarkdownPath` fields.
  * `lib/nait_learning/screens/nait_class_screen.dart`: Focus UI on the summary document view and single Shadowing MP3 player bar.
* **Functions Likely Modified**:
  * `NaitProcessingService.processClassSession()`
  * `NaitClassSession.toJson()` / `fromJson()`
* **Files That Should NOT Need Modification**:
  * `lib/nait_learning/services/nait_chunking_service.dart` (working perfectly)
  * `lib/nait_learning/services/nait_transcript_parser.dart` (working perfectly)
  * `lib/nait_learning/services/nait_consolidation_service.dart` (working perfectly)
  * `lib/prompt_provider.dart` (chunk prompt is already optimal)
  * `lib/services/wav_stitch_service.dart` (reusable as-is)
* **New Files Required, If Any**:
  * Optional helper: `lib/nait_learning/services/nait_summary_formatter.dart` (to format `NaitClassAnalysis` into GitHub-flavored Markdown).

---

## 12. TEMP FILE CLEANUP PLAN

### The Safe Lifecycle Flow
```text
Step 1: Ingestion & Normalization
        original_audio.mp4 preserved
        normalized.wav created
           ↓
Step 2: AI Chunk Analysis & Consolidation
        chunks/*.json cached
        session.json created
           ↓
Step 3: Duration Selection (8–10 min) & Clip Extraction
        Top high-value clips extracted to clips/*.wav
           ↓
Step 4: Stitching & MP3 Conversion
        clips/*.wav + silence_gap.wav → temp_stitched.wav → shadowing.mp3
        summary.md written to disk
           ↓
Step 5: Verification Gate (Strict Checks)
        ✓ File(summary.md).exists() && length > 100 bytes
        ✓ File(shadowing.mp3).exists() && length > 500 KB
           ↓
Step 6: Safe Cleanup (ONLY AFTER PASSING STEP 5)
        Delete clips/*.wav
        Delete temp_stitched.wav
        Delete silence_gap.wav
        (Optionally delete normalized.wav to save ~200MB per class)
           ↓
RETAINED PERMANENTLY:
  1. original_audio.<ext>  (Source audio master)
  2. transcript.json       (Source transcript data)
  3. session.json          (Structured machine-readable data)
  4. summary.md            [FINAL USER DELIVERABLE #1]
  5. shadowing.mp3         [FINAL USER DELIVERABLE #2]
```

### Safety Principles
* **Failure Preservation**: If AI analysis fails, FFmpeg errors, or output validation fails, **no temporary files are deleted**. The manifest and intermediate files remain intact for debugging and instant retry.
* **Master Audio Protection**: `original_audio.<ext>` is never deleted by any cleanup routine.

---

## 13. FUTURE SONICSHADOW COMPATIBILITY

The Jeff_Notes NAIT pipeline **already captures all prerequisite data** needed for future SonicShadow integration.

### Existing Data Inventory Available for SonicShadow
1. **Audio File**: Master teacher classroom audio slices extracted directly from original recording.
2. **Timed Transcript**: `NaitTranscriptEntry` items with millisecond-accurate `timestamp` and speaker markers.
3. **Selected Useful Expressions**: `NaitEnglishChunk` items containing:
   * `phrase`: Target English phrase/chunk.
   * `context`: Complete surrounding instructor sentence context.
   * `chineseMeaning`: Contextual Chinese translation.
   * `priority`: Frequency and importance score (1–5).
   * `sourceType`: Explicitly tagged as `teacher_original`.
   * `audioStart` & `audioEnd`: Exact millisecond/timecode timestamps for audio slicing.
4. **Practice Sentences**: `askTeacher` and `classmateEnglish` items with `sourceType: practice_sentence`.

### Future Handshake Flow
```text
Jeff_Notes NAIT Processing
       ↓
Exports:
  1. Classroom Summary (Markdown)
  2. 8–10 min Shadowing MP3
  3. Structured Alignment Manifest (JSON / Timestamps / Text / Translations)
       ↓
SonicShadow Application
       ↓
Features Enabled Instantly:
  • Waveform display with sentence boundaries
  • Blind listening mode with tap-to-reveal English & Chinese
  • Sentence-by-sentence looping and shadowing playback
  • Pitch / speed adjustment of teacher's real voice
```

---

# Files Most Relevant to NAIT Two-File Output

The following 12 files are the most critical for implementing the two-file output rule:

1. [nait_processing_service.dart](file:///d:/Jeff_notes_project/lib/nait_learning/services/nait_processing_service.dart) — Orchestrates the full session pipeline from transcript chunking to AI analysis, audio extraction, and storage.
2. [nait_class_session.dart](file:///d:/Jeff_notes_project/lib/nait_learning/models/nait_class_session.dart) — Data model for class sessions, which will hold paths to the two final deliverable files (`summary.md` and `shadowing.mp3`).
3. [nait_class_analysis.dart](file:///d:/Jeff_notes_project/lib/nait_learning/models/nait_class_analysis.dart) — Holds the structured operational notes and extracted English expressions that form the summary document.
4. [nait_english_chunk.dart](file:///d:/Jeff_notes_project/lib/nait_learning/models/nait_english_chunk.dart) — Defines English chunks with start/end audio timestamps, priority, and Chinese translations used for 8–10 min shadowing selection.
5. [nait_audio_extract_service.dart](file:///d:/Jeff_notes_project/lib/nait_learning/services/nait_audio_extract_service.dart) — Performs sample-accurate slicing of teacher audio from `normalized.wav`.
6. [wav_stitch_service.dart](file:///d:/Jeff_notes_project/lib/services/wav_stitch_service.dart) — Joins multiple PCM audio slices and silence gaps into a single continuous audio stream.
7. [nait_audio_import_service.dart](file:///d:/Jeff_notes_project/lib/nait_learning/services/nait_audio_import_service.dart) — Manages FFmpeg normalization and audio format conversion.
8. [nait_consolidation_service.dart](file:///d:/Jeff_notes_project/lib/nait_learning/services/nait_consolidation_service.dart) — Merges and ranks multi-chunk English extractions to prioritize the most valuable expressions for the 8–10 min audio.
9. [nait_storage_service.dart](file:///d:/Jeff_notes_project/lib/nait_learning/services/nait_storage_service.dart) — Manages filesystem paths, directory structures, and persistence for sessions.
10. [nait_class_screen.dart](file:///d:/Jeff_notes_project/lib/nait_learning/screens/nait_class_screen.dart) — The primary user interface that will present the two final deliverables (Summary View and Shadowing MP3 Player).
11. [nait_learning_provider.dart](file:///d:/Jeff_notes_project/lib/nait_learning/nait_learning_provider.dart) — State coordinator connecting the UI actions with background processing and playback.
12. [nait_week_consolidation_service.dart](file:///d:/Jeff_notes_project/lib/nait_learning/services/nait_week_consolidation_service.dart) — Contains existing reference logic for clip selection, silence gap insertion, and audio stitching.

---

# Recommended Implementation Scope

### Scope Estimate: **Small to Medium**

### Why:
* **The hard problems are already solved and accepted**:
  * The long-class transcript chunking (~17m window) and token safety ceiling are implemented and tested.
  * The AI sequential execution with Gemini bounded retries and Groq fallback is implemented and verified on real 107-minute classes.
  * The deterministic multi-chunk consolidation is already working.
  * The binary WAV audio extraction (`NaitAudioExtractService`) and WAV stitching (`WavStitchService`) are already implemented and proven.
* **What needs to be added is straightforward**:
  1. A duration budgeting filter (summing clip durations up to 480–600 seconds based on existing `priority`).
  2. A single session-level MP3 encode step using existing FFmpegKit.
  3. A markdown document exporter for `NaitClassAnalysis`.
  4. Updating `NaitClassScreen` to present the single Shadowing MP3 player and summary document rather than listing 68 individual clip cards.
  5. A 5-line safe cleanup function that deletes temporary `clips/*.wav` after verification.

---

# Explicit Answers to Core Questions

### 1. Does the current NAIT module already generate a final merged MP3?
**No.** Currently, the session pipeline generates individual `.wav` clips (`clips/clip_001.wav`...). Merged audio is only created if the user manually triggers consolidation at the **Week** level, and that output is currently an uncompressed **`.wav`** file (`listening_pack.wav`), not an MP3.

### 2. Is that audio made from the teacher's original classroom audio?
**Yes.** All audio clips and stitched listening packs are sliced directly from the teacher's original classroom recording via `normalized.wav`. It is **100% authentic teacher voice, NOT TTS**.

### 3. Why are individual MP3/WAV fragments currently retained/exposed?
Because `NaitProcessingService` extracts each phrase into its own file in `clips/`, and `NaitClassScreen` was coded to render individual audio player widgets for every single extracted phrase card and display an "Extracted Audio Clips" list.

### 4. Can those fragments safely become temporary-only files?
**Yes.** Once the top-priority clips are stitched and encoded into the final 8–10 minute `shadowing.mp3`, the individual `.wav` fragments in `clips/` serve no further purpose and can be safely deleted.

### 5. Can the final user-facing result realistically be reduced to exactly two outputs without redesigning Jeff_Notes?
**Yes, easily.** All the underlying machinery (chunking, AI analysis, consolidation, extraction, stitching) already exists. We only need to assemble the session-level Shadowing MP3 and Summary Markdown document at the end of the existing pipeline and update the screen to display them.

### 6. Which existing data can later be reused by SonicShadow?
* Segment-level timed transcripts with millisecond timestamps (`NaitTranscriptEntry`).
* Extracted English chunks with start/end audio timestamps (`audioStart`, `audioEnd`), contextual sentences (`context`), and Chinese meanings (`chineseMeaning`).
* Normalized teacher PCM audio master (`normalized.wav`) or final Shadowing MP3 (`shadowing.mp3`).
* Priority and frequency metrics (`priority`, `appearanceCount`).
* Practice questions (`askTeacher`, `classmateEnglish`) and teach-back prompts (`teacherMode`).
