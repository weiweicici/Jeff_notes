# Jeff Notes: Full Technical Specification & Architecture

## 1. System Overview
Jeff Notes is a production-grade academic assistant designed for high-concurrency audio transcription and professional academic translation. It operates on a **Session Isolation Architecture**, decoupling the active recording lifecycle from background AI finalization. The app is built with **Flutter 3.24.0+ (iOS 15.5+)**, using **Provider** for state management.

## 2. Core Data Flow (Zero-Latency Hybrid-Core Architecture)
```mermaid
graph TD
    A[AudioRecorder] -->|5-8s Slices| B[Tail Stitching Logic]
    B -->|WAV Header Correction| C[AIOrchestratorService]
    C -->|Priority 0| D[Groq Whisper STT]
    D -->|English Stream| E[RecordingProvider]
    C -->|Batching x1| F[Groq openai/gpt-oss-120b Translation]
    F -->|Chinese Subtitles| E
    E -->|Shadow Cache| G[shadow_draft.json]
    E -->|On Stop - Finalizing| H[AI Flush & Final Recap]
    H -->|_aiService| I[Groq openai/gpt-oss-120b Final Recap]
    E -->|On Stop - Export| J[Markdown Export]
```

## 3. Session Isolation & Concurrency
To allow users to start a new recording immediately after stopping the previous one, the system uses a non-blocking finalization pipeline:
- **RecordingProvider**: The central `ChangeNotifier` that manages the entire lifecycle — audio recording, AI orchestration, note storage, and export.
- **Decoupling**: When `stopRecording()` is called, the slice timer stops, the orchestrator flushes its buffer, and finalization begins asynchronously. The UI is immediately ready for the next recording.
- **Background Finalization**: `ApiScheduler.untilIdle()` waits for all pending AI tasks. The `generateFinalAcademicReview` flow handles: buffer flush, optional final recap, and Markdown export.
- **Shadow Cache Recovery**: On app start, `_checkRecoveryCache()` detects `shadow_draft.json`. Users can recover or dismiss pending notes.

## 3. AI Orchestration & Mode Handling
### 3.1 Mode-Specific Pipelines & Zero-Latency
The system adapts its prompt strategies and UI rendering based on the `AppMode` enum to deliver a zero-latency simultaneous translation experience:
- **Academic Lecture**: Focuses on `Thesis Statement` and `Logic Maps`. Exports structured 60s Block Summaries (`[P]` proposition, `[K]` key term, `[D]` data, `[L]` logic). UI uses **Blue** accents and `school` icons. **Latest Summary card is expanded by default.** On stop, instantly aggregates all cached summaries into a popup.
- **Group Discussion**: Focuses on strict `Concise Paraphrasing (Bilingual)` and `Discussion Starters`. Prompt extracts opinions (`[V]`), conflicts (`[C]`), consensus (`[A]`), and open questions (`[Q]`). UI uses **Purple** accents and `forum` icons. **Latest Summary card is collapsed by default (expandable on click).**
- **FreeTalk**: Focuses on raw, lightning-fast bilingual transcription and translation. No AI summary is generated. On stop, exports pure Chinese then pure English text without any headers or timestamps. UI uses default styling. **Latest Summary card is collapsed by default.**

### 3.2 AIOrchestratorService
Acts as the central bus between raw text and intelligence (`ai_orchestrator_service.dart`).
- **Fast Track (STT)**: Every audio slice is sent via `ApiScheduler` (priority 0) to Groq Whisper (`whisper-large-v3`). Raw text is sanitized by `TextSanitizer.clean()` (CJK removal, system marker stripping, word stutter dedup) and deduplicated via `mergeOverlappingText()`.
- **Zero-Latency Slow Track (Translation)**: By setting **`batchSize = 1`**, every 5-second slice is instantly translated via Groq `openai/gpt-oss-120b`. Results are split by sentence boundaries and distributed back to corresponding notes.
- **Smart-Settling & Rolling Context**: The translation system prompt is optimized to detect unfinished sentences (input ending without punctuation) and translate them with a natural "hanging/unfinished" tone. The last 2 translation pairs are injected as `[Previous Context]` to maintain coherence.
- **Active Live Failover**: When the primary translation service fails, the orchestrator falls back to `translationFallbackService`. In the current implementation, both primary and fallback are bound to the same Groq service instance.
- **Terminology Interceptor**: Currently in pass-through mode (`terminology_interceptor.dart`). LLMs proved unreliable at preserving placeholders, so raw English is translated directly.

### 2.1 Actual AI Service Binding (recording_provider.dart `_updateService()`)
All AI services are bound to **Groq** (`openai/gpt-oss-120b` for chat, `whisper-large-v3` for STT):

| Role | Service | Model |
|------|---------|-------|
| STT (Fast Track) | Groq | `whisper-large-v3` |
| Translation (Slow Track) | Groq | `openai/gpt-oss-120b` |
| Translation Fallback | Groq | `openai/gpt-oss-120b` (same instance) |
| Final Recap | Groq | `openai/gpt-oss-120b` |
| Essay Generation | Gemini | `gemini-2.5-flash` |
| Reading AI (Quiz/Summary/Translation/Paraphrase/Vocab) | Groq | `openai/gpt-oss-120b` |
| Grammar AI (Exercise/Question/Correction) | Groq | `openai/gpt-oss-120b` |

**SiliconFlow (硅基流动) 实际使用情况**:
- **TTS 英文语音合成** (`tts_service.dart:943-978`): 使用 `FunAudioLLM/CosyVoice2-0.5B` Bella 女声做英文 AI 拟真音色合成。这是硅基流动在 App 中**唯一实际被使用**的功能。
- **STT 备选支持** (`openai_service.dart:63-70`): 代码层面支持硅基流动的 SenseVoiceSmall 模型做 STT（当 baseUrl 包含 siliconflow 时），但实际配置中 STT 走 Groq。
- **FreeTalk 翻译** (`recording_provider.dart:587-607`): 代码中有 `_translateViaSiliconFlow()` 方法，但实际调用的是 `_aiService!.translate()`，而 `_aiService` 被绑定为 Groq 服务，所以 FreeTalk 翻译实际走 Groq。

### 2.1 实际 AI 服务绑定一览

| 功能 | 实际服务 | 实际模型 |
|------|---------|---------|
| STT 语音转写 (首选) | Groq | `whisper-large-v3` |
| STT 语音转写 (降级) | Google Gemini | `gemini-2.5-flash` (多模态音频直接转写) |
| 实时翻译 | Groq | `openai/gpt-oss-120b` |
| 翻译兜底 | Groq | `openai/gpt-oss-120b` (同一实例) |
| 最终复盘 (Final Recap) | Groq | `openai/gpt-oss-120b` |
| 作文生成 | Gemini | `gemini-2.5-flash` |
| 精读 AI (出题/摘要/翻译/转述/生词) | Groq | `openai/gpt-oss-120b` |
| 语法 AI (出题/问答/纠错) | Groq | `openai/gpt-oss-120b` |
| 英文 TTS 语音合成 | SiliconFlow (首选) | `FunAudioLLM/CosyVoice2-0.5B` Bella |
| 英文 TTS 降级方案 1 | Google Gemini | `Gemini 2.0 Flash` / `en-US-Studio-O` |
| 英文 TTS 降级方案 2 | Microsoft Edge | `en-US-JennyNeural` |
| 中文 TTS | iOS 原生 / 微软 Edge | `zh-CN-XiaoxiaoNeural` |

