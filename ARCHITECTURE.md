# Jeff Notes: Full Technical Specification & Architecture

## 1. System Overview
Jeff Notes is a production-grade academic assistant designed for high-concurrency audio transcription and professional academic translation. It operates on a **Session Isolation Architecture**, decoupling the active recording lifecycle from background AI finalization.

## 2. Core Data Flow (Hybrid-Core Token-Economy Architecture)
```mermaid
graph TD
    A[AudioRecorder] -->|5s-15s Slices| B[Tail Stitching Logic]
    B -->|WAV Header Correction| C[AIOrchestratorService]
    C -->|Priority 0| D[Groq Whisper STT]
    D -->|English Stream| E[RecordingProvider]
    C -->|Batching x3| F[Priority 1: OpenRouter Gemini 2.0 Flash Translation]
    F -->|Chinese Subtitles| E
    F -.->|Fallback兜底| SF[SiliconFlow Qwen-72B Translation]
    SF -.->|Chinese Subtitles| E
    E -->|Background Isolate| G[Shadow Cache JSON]
    E -->|On Stop| H[Finalizing Queue]
    H -->|Active Polling Wait| I[OpenRouter Gemini 2.0 Flash Final Recap]
    E -->|60s Sliding Window| QW[SiliconFlow Qwen-72B Semantic Summary]
    QW -->|Part 2 Blocks| G
    I -->|sessionReadyStream| J[UI Auto-Popup & MD Export]
```

## 3. Session Isolation & Concurrency
To allow users to start a new recording immediately after stopping the previous one, the system uses a **Finalizing Queue**:
- **LectureSession**: Every recording is encapsulated in a `LectureSession` object containing its own notes, orchestrator, and mode (Lecture/Discussion).
- **Decoupling**: When `stop()` is called, the `_activeSession` is moved to `_finalizingSessions`. The UI is immediately cleared for the next recording.
- **Background Finalization**: A non-blocking `_finalizeSession` task handles buffer flushing, STT/Translation settlement polling, final recap generation, and file exporting.

## 4. AI Orchestration & Mode Handling
### 4.1 Mode-Specific Pipelines
The system adapts its prompt strategies and UI rendering based on the `AppMode`:
- **Academic Lecture**: Focuses on `Thesis Statement` and `Logic Maps`. Exports structured 60s Block Summaries and sequentially outputs Chinese and English scripts. UI uses **Blue** accents and `school` icons.
- **Group Discussion**: Focuses on strict `Concise Paraphrasing (Bilingual)` and `Discussion Starters` (expressing opinion, citing statistics, tag questions). Explicitly filters out 60s block summaries and outputs fully consolidated English and Chinese scripts. UI uses **Purple** accents and `forum` icons.
- **Mode-Parameter Fix**: Resolved a leak in finalization review generation (`generateFinalAcademicReview()`) and block summaries (`_performBatchSummary()`) where the absence of a `mode` parameter caused Group Discussion to revert to Lecture recap mode. Mode states are now strictly propagated to the semantic summarizing system.

### 4.2 AIOrchestratorService
Acts as the central bus between raw text and intelligence.
- **Fast Track**: Sends every single text slice to the `fastEnglishStream` via Groq Whisper.
- **Slow Track (Translation)**: Buffers 3 slices into a `_translationBuffer`. Once full, triggers the translation API.
- **Hybrid Routing**: Uses `google/gemini-2.0-flash` on OpenRouter as the primary interpreter to maximize translation speed (under 1s) and slash latency. High-volume translations automatically fallback to `Qwen/Qwen2.5-72B-Instruct` via SiliconFlow in case of rate limits (HTTP 429) or timeouts, safeguarding UI stability.
- **Ghost-Fragment Handlers**: Includes dedicated null-state injection logic (`PipelineResult(id, " ")`) to prevent translation allocation starvation when Chinese sentence counts fall short of English chunks, ensuring finalization polling loops do not dead-wait.
- **Batching Strategy**: Automatically adjusts based on whether the session is active or being flushed.

### 4.3 ApiScheduler (The Traffic Cop)
- **4 Parallel Slots**: Manages 4 concurrent network requests across all sessions.
- **Prioritization**: `Priority 0` (STT) always preempts `Priority 1` (Summary/Translation).
- **untilSessionIdle(id)**: (Deprecated in favor of active settlement polling to eliminate race conditions).

## 5. Event-Driven UI & Auto-Popup
The UI does not poll for summary completion. Instead, it uses a **Reactive Notification Stream**:
- **sessionReadyStream**: A broadcast stream in `RecordingProvider`.
- **Trigger**: Emits the final recap content only when `_finalizeSession` is 100% complete.
- **Consumption**: `NotesScreen` listens to this stream and automatically triggers the `FinalReviewModal` regardless of the user's current interaction.

## 6. Audio Ingestion & Stitching Protocol
- **Overlap-Stitch Algorithm**: Captures a trailing 25,600 byte PCM segment (`kTailSize`) to prevent word-chopping at slice boundaries.
- **WAV Integrity**: Manually generates a 44-byte WAV header for each slice in a background Isolate.

## 7. Domain-Specific Translation (EAL Optimized)
- **Philosophy**: Uses a **Simultaneous Interpreter Prompt` with strict temperature (`0.1`) to ensure academic tone and technical term preservation.

## 8. Data Persistence Hierarchy
1. **Shadow Cache (Ephemeral)**: `shadow_draft.json` updated on every translation for crash recovery.
2. **MD Export (Permanent)**: Validated and exported upon session settlement. Format strictly adapts to AppMode to ensure maximum readability for the specific use case.

## 9. Development Environment (Hybrid Distributed Engine)
- **STT (Fast Track)**: Groq API (`whisper-large-v3`).
- **Translation (Real-Time)**: OpenRouter (`google/gemini-2.0-flash`) as primary, SiliconFlow (`Qwen/Qwen2.5-72B-Instruct`) as secondary fallback.
- **60s Sliding Summary (Background)**: SiliconFlow (`Qwen/Qwen2.5-72B-Instruct`) to preserve main-channel bandwidth and keep prompt execution highly accurate.
- **Final Summary (Intelligence)**: OpenRouter (`google/gemini-2.0-flash`) for rapid, high-context, cost-effective generation.
- **Framework**: Flutter 3.24.0+ (iOS 15.5+).
