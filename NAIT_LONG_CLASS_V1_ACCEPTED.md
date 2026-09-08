# NAIT Long-Class V1 Pipeline Accepted

## Final Verdict
**ACCEPTED**

The NAIT long-class V1 reliability pipeline is fully verified, operational, and accepted for real-class use on 60–120 minute sessions.

> **Explicit Policy**:
> Do not redesign or re-audit the long-class pipeline unless a real regression is observed.

---

## Real-Class Acceptance Evidence
- **Real Session**: `20260904` (Week 1, `real_class`, 107 minutes duration).
- **Transcript**: 1,534 timestamped entries (~470 KB JSON).
- **Audio Intact**: Full 107-minute normalized PCM WAV (205,984,504 bytes) remained completely intact without physical audio splitting.
- **Chunk Execution**: 7 total chunks (~16.5m duration, ~4.1k–4.7k tokens each).
  - Chunk 0: COMPLETED via Groq fallback after Gemini 503.
  - Chunk 1: COMPLETED via Groq fallback after Gemini 503.
  - Chunk 2: REUSED directly from local cache (`chunk_02.json`) with zero duplicate AI network requests.
  - Chunk 3: COMPLETED via Gemini primary.
  - Chunk 4: COMPLETED via Gemini primary.
  - Chunk 5: COMPLETED via Gemini primary.
  - Chunk 6: COMPLETED via Gemini primary.
- **Consolidation**: Deterministic consolidation merged all 7 chunks into final structured analysis (`session.status = processed`).
- **Operational Completeness**: 24 MustDo, 14 Important, 2 NextClass, 21 TechnicalPoints fully preserved from lecture.
- **English Extraction & Accuracy**: 68 classroomEnglish phrases extracted; 100% of sampled teacher-original items verified against transcript text and timestamps.
- **Practice Separation**: 12 practice items strictly labeled `practice_sentence`; zero mislabeled as teacher-original.
- **Listening Clips**: 68 audio clips extracted cleanly from full normalized WAV.
- **Listening Pack**: Generated successfully at `real_class_test/acceptance/nait/real_class/week_01/listening_pack.wav` (17,907,244 bytes).

---

## Final Architecture Summary
1. **Hybrid Timestamp-Aware Chunking** (`NaitChunkingService`):
   - Pure-Dart service slicing transcripts into overlapping segments (~17 min target window, 90s overlap).
   - Preserves entry boundaries (never splits individual transcript entries).
   - Snaps to natural pauses (>= 4.0s silence in ±45s search window) when available.
   - Enforces configurable token safety budget (default 6,000 tokens) to prevent provider payload limits.
   - Preserves absolute timestamps across all chunks.

2. **Per-Chunk Sequential AI Pipeline with Bounded Retry & Fallback** (`NaitProcessingService`):
   - Sequential per-chunk processing (no concurrency storms).
   - Gemini primary (`gemini-2.5-flash`) with bounded exponential backoff retry for transient 429/503/timeouts.
   - Groq fallback (`openai/gpt-oss-120b`) triggered only if Gemini retries fail on that specific chunk.
   - 1.0s pacing delay between chunks.

3. **Incremental Manifest Persistence & Resume**:
   - `chunks/chunk_manifest.json` tracks chunk state (`pending`, `processing`, `completed`, `failed`), provider used, and error diagnostics.
   - `chunks/chunk_XX.json` persists completed chunk results atomically via temporary file and rename.
   - On resume, completed chunks load from disk; only pending or failed chunks are sent to AI.
   - Partial failures preserve completed chunks and mark `session.status = partial` without presenting partial data as complete.

4. **Deterministic Consolidation** (`NaitConsolidationService`):
   - Zero secondary LLM summarization calls.
   - Chronological merge across all completed chunks.
   - Lexical overlap deduplication (token overlap >= 70% or Jaccard >= 0.55) to discard overlap duplicates while retaining distinct operational instructions.
   - Repeated classroom English across distant timestamps boosts priority and appearance count.
   - Strict segregation of `teacher_original` vs `practice_sentence`.

---

## Files Changed for Long-Class V1
- `lib/nait_learning/services/nait_chunking_service.dart` [NEW]
- `lib/nait_learning/services/nait_consolidation_service.dart` [NEW]
- `lib/nait_learning/services/nait_processing_service.dart` [MODIFIED]
- `lib/nait_learning/models/nait_class_session.dart` [MODIFIED - added `partial` status and getter]
- `lib/nait_learning/widgets/nait_class_card.dart` [MODIFIED - handled `partial` status and warning badge]
- `lib/prompt_provider.dart` [MODIFIED - added `getNaitChunkAnalysisPrompt()`]
- `test/nait_learning/nait_chunking_service_test.dart` [NEW]
- `test/nait_learning/nait_consolidation_service_test.dart` [NEW]
- `test/nait_learning/nait_processing_chunk_retry_test.dart` [NEW]
- `real_class_test/acceptance/runner.dart` [MODIFIED - retry and fallback logging]
- `real_class_test/acceptance/single_chunk_runner.dart` [NEW - single chunk validation runner]

---

## Tests Passed
- `flutter analyze`: 0 errors, 0 warnings across all 11 changed and test files.
- `nait_chunking_service_test.dart`: 5/5 passed (short transcript, 60m synthetic, 120m synthetic, pause snapping, token safety ceiling).
- `nait_consolidation_service_test.dart`: 4/4 passed (overlap deduplication, lab step ordering, frequency/priority boost, practice sentence labeling).
- `nait_processing_chunk_retry_test.dart`: 3/3 passed (Gemini transient 503 retry, Groq fallback after retry exhaustion, cache resume).
- Real 107-minute E2E acceptance: PASS with all 7 chunks completed and listening pack generated.

---

## Known Remaining Risk
- Free-tier rate limits or transient high-demand spikes on Gemini API can cause 90s timeouts or 503 errors during long classes. The implemented bounded retry and Groq fallback architecture provenly mitigates this without data loss or user intervention.