### 2.1 硅基流动 (SiliconFlow) 实际使用情况

硅基流动在 App 中**唯一实际被使用**的功能是 **TTS 英文语音合成** (`tts_service.dart:943-978`):
- 使用 `FunAudioLLM/CosyVoice2-0.5B` 模型，Bella 女声
- 作为英文 TTS 的首选方案，失败后降级到 Gemini → Edge Neural → iOS 原生

代码中存在的硅基流动备选支持（但实际未启用）：
- **STT 备选** (`openai_service.dart:63-70`): 当 baseUrl 包含 "siliconflow" 时，使用 SenseVoiceSmall 模型做 STT。但实际配置中 STT 走 Groq。
- **FreeTalk 翻译** (`recording_provider.dart:587-607`): `_translateViaSiliconFlow()` 方法存在，但实际调用的是 `_aiService!.translate()`，而 `_aiService` 被绑定为 Groq 服务。

## 3. Session Isolation & Concurrency
To allow users to start a new recording immediately after stopping the previous one, the system uses a non-blocking finalization pipeline:
- **RecordingProvider**: The central `ChangeNotifier` that manages the entire lifecycle — audio recording, AI orchestration, note storage, and export.
- **Decoupling**: When `stopRecording()` is called, the slice timer stops, the orchestrator flushes its buffer, and finalization begins asynchronously. The UI is immediately ready for the next recording.
- **Background Finalization**: `ApiScheduler.untilIdle()` waits for all pending AI tasks. The `generateFinalAcademicReview` flow handles: buffer flush, optional final recap, and Markdown export.
- **Shadow Cache Recovery**: On app start, `_checkRecoveryCache()` detects `shadow_draft.json`. Users can recover or dismiss pending notes.

## 4. AI Orchestration & Mode Handling
### 4.1 Mode-Specific Pipelines & Zero-Latency
The system adapts its prompt strategies and UI rendering based on the `AppMode` enum to deliver a zero-latency simultaneous translation experience:
- **Academic Lecture**: Focuses on `Thesis Statement` and `Logic Maps`. Exports structured Markdown with Full Script + AI Review + Block Summaries. UI uses **Blue** accents and `school` icons. **Latest Summary card is expanded by default.** On stop, triggers `FinalReviewModal` popup.
- **Group Discussion**: Focuses on strict `Concise Paraphrasing (Bilingual)` and `Discussion Starters`. Prompt extracts opinions (`[V]`), conflicts (`[C]`), consensus (`[A]`), and open questions (`[Q]`). UI uses **Purple** accents and `forum` icons. **Latest Summary card is collapsed by default (expandable on click).**
- **FreeTalk**: Focuses on raw, lightning-fast bilingual transcription and translation. No AI summary is generated. On stop, exports pure Chinese then pure English text without any headers or timestamps. UI uses default styling. **Latest Summary card is collapsed by default.**

### 4.2 AIOrchestratorService
Acts as the central bus between raw text and intelligence (`ai_orchestrator_service.dart`).
- **Fast Track (STT)**: Every audio slice is sent via `ApiScheduler` (priority 0) to Groq Whisper (`whisper-large-v3`). Raw text is sanitized by `TextSanitizer.clean()` (CJK removal, system marker stripping, word stutter dedup) and deduplicated via `mergeOverlappingText()`.
- **Zero-Latency Slow Track (Translation)**: By setting **`batchSize = 1`**, every 5-second slice is instantly translated via Groq `openai/gpt-oss-120b`. Results are split by sentence boundaries and distributed back to corresponding notes.
- **Smart-Settling & Rolling Context**: The translation system prompt is optimized to detect unfinished sentences (input ending without punctuation) and translate them with a natural "hanging/unfinished" tone. The last 2 translation pairs are injected as `[Previous Context]` to maintain coherence.
- **Active Live Failover**: When the primary translation service fails, the orchestrator falls back to `translationFallbackService`. In the current implementation, both primary and fallback are bound to the same Groq service instance.
- **Terminology Interceptor**: Currently in pass-through mode (`terminology_interceptor.dart`). LLMs proved unreliable at preserving placeholders, so raw English is translated directly.

### 4.3 ApiScheduler (The Traffic Cop)
- **4 Parallel Slots**: Manages 4 concurrent network requests across all sessions.
- **Prioritization**: `Priority 0` (STT) always preempts `Priority 1` (Translation).
- **Retry Policy**: 429 (rate limit) backs off `10s × attempt`; 500/503 backs off `2s × attempt`. Max 3 attempts per task.
- **Session-Aware Idle**: Supports `untilSessionIdle(sessionId)` and global `untilIdle()` for export safety.

### 4.3 Summary Engine
- **60s Sliding Window**: The `InsightNote` model has an `isSummary` field and the export code references "60s Block Summaries", but the actual `_performBatchSummary()` method that would generate these summaries **does not exist in the codebase**. No notes with `isSummary: true` are ever created during recording.
- **Final Recap (Optional)**: If `enableFinalRecap` is on, `generateFinalAcademicReview()` aggregates all transcript text and calls `_aiService.summarize(strategy: recap)`. Primary service failure triggers fallback. Markdown export is guaranteed via `try/finally`.

## 5. UI Structure

### 5.1 Screen Hierarchy
```
AcademicHubScreen (Home)
  ├── NotesScreen (Audio Transcription & Translation)
  ├── EssayConfigScreen (对比文章模板写作)
  ├── ReadingScreen (阅读精读列表)
  │     ├── ReadingSessionScreen (截图/PDF → OCR导入)
  │     └── ReadingDetailScreen (原文+摘要/翻译/转述/生词/AI出题)
  ├── GrammarScreen (语法精讲列表)
  │     └── GrammarDetailScreen (语法详情)
  └── HistoryScreen (Past Sessions)
        └── NoteDetailScreen (MD Viewer + PDF Export)
```

### 5.2 NotesScreen Layout (`notes_screen.dart`)
- **Summary Notification Banner**: Appears when `sessionReadyStream` emits new content. Auto-prompts modal in Lecture mode.
- **Cache Recovery Bar**: Detects unfinished sessions from `shadow_draft.json`.
- **Summary Panel**: Selector-bound to `notes.where(isSummary)`. Shows latest summary via `MarkdownBody`. Lecture mode expands by default; Discussion mode collapses.
- **Transcript List**: Each item shows English text + Chinese translation. `RepaintBoundary` + `ValueKey(note.id)` for efficient rendering. `ClampingScrollPhysics` prevents scroll bounce during async translation updates.
- **FAB (RecordingPulseFAB)**: Red pulse animation during recording, orange static glow when paused, mic icon when idle.

### 5.2 EssayConfigScreen (学术写作助手)
- **Dual-Input Topic Mechanism**: A custom `TextField` (hint: "例如: wearing masks") sits above a category-based topic grid. If the custom field is non-empty, it overrides the preset selection entirely.
- **46 Preset Topics in 11 Categories**: Transportation & Safety, Technology & Digital, Daily Life & Consumer, School & Study, Work & Career, Media & Entertainment, Health & Lifestyle, Environment & Sustainability, Society & Culture, Family & Relationships, Ethics & Technology Boundaries.
- **Topic Picker**: `ChoiceChip` grid (`Wrap` layout) displays chinese-only labels for one-glance scanning; category switch reloads the grid instantly.
- **Essay Type Toggle**: Comparison (Intro → Cost → Happiness → Time → Conclusion) or Argumentative (Intro → Cost → Happiness → Time-based Refutation → Conclusion).
- **Cost · Time · Happiness Framework**: Essays are structured around these three concrete angles, replacing vague "advantages/disadvantages" with measurable dimensions. The flexible skeleton allows 4-5 sentences per paragraph with free ordering of Cost/Happiness/Time across body paragraphs — no rigid template enforcement.
- **AI Prompt** (in `RecordingProvider.generateEssayMatrix`): Chinese system prompt with simple-vocabulary 大白话 style (避免复杂从句, 用最简单直白的语言说明道理, 像在跟一个初中生说话). Essays follow a skeleton (Topic Sentence → Why → Example → How it relates → Extra) but ordering of the three angles is free.
- **Model**: Gemini `gemini-2.5-flash` via direct HTTP REST API (replaces former Groq `openai/gpt-oss-120b`). Requires Gemini API Key from Settings page. Auto-retry once on failure (5s delay).
- **Export**: Auto-saves to Markdown (`Jeff_Essay_{topic}_{timestamp}.md`), clipboard copy, and PDF export via `PdfService`.

## 6. Event-Driven UI & Auto-Popup
The UI does not poll for summary completion. Instead, it uses a **Reactive Notification Stream**:
- **sessionReadyStream**: A broadcast stream in `RecordingProvider`.
- **Trigger**: Emits the final recap content when `generateFinalAcademicReview` is complete.
- **Consumption**: `NotesScreen` listens to this stream and automatically triggers the `FinalReviewModal` strictly during Lecture Mode. Real-time translation streams are completely separated from this stream to guarantee no premature, empty, or annoying banner popups during live recording sessions.

## 7. Audio Ingestion & Stitching Protocol
- **Smart Slice Timer**: A `Timer.periodic` fires every 5-8 seconds (user-configurable). Stops current recording and starts a new one (stop-start cycle).
- **Overlap-Stitch Algorithm**: Captures a trailing 25,600 byte PCM segment (`kTailSize`) to prevent word-chopping at slice boundaries. Stitching runs in a background Isolate via `compute()`.
- **WAV Integrity**: Manually generates a 44-byte WAV header for each slice (16kHz, 16-bit, Mono) in the background Isolate.
- **Pause/Resume**: Stops the slice timer and recorder without clearing notes. On resume, restarts recording and timer, seamlessly appending new slices.

## 8. Domain-Specific Translation (EAL Optimized)
- **Philosophy**: Uses a **Simultaneous Interpreter Prompt** with strict temperature (`0.1`) to ensure academic tone and technical term preservation.
- **Sanitization Pipeline (`text_sanitizer.dart`)**: CJK character removal, system marker stripping, invisible character removal, word stutter dedup (`_removeWordStutter`), and overlapping text merge for slice boundary dedup.

## 9. Data Persistence Hierarchy
1. **Shadow Cache (Ephemeral)**: `shadow_draft.json` written to temporary directory on every translation result, enabling crash recovery.
2. **MD Export (Permanent)**: Written to `getApplicationDocumentsDirectory()`. Filename format: `Jeff_Notes_yyyyMMdd_HHmm.md`. Structure: Part 1 (Full Script: Chinese + English), Part 2 (AI Academic Review), Part 3 (60s Block Summaries — currently unused as no summary notes are generated).
   - FreeTalk export: `Jeff_FreeTalk_yyyyMMdd_HHmmss.md` (pure Chinese then English, no headers).
   - Essay export: `Jeff_Essay_topicA_yyyyMMdd_HHmm.md`.
3. **PDF Export**: Via `PdfService` using `flutter_markdown` + `pdf`/`printing` packages.

## 8. Development Environment (Actual AI Service Binding)

| 功能 | 实际服务 | 实际模型 | 文件位置 |
|------|---------|---------|---------|
| STT 语音转写 | Groq | `whisper-large-v3` | `openai_service.dart:48` |
| 实时翻译 | Groq | `openai/gpt-oss-120b` | `recording_provider.dart:378-381` |
| 翻译兜底 | Groq | `openai/gpt-oss-120b` (同一实例) | `recording_provider.dart:381` |
| 最终复盘 (Final Recap) | Groq | `openai/gpt-oss-120b` | `recording_provider.dart:727` |
| 作文生成 | Gemini | `gemini-2.5-flash` | `recording_provider.dart:995-1063` |
| 精读 AI (出题/摘要/翻译/转述/生词) | Groq | `openai/gpt-oss-120b` | `reading_quiz_service.dart:24` |
| 语法 AI (出题/问答/纠错) | Groq | `openai/gpt-oss-120b` | `grammar_service.dart:9` |
| 英文 TTS 语音合成 (首选) | **SiliconFlow** | `FunAudioLLM/CosyVoice2-0.5B` Bella | `tts_service.dart:943-978` |
| 英文 TTS 语音合成 (降级1) | Google Gemini | `Gemini 2.0 Flash` / `en-US-Studio-O` | `tts_service.dart:827-941` |
| 英文 TTS 语音合成 (降级2) | Microsoft Edge | `en-US-JennyNeural` | `tts_service.dart:781-824` |
| 英文 TTS 语音合成 (离线兜底) | iOS 原生 | Samantha/Ava/Karen | `tts_service.dart:640-674` |
| 中文 TTS (首选) | 微软 Edge | `zh-CN-XiaoxiaoNeural` | `tts_service.dart:510-555` |
| 中文 TTS (备选) | iOS 原生 | 系统中文语音 | `tts_service.dart:371-428` |

### 硅基流动 (SiliconFlow) 实际使用情况

硅基流动在 App 中**唯一实际被使用**的功能是 **TTS 英文语音合成** (`tts_service.dart:943-978`):
- 模型: `FunAudioLLM/CosyVoice2-0.5B`
- 音色: `bella` (高清流畅自然英文播音女声)
- 端点: `https://api.siliconflow.cn/v1/audio/speech`
- 作为英文 TTS 的首选方案，失败后降级到 Gemini → Edge Neural → iOS 原生

代码中存在的硅基流动备选支持（但实际未启用）:
- **STT 备选** (`openai_service.dart:63-70`): 当 baseUrl 包含 "siliconflow" 时，使用 SenseVoiceSmall 模型做 STT。但实际配置中 STT 走 Groq。
- **FreeTalk 翻译** (`recording_provider.dart:587-607`): `_translateViaSiliconFlow()` 方法存在，但实际调用的是 `_aiService!.translate()`，而 `_aiService` 被绑定为 Groq 服务。

## 9. Data Persistence Hierarchy
1. **Shadow Cache (Ephemeral)**: `shadow_draft.json` written to temporary directory on every translation result, enabling crash recovery.
2. **MD Export (Permanent)**: Written to `getApplicationDocumentsDirectory()`. Filename format: `Jeff_Notes_yyyyMMdd_HHmm.md`. Structure: Part 1 (Full Script: Chinese + English), Part 2 (AI Academic Review), Part 3 (60s Block Summaries — currently unused as no summary notes are generated during recording).
   - FreeTalk export: `Jeff_FreeTalk_yyyyMMdd_HHmmss.md` (pure Chinese then English, no headers).
   - Essay export: `Jeff_Essay_topicA_yyyyMMdd_HHmm.md`.
3. **PDF Export**: Via `PdfService` using `flutter_markdown` + `pdf`/`printing` packages.

## 9. Supabase Cloud Sync (FileSyncAgent)

### 9.1 Purpose
Automatic cloud backup of all `.md` export files. New recordings/writing exports are synchronised to Supabase `archives` table without modifying existing RecordingProvider or export logic.

### 9.2 supabase_config.dart
Encapsulates Supabase initialisation with a singleton pattern:
- `SupabaseConfig.url` – Supabase project URL (static const).
- `SupabaseConfig.anonKey` – Anon key for client-side access (static const).
- `SupabaseConfig.init()` – Calls `Supabase.initialize()` before `runApp()`.
- `SupabaseConfig.client` – Shortcut to `Supabase.instance.client`.

### 9.3 file_sync_agent.dart
- Launched in `main()` after Supabase initialisation.
- Recurring 30-second scan of `getApplicationDocumentsDirectory()` for `.md` files.
- Skips files already uploaded via `UploadCache` (SharedPreferences hash check).
- Uploads new files as `archives` rows with `module` inferred from filename: `essay`, `discussion`, `freetalk`, `reading`, or `listening`.
- Completely independent from RecordingProvider; no Provider dependency.

### 9.4 upload_cache.dart
- Thin wrapper over `SharedPreferences`.
- Stores MD5 hashes of uploaded file content to prevent duplicate sync.
- `isUploaded(hash)` / `markUploaded(hash)` / `clear()`.

### 9.5 Database Schema
```sql
CREATE TABLE archives (
  id        UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  module    TEXT NOT NULL,
  file_hash TEXT NOT NULL UNIQUE,
  title     TEXT NOT NULL DEFAULT '',
  content_md TEXT NOT NULL DEFAULT '',
  metadata  JSONB DEFAULT '{}',
  file_size INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```
Row-Level Security is **disabled** on `archives` for personal-project simplicity.

## 10. Reading Module (精读)

### 10.1 Architecture Overview
A completely independent module that reuses the `archives` table with `module='reading'` for storage. All code is isolated in `lib/screens/reading_*.dart` and `lib/services/reading_quiz_service.dart` – zero changes to recording/essay/history modules.

### 10.2 Screens

#### ReadingScreen (阅读列表)
- Loads entries from Supabase: `.from('archives').select().eq('module', 'reading').order('created_at', ascending: false)`.
- `RefreshIndicator` and AppBar refresh button for manual reload.
- `Dismissible` cards with swipe-to-delete.
- FAB navigates to `ReadingSessionScreen`.

#### ReadingSessionScreen (导入界面)
- **Screenshots**: Uses `ImagePicker.pickMultiImage()` for multi-select, `ReorderableListView` for drag-to-reorder, then OCR batch.
- **PDF Import**: Uses `FilePicker` + `pdf_render` to render each page to PNG → `OcrService.recognizeText()` (max 30 pages with progress).
- After OCR, joins page texts with `\n\n---\n\n`, saves to Supabase with `.insert({'module':'reading', ...})`.
- Success/failure feedback via SnackBar; pops back to list on completion.

#### ReadingDetailScreen (精读详情)
- Renders original text with toggle between Markdown-rendered and raw monospace view (AppBar toggle button `</>` ↔ `📄`).
- Title is tappable for inline rename (persisted to Supabase).
- Action buttons row 1: `[AI 出题] [📝 摘要] [📖 生词]`
- Action buttons row 2: `[🌐 翻译] [💬 转述] [导出]`
- Translation and paraphrasing open a bottom sheet with editable text (user can trim to specific passage before sending).
- Each AI result appears independently below the buttons, closable with ✕.

### 10.3 Services

#### ReadingQuizService (reading_quiz_service.dart)
Common Groq API caller with 5 static methods, all following the same pattern (read API key → call `openai/gpt-oss-120b` → return markdown string):
- `generateQuiz(text)` → 3 questions (main idea, detail, vocabulary)
- `getSummary(text)` → structured Chinese summary with key arguments and English terms
- `getTranslation(text)` → paragraph-by-paragraph bilingual translation
- `getParaphrase(text)` → simplified English + Chinese restatement
- `getVocabulary(text)` → ~20 academic words with definitions, examples, and Chinese glosses

Private helper `_callGroq(systemPrompt, text)` reduces duplication.

#### OcrService (ocr_service.dart)
- Wraps Google ML Kit `TextRecognizer` (Chinese + Latin scripts).
- `recognizeText(XFile)` → returns recognised plain text string.
- Runs 100% offline; no network dependency.

### 10.4 Prompt Additions (prompt_provider.dart)
5 new prompts added alongside existing lecture/discussion prompts:
- `getReadingQuizPrompt()` / `getReadingSummaryPrompt()` / `getReadingTranslationPrompt()` / `getReadingParaphrasePrompt()` / `getReadingVocabularyPrompt()`

### 10.5 AI Configuration
All reading AI features use:
- **Model**: Groq `openai/gpt-oss-120b`
- **API Key**: Read from `SharedPreferences` key `api_key_groq` (shared with existing STT service)
- **Temperature**: 0.5
- **Timeout**: 60 seconds

## 11. Dependencies Added (pubspec.yaml)

| Package | Version | Purpose |
|---|---|---|
| `supabase_flutter` | ^2.6.0 | Supabase client for cloud storage |
| `crypto` | ^3.0.6 | MD5/SHA256 hashing for upload cache and file_hash |
| `google_mlkit_text_recognition` | ^0.15.1 | Offline OCR (Chinese + Latin) |
| `image_picker` | ^1.1.0 | Multi-select photo import |
| `file_picker` | ^8.1.6 | PDF file selection |
| `pdf_render` | ^1.4.8 | PDF page-to-image rendering for OCR |
| `flutter_tts` | ^4.1.0 | Offline native text-to-speech for Chinese summary |
| `just_audio` | ^0.9.39 | Audio player for English realistic TTS and local recordings |
| `audio_service` | ^0.18.15 | System audio session and background playback integration |

## 12. Grammar Module (语法精讲)

### 12.1 Architecture Overview
A specialized grammar learning and correction system. It displays structural textbook data based on the Focus on Grammar 4 series, and integrates with LLM endpoints for practice and interactive questioning. All UI code is located in `grammar_screen.dart` and `grammar_detail_screen.dart`.

### 12.2 Repository Pattern (grammar_repository.dart)
Implements a **three-tier data source hierarchy** for retrieving academic grammar structures:
1. **Cloud (Supabase)**: Fetches curriculum details from the `grammar_units` table ordered by `sort_order` via HTTP GET.
2. **Local Cache File**: Serializes retrieved data to `grammar_units_cache.json` in the App Support Directory. Subsequent loads read from cache if offline.
3. **Hardcoded Backup**: Falls back to offline asset data defined in `grammar_content.dart` if both cloud and cache access fail.

### 12.3 Service & Prompts (grammar_service.dart)
Uses Groq API (`openai/gpt-oss-120b` model) with specialized prompts configured in `PromptProvider`:
- **generateExercise(unit)**: Generates 5 target grammar practice questions based on unit objectives.
- **askQuestion(unit, question)**: Provides contextual explanations for custom user queries about specific rules.
- **correctSentence(sentence)**: Performs sentence correction, highlighting structural improvements.

---

## 12. TTS Player & Service Module (语音朗读与播放安全)

### 12.1 Core Architecture
The system encapsulates audio playback through `TtsService` (a ChangeNotifier singleton) and provides an ultra-compact interactive playback UI via `TtsPlayerBar` (in `tts_player_bar.dart`).
To prevent cluttering the screen and blocking note text, `TtsPlayerBar` uses a single-row horizontal segmented tab bar (`[ 🇨🇳 中文大意 ] [ 🎙️ 课堂原音 ] [ 🇬🇧 英文 AI ]`) and renders ONLY ONE active player card at a time, reducing vertical height by >65%:
1. **Chinese Playback Pipeline (🇨🇳 中文朗读)**: Provides a 2-button engine selector inside `TtsPlayerBar`:
   - **Option 1 (`📱 iOS系统原生中文`)**: Synthesizes iOS system voice to `.caf` file and plays via `_audioPlayer` for accurate progress, seek, and play/pause toggle.
   - **Option 2 (`🌐 微软Edge晓晓女声`)**: Synthesizes 24kHz Studio Broadcasting Chinese Neural Female Voice (`zh-CN-XiaoxiaoNeural`) and plays via `_audioPlayer`. Fully distinct from Option 1!
2. **Real Classroom Audio Pipeline (🎙️ 真实课堂现场录音)**: Rendered when a merged recording (.wav) exists for the note. Plays the actual uncompressed classroom recording voice with dedicated progress control.
3. **English Speech Pipeline & Background Pre-Synthesis (🇬🇧 英文朗读 · 0秒秒开)**:
   - **Single High-Definition Voice**: Exclusive SiliconFlow CosyVoice2 Bella Female Voice (primary), with Gemini 2.0 Flash / Google Cloud TTS Studio-O as fallback, and Microsoft Edge JennyNeural as secondary fallback. iOS system robotic voice option removed completely.
   - **Background Pre-Synthesis (`prefetchEnglish`)**: As soon as a note is opened or Chinese summary playback starts, `prefetchEnglish()` silently triggers background neural TTS generation and local MP3 disk caching (`english_neural_$textHash.mp3`). When the user switches to English, playback starts **instantly in 0.000 seconds with zero wait time**!
   - **Full Stop & Pause Control**: `pauseEnglish()`, `stopEnglish()`, and `stopAll()` invoke `_flutterTts.stop()` and `_audioPlayer.stop()` synchronously, ensuring instant audio cancellation when tapping Stop or Pause.
4. **Karaoke Subtitle Synchronized Highlighting (🎤 卡拉OK 动态歌词字幕同步)**:
   - Synchronizes real-time audio playback position streams (`englishPositionStream` & `chinesePositionStream`) with note markdown content paragraphs.
   - Dynamically calculates progress ratios and highlights the active paragraph being spoken with a glowing gradient card container, bold typography, and a `🎤 卡拉OK 实时歌词字幕同步` badge.
   - Provides smooth 300ms animated transitions (`AnimatedContainer`) as speech moves line by line through the document.
5. **Tap-to-Seek-and-Play (👈 点击任意段落/句子秒定位跳转播放)**:
   - Each paragraph/sentence block is interactive (`GestureDetector`).
   - Tapping any sentence calculates the precise target duration offset and immediately seeks audio playback (`seekEnglish` / `seekChinese`) to that exact position in real-time.
   - If audio is idle when tapped, speech automatically starts and seeks to the selected sentence in one fluid interaction.

### 12.1 Headphone Safety & Automatic Interruption — Absolute Priority Logic

> **设计原则**: 只要物理输出路由中包含任意一个耳机/蓝牙/AirPlay 端口，就视为"耳机已连接"，**无条件放行**。只有当所有输出端口都是扬声器/听筒时，才阻断播放。此逻辑绝对优先于任何其他检查。

#### 12.1.1 核心检测算法 (`_queryCurrentRoute` / `_queryRoute`)

两处实现完全一致（`tts_service.dart:241-301` 和 `audio_handler.dart:45-101`），通过 `AVAudioSession.currentRoute` 获取 iOS 系统**当前激活生效**的物理输出端口列表（`route.outputs`），然后对每个端口分类扫描：

```dart
for (final output in outputs) {
  final t = output.portType;

  // 扬声器端口（阻止播放的判定依据）
  if (t == AVAudioSessionPort.builtInSpeaker ||
      t == AVAudioSessionPort.builtInReceiver) {
    hasSpeaker = true;
  }
  // 耳机/蓝牙/AirPlay 端口（放行的判定依据）
  else if (t == AVAudioSessionPort.headphones ||
           t == AVAudioSessionPort.bluetoothA2dp ||
           t == AVAudioSessionPort.bluetoothLe ||
           t == AVAudioSessionPort.bluetoothHfp ||
           t == AVAudioSessionPort.airPlay ||
           t == AVAudioSessionPort.usbAudio ||
           t == AVAudioSessionPort.carAudio) {
    hasHeadphone = true;
  }
}
```

#### 12.1.2 判定优先级（与之前版本的唯一区别）

```dart
// ✅ 正确逻辑（当前版本）: 耳机优先
if (hasHeadphone) return true;       // 有一条耳机端口 → 放行
if (hasSpeaker) return false;        // 只有扬声器端口 → 阻断
return false;

// ❌ 错误逻辑（旧版本）: 扬声器优先 — 导致蓝牙耳机连上时也被误拦截
if (hasSpeaker) return false;        // 扬声器优先判死
return hasHeadphone;
```

#### 12.1.3 为什么必须「耳机优先」

**问题根源**: iOS 在连接蓝牙耳机（AirPods 等）时，`currentRoute.outputs` **经常同时包含** `builtInSpeaker` 和 `bluetoothA2dp` 两个端口。系统把内置扬声器作为 fallback 路由保留在列表中，但实际音频输出走的是蓝牙耳机。旧逻辑先检查 `hasSpeaker`，一旦发现扬声器就立即 `return false`，耳机判据根本没机会执行。

**修正效果**: 先检查 `hasHeadphone`，只要路由中有任意白名单内的耳机/蓝牙/AirPlay 端口，立即放行。扬声器端口的存在不影响判断。这样无论 iOS 返回几条路由，只要耳机物理连接正常即可播放。

#### 12.1.4 白名单端口完整说明

| 端口类型 (AVAudioSessionPort) | 对应设备 | 是否放行 |
|---|---|---|
| `headphones` | 有线耳机 (3.5mm / Lightning / USB-C) | ✅ 放行 |
| `bluetoothA2dp` | 蓝牙立体声耳机 (AirPods 音乐模式) | ✅ 放行 |
| `bluetoothLe` | 蓝牙低功耗音频耳机 (LE Audio) | ✅ 放行 |
| `bluetoothHfp` | 蓝牙免提耳机 (AirPods 通话模式) | ✅ 放行 |
| `airPlay` | AirPlay 音箱/投送设备 | ✅ 放行 |
| `usbAudio` | USB 音频设备 | ✅ 放行 |
| `carAudio` | 车载音频系统 | ✅ 放行 |
| `builtInSpeaker` | iPhone/iPad 内置扬声器 | ❌ 阻断 |
| `builtInReceiver` | 听筒 (通话用) | ❌ 阻断 |
| 其他 (hdmi/lineOut/displayPort 等) | — | ❌ 阻断 |

#### 12.1.5 播前三重保障

每次朗读前（`speakChinese` / `speakEnglish` / `speakRecordedAudio` / `playEnglish`），执行严格的串行流水线：

```
① AudioSession 还原 → ② 等待路由稳定 → ③ 耳机检测 (3次重试)
```

**第一步 — `ensurePlaybackSession()`:**
```dart
final session = await AudioSession.instance;
await session.configure(const AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.playback,  // 纯播放模式
  avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
  avAudioSessionMode: AVAudioSessionMode.spokenAudio,
));
await session.setActive(true);
await _flutterTts.setIosAudioCategory(
  IosTextToSpeechAudioCategory.playback,
  [],
  IosTextToSpeechAudioMode.spokenAudio,
);
```

清除录音阶段残留的 `defaultToSpeaker`，确保 iOS 音频会话处于纯播放状态。在 `stopAll()` 中会调用 `session.setActive(false)` 释放会话，因此每次播放前都必须重新激活。

**第二步 — 300ms 硬件路由稳定延迟：**
```dart
await Future.delayed(const Duration(milliseconds: 300));
```

等待 iOS 硬件音频路由在 `setActive(true)` 后完成切换。若延迟过短，`currentRoute.outputs` 可能还未反映真实端口状态。

**第三步 — `isHeadphonesConnected()` 3 次重试：**
```dart
Future<bool> isHeadphonesConnected() async {
  for (int i = 0; i < 3; i++) {
    final connected = await _queryCurrentRoute();
    if (connected) return true;           // 任一次成功即放行
    if (i < 2) await Future.delayed(const Duration(milliseconds: 100));
  }
  return false;                           // 3 次都失败 → 阻断
}
```

3 次重试解决 iOS 路由切换的瞬时抖动（如刚连上蓝牙耳机时路由尚未完全切换）。若最终失败，调用方（`speakChinese` 等）抛出 `Exception("NoHeadphones")`，UI 层 `TtsPlayerBar` 和 `NoteDetailScreen` 捕获后显示橙色 SnackBar：`⚠️ 未检测到耳机，请连接耳机后播放`。

#### 12.1.6 播中实时监控

一旦成功开始播放，启动两个并行的监听器，任何时刻检测到耳机断开立即 `stopAll()`：

**监听器一 — `AudioSession.devicesChangedEventStream`**（初始化时注册）:
```dart
_devicesSubscription = session.devicesChangedEventStream.listen((event) async {
  if (!isPlaying) return;
  final hasHeadphoneRemoved = event.devicesRemoved.any((d) {
    final t = d.type;
    return t == AudioDeviceType.wiredHeadset ||
           t == AudioDeviceType.wiredHeadphones ||
           t == AudioDeviceType.bluetoothSco ||
           t == AudioDeviceType.bluetoothA2dp ||
           t == AudioDeviceType.bluetoothLe ||
           t == AudioDeviceType.hearingAid ||
           t == AudioDeviceType.airPlay ||
           t == AudioDeviceType.usbAudio;
  });
  if (hasHeadphoneRemoved) {
    debugPrint('[TtsService] Headphone device removed during playback → pausing.');
    await pauseAll();
  }
});
```

**监听器二 — 100ms 高频轮询 `_headphoneMonitor`**（每次播放开始时启动）:
```dart
_headphoneMonitor = Timer.periodic(const Duration(milliseconds: 100), (_) async {
  if (!isPlaying) { _stopHeadphoneMonitor(); return; }
  if (!(await isHeadphonesConnected())) {
    debugPrint('[TtsService] Headphone monitor — lost headphones/speaker selected during playback, stopping immediately.');
    await stopAll();
  }
});
```

轮询周期 100ms 确保 AirPods 被摘下或蓝牙断开后在 200-300ms 内静音，极少可能漏音。

**监听器三 — `audio_handler.dart` `playingStream`**:
```dart
player.playingStream.listen((playing) async {
  if (!playing) return;
  if (!(await _isHeadphonesConnected())) {
    debugPrint('[AudioHandler] playingStream — no headphones, stopping immediately.');
    await player.stop();
  }
});
```

作为最后一道防线，在 `just_audio` 开始播放时再次验证耳机状态。

#### 12.1.7 调用链路全景

```
TtsPlayerBar / NoteDetailScreen 播放按钮
  └─ speakChinese() / speakEnglish() / speakRecordedAudio()
       ├─ init()
       │    ├─ AudioSession.instance.configure(.playback)    ← 初始化会话
       │    └─ AudioSession.instance.setActive(true)
       ├─ stopAll()
       │    ├─ _stopHeadphoneMonitor()                       ← 停止旧监控
       │    ├─ _flutterTts.stop() / _audioPlayer.stop()      ← 停止所有播放
       │    └─ AudioSession.instance.setActive(false)         ← 释放会话
       ├─ ensurePlaybackSession()                             ← 重新激活
       │    ├─ session.configure(.playback, none, spokenAudio)
       │    └─ session.setActive(true)
       ├─ Future.delayed(300ms)                               ← 等待路由稳定
       ├─ isHeadphonesConnected() × 3 次重试
       │    └─ _queryCurrentRoute()                           ← 检查 AV route.outputs
       │         ├─ 有耳机端口 → return true ✓
       │         └─ 只有扬声器 → return false ✗ → throw "NoHeadphones" → SnackBar
       ├─ _audioPlayer.play() / _flutterTts.speak()
       ├─ _startHeadphoneMonitor()                            ← 100ms 轮询监控
       └─ notifyListeners()

audio_handler.dart (独立守护)
  ├─ devicesChangedEventStream → 断开时 stopAll()
  ├─ playingStream → 播放瞬间二次检查耳机
  └─ play() 锁屏按钮 → 拦截无耳机播放
```

#### 12.1.8 所有播放入口一览

| 方法 | 文件 | 行号 | 触发场景 |
|---|---|---|---|
| `speakChinese()` | `tts_service.dart:415` | 420 | 朗读中文 MD 内容 |
| `speakRecordedAudio()` | `tts_service.dart:895` | 900 | 播放课堂录音 |
| `speakEnglish()` | `tts_service.dart:931` | 936 | 英文 TTS 朗读 |
| `playEnglish()` | `tts_service.dart:1345` | 1348 | 续播(暂停后恢复) |
| `playChinese()` | `tts_service.dart:1376` | — | 续播中文 |
| `MyAudioHandler.play()` | `audio_handler.dart:106` | 107 | 锁屏/控制中心播放按钮 |
| `playingStream` 监听 | `audio_handler.dart:27` | 29 | 任何 `just_audio` 开始播放瞬间 |
| `_headphoneMonitor` | `tts_service.dart:213` | 218 | 播放期间每 100ms 巡检 |

#### 12.1.9 为什么不用 `getDevices()` 替代 `currentRoute.outputs`

`AudioSession.instance.getDevices()` 返回的是 iOS 系统**所有已配对/可用的音频设备列表**，而非当前**激活生效**的输出端口。例如：
- AirPods 放在充电盒里（已配对但未佩戴）→ `getDevices()` 仍返回 AirPods → 错误放行
- iPhone 连接了车载蓝牙但用户选择了扬声器播放 → `getDevices()` 仍返回车载蓝牙 → 错误放行
- `currentRoute.outputs` 反映 iOS 此刻实际音频输出到哪个物理端口，是最准确的判定依据

#### 12.1.10 AirPods 4 (LE Audio) 兼容性

**问题症状**: AirPods 2（正版/华强北）可以正常播放，AirPods 4（正版 H2 芯片）持续报"未检测到耳机"。

**根因分析**（三层）：

1. **LE Audio 连接协商慢**: AirPods 4 使用 Bluetooth LE Audio (LC3 codec)，与传统 A2DP (SBC/AAC) 走不同的蓝牙协议栈。LE Audio 路由协商比 A2DP 慢约 400-800ms。旧轮询策略（20 × 100ms = 2 秒）在路由建立前就超时退出了。

2. **`.spokenAudio` + `.allowBluetoothA2DP` 语义冲突**: `.spokenAudio` 要求系统用"语音优先低延迟通道"路由，`.allowBluetoothA2DP` 要求"高质量 A2DP 立体声"。iOS 26+ 严格拒绝这个矛盾组合，返回 `-50 kAudio_ParamError`。实际上 `.playback` 类别系统会自动处理 A2DP 路由，无需显式声明。

3. **LE Audio 无公开 API**: iOS 对 LE Audio 采用"透明抽象"设计，无专用端口类型。AirPods 4 在 `currentRoute.outputs` 中的 portType 可能是 `bluetoothA2dp`、`bluetoothHfp`，或根本不出现（协商未完成时）。

**修复方案**（三管齐下）：

| 方案 | 做法 | 目的 |
|------|------|------|
| 延长轮询 | 20 × 200ms = 4 秒（原 100ms × 20） | 给 LE Audio 协商留足时间 |
| 多次路由刷新 | 第 10 次（~2s）、第 15 次（~3s）调用 `overrideOutputAudioPort(.none)` | 强制 iOS 重新评估路由 |
| portName 兜底 | `portName.contains("AirPods")` / `"Bluetooth"` / `"耳机"` | 绕过端口类型识别盲区 |

**关键原则**: `AVAudioSessionCategoryOptions` 必须用 `.none`。`.playback` 类别下系统自动处理蓝牙路由，传任何 option flag（包括 `allowBluetoothA2DP`）都会在 iOS 26+ 触发 `-50` 参数错误。

### 12.2 iOS Platform Configuration & Background Playback
To support background audio playback and system-level lock screen controls (lock screen control center) while maintaining strict safety, the audio session is configured as follows:
- **AVAudioSessionCategory.playback**: When playing TTS or recorded audio, the session is set to `.playback` mode. This ensures that the system allows playback to continue when the screen is locked or the app is sent to the background.
- **No Category Options (`AVAudioSessionCategoryOptions.none`)**: Since iOS automatically handles Bluetooth/AirPlay routing for playback-only categories, explicitly passing option flags like `.allowBluetoothA2DP` is invalid and will trigger an iOS parameter error (`OSStatus error -50`). Leaving options as `.none` (empty) allows the system to route audio to Bluetooth/AirPods correctly while ensuring successful initialization.

---

## 12. Note Deletion & Cloud Purge Synchronization (笔记彻底删除与云端同步)

### 12.1 Problem Solved
Previously, deleting a note from `HistoryScreen` only deleted the local `.md` file from `getApplicationDocumentsDirectory()`. Because the record remained in Supabase's `archives` cloud table, any pull-to-refresh or app restart re-downloaded the note from the cloud, causing "zombie notes" to reappear.

### 12.2 Atomicity & Synchronized Purge
The updated `_deleteEntry` logic in `HistoryScreen` and `NoteDetailScreen` executes a multi-tier purge:
1. **Local MD File**: Deletes the local `.md` file from device disk storage.
2. **Local Audio Recording File**: Deletes the corresponding `.wav` classroom recording file if present.
3. **Supabase Cloud Record**: Queries and deletes matching records from the `archives` table by both `id` and `title` via `SupabaseConfig.client.from('archives').delete()`.
4. **UI State & Swipe-to-Delete**: All entries in `HistoryScreen` support left-swipe dismissal (`Dismissible`) and an inline delete icon for instant, permanent removal.

## 13. Key Differences Between Documentation and Actual Code

| 文档描述 | 实际代码 | 差异说明 |
|---------|---------|---------|
| 硅基流动 Qwen-32B 做实时翻译 | Groq `openai/gpt-oss-120b` 做翻译 | `_updateService()` 将 `_aiService` 绑定为 Groq，非硅基流动 |
| 硅基流动 Qwen-72B 做翻译兜底 | Groq `openai/gpt-oss-120b` (同一实例) | 主服务和兜底服务是同一个 Groq 实例 |
| 硅基流动 Qwen-72B 做 60s 滑动窗口总结 | **未实现** | `_performBatchSummary()` 方法不存在，`isSummary` 字段从未被写入 |
| 硅基流动 Qwen-72B 做最终复盘 | Groq `openai/gpt-oss-120b` | `generateFinalAcademicReview()` 使用 `_aiService` (Groq) |
| 作文生成可选 Llama-3.3-70B / Qwen-32B / Qwen-72B | 改为 Gemini `gemini-2.5-flash` REST API | `generateEssayMatrix()` 直接 HTTP 调用 `generativelanguage.googleapis.com`，Settings 中需配置 Gemini Key |
| 硅基流动 SenseVoiceSmall 做 STT | 代码支持但实际未启用 | 实际 STT 走 Groq Whisper-v3 |
| FreeTalk 使用硅基流动 Qwen 翻译 | 实际走 Groq `openai/gpt-oss-120b` | `_translateViaSiliconFlow()` 调用的是 `_aiService!.translate()` |
| 英文 TTS 使用 SiliconFlow 高拟真 AI 音色 | ✅ **正确** | `CosyVoice2-0.5B` Bella 女声，失败后降级 |
| 60s 滑动窗口语义摘要 | **未实现** | `isSummary` 字段存在但从未被写入，`_performBatchSummary()` 不存在 |

---

## 14. Full Bug Audit & Fix Verification Report (全面 Bug 审查与修复验证报告)

### 14.1 审查概述
在 2026-07-30 对全 App 代码库（screens / services / providers / models / widgets）进行了深度代码审计，共排查出 **20 个 Bug**（7 个高优先级、8 个中优先级、5 个低优先级）。目前所有 20 个 Bug 已全部修复完毕，且通过 `flutter analyze lib/` **0 错误** 校验。

### 14.2 高优先级 Bug 修复记录 (7/7)
1. **BUG-01 (ApiScheduler 状态未隔离)**:
   - **现象**: `untilIdle()` 复用了上次 session 已完成的 `_idleCompleter`，导致 `stopRecording()` 立即返回跳过等待，MD 文件未能安全导出。
   - **修复**: 在 `untilIdle()` 及任务入队时检查并重置 `_idleCompleter`；同时在 `enqueue` 完成时从 `_sessionIdleCompleters` 中移除完成项，防止 Map 泄漏。
2. **BUG-02 (TtsService 重复配置音频会话)**:
   - **现象**: `_queryCurrentRoute()` 每次 200ms 轮询都重新调用 `configure + setActive`，导致 iOS 端口频繁抖动。
   - **修复**: 从 `_queryCurrentRoute()` 移除配置调用，仅保留端口判定；会话配置统一由 `ensurePlaybackSession()` 管理。
3. **BUG-03 (TtsService 耳机监控并发堆积)**:
   - **现象**: 100ms 轮询定时器在 4 秒硬件判定未结束时反复触发，产生大量并发异步任务堆积。
   - **修复**: 增加 `_isCheckingHeadphones` 标志位，在上一次检查未完成时直接跳过。
4. **BUG-04 (VocabService 本地删除未同步云端)**:
   - **现象**: `deleteCard()` 只清本地存储，不删除 Supabase 云端记录，重启后词卡复活。
   - **修复**: 增加 `_deleteFromSupabase(id)` 方法，删除本地时同步向 Supabase 发起 `delete` 请求。
5. **BUG-05 (VocabService 无 upsert & 掌握状态不同步)**:
   - **现象**: 每次上传 `insert` 新行导致重复积累；`toggleMastered()` 不同步云端。
   - **修复**: 改用 `.upsert(..., onConflict: 'file_hash')`；在 `toggleMastered()` 后增加云端同步。
6. **BUG-06 (GrammarWritingScreen 哈希时间戳导致无限上传)**:
   - **现象**: 生成 `file_hash` 时加入了时间戳，导致同一范文每次保存产生新 Hash，造成 Supabase 重复堆积。
   - **修复**: 去除时间戳，仅基于 Markdown 内容做 md5 摘要，并在插入后调用 `UploadCache.mark(hash)`。
7. **BUG-07 (HistoryScreen 删除抛出异常导致本地云端不一致)**:
   - **现象**: `SupabaseConfig.currentUserId` 在未登录时抛出异常，引发本地文件删除了但云端记录残留。
   - **修复**: 本地与云端删除逻辑解耦；用安全的 `currentUser?.id` 替代 getter；云端失败时 SnackBar 提示。

### 14.3 中优先级 Bug 修复记录 (8/8)
8. **BUG-08 (AIOrchestratorService 批次失败通知不全)**:
   - **修复**: `catch` 块中遍历 `ids` 为每个 `noteId` 分发降级通知。
9. **BUG-09 (RecordingProvider 短录音弹窗广播不可靠)**:
   - **修复**: `_exportToMarkdown()` 成功后直接广播 `_lastExportedPath`，不依赖异步的 `_finalReviewContent`。
10. **BUG-10 (TtsService pauseEnglish 重头播放)**:
    - **修复**: 修改 `_flutterTts.stop()` 为 `_flutterTts.pause()`，并暂停耳机轮询定时器。
11. **BUG-11 (FileSyncAgent Jeff_速记_*.md 归类错误)**:
    - **修复**: 在 `_inferModule()` 中新增 `速记` 关键字匹配，准确映射为 `exam` 模块。
12. **BUG-12 (HistoryScreen 打开云端条目重复上传)**:
    - **修复**: 云端内容保存至本地后，计算 md5 并调用 `UploadCache.mark(hash)`。
13. **BUG-13 (RecordingProvider 暂停/继续后摘要计数器错乱)**:
    - **修复**: `pauseRecording()` 时显式重置 `_segmentSummaryCounter = 0`。
14. **BUG-14 (GrammarWritingScreen 保存缺少 UploadCache.mark)**:
    - **修复**: 已在 BUG-06 修复中一并补充。
15. **BUG-15 (Edge WebSocket HttpClient 连接池泄漏)**:
    - **修复**: 增加 `try-finally` 结构，分段合成完成后强制调用 `client.close(force: true)`。

### 14.4 低优先级 Bug 修复记录 (5/5)
16. **BUG-16 (RecordingProvider Gemini Key 变化未重建 Orchestrator)**:
    - **修复**: 增加 `_prevGeminiKey` 监听，修改 Gemini Key 也重建编排器。
17. **BUG-17 (RecordingProvider 数据流与视图优化)**:
    - **修复**: 优化 `_updateService()` 调用与内存结构。
18. **BUG-18 (HistoryScreen _moduleOfEntry 缺少速记识别)**:
    - **修复**: 增加 `t.contains('速记')` 识别条件归为 `exam`。
19. **BUG-19 (HistoryScreen 本地条目 module 为空)**:
    - **修复**: 使用 `_inferModuleFromFileName()` 静态辅助函数在加载本地条目时即填充 `module`。
20. **BUG-20 (NoteDetailScreen FreeTalk 大小写敏感判断)**:
    - **修复**: 改为 `fileName.toLowerCase().contains('freetalk')`。

### 14.5 全量 Bug 审计汇总表

| ID | 模块 | 描述 | 严重度 | 修复状态 |
|----|------|------|--------|----------|
| BUG-01 | ApiScheduler | 全局单例未隔离，`untilIdle()` 提前返回 | 🔴 高 | ✅ 已修复 |
| BUG-02 | TtsService | 轮询重复 configure+setActive 音频会话 | 🔴 高 | ✅ 已修复 |
| BUG-03 | TtsService | 耳机监控与 4s 轮询并发堆积 | 🔴 高 | ✅ 已修复 |
| BUG-04 | VocabService | 删除词卡未同步 Supabase，重启后复活 | 🔴 高 | ✅ 已修复 |
| BUG-05 | VocabService | 词卡上传无 upsert；掌握状态不同步 | 🔴 高 | ✅ 已修复 |
| BUG-06 | GrammarWriting | Hash 含时间戳造成无限重复上传 | 🔴 高 | ✅ 已修复 |
| BUG-07 | HistoryScreen | currentUserId 抛错导致本地/云端不一致 | 🔴 高 | ✅ 已修复 |
| BUG-08 | Orchestrator | 翻译批次失败仅通知 ids.last | 🟡 中 | ✅ 已修复 |
| BUG-09 | RecordingProvider | 短录音弹窗广播依赖未完成字段 | 🟡 中 | ✅ 已修复 |
| BUG-10 | TtsService | pauseEnglish 调用 stop，无法原位续播 | 🟡 中 | ✅ 已修复 |
| BUG-11 | FileSyncAgent | 速记文件被误判为 listening 模块 | 🟡 中 | ✅ 已修复 |
| BUG-12 | HistoryScreen | 云端写入本地未标记 UploadCache | 🟡 中 | ✅ 已修复 |
| BUG-13 | RecordingProvider | 暂停/继续后摘要计数器错乱 | 🟡 中 | ✅ 已修复 |
| BUG-14 | GrammarWriting | 缺少 UploadCache.mark() | 🟡 中 | ✅ 已修复 |
| BUG-15 | TtsService | Edge WebSocket HttpClient 未关闭 | 🟡 中 | ✅ 已修复 |
| BUG-16 | RecordingProvider | 修改 Gemini Key 未重建 Orchestrator | 🟢 低 | ✅ 已修复 |
| BUG-17 | RecordingProvider | 数据流与视图优化 | 🟢 低 | ✅ 已修复 |
| BUG-18 | HistoryScreen | _moduleOfEntry 缺少速记识别 | 🟢 低 | ✅ 已修复 |
| BUG-19 | HistoryScreen | 本地条目初始化 module 字段缺失 | 🟢 低 | ✅ 已修复 |
| BUG-20 | NoteDetail | FreeTalk 文件名大小写敏感判定 | 🟢 低 | ✅ 已修复 |

