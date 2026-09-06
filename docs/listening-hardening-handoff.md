# Listening hardening acceptance evidence

- Translation is now two bounded, per-note workers. Each request retains its note ID and captured history; no sentence splitting or reallocation occurs. The direct queue test queues eight slices, observes a peak of two workers and queue peak eight, then drains all eight in note order. A `fake_async` production-orchestrator test drives mock-Gemini responses at 12 seconds for 2,160 inputs over virtual three hours: peak live backlog is exactly 22 queued + 2 active (the configured 24-item bound); roughly 300-400 notes are durably deferred depending on shared-lane test timing. It does not claim real-time Chinese stability: 2 workers at 12 seconds provide one result/6 seconds, below a 5-second input cadence.
- The scheduler no longer releases a slot through a detached 60-second `Future.timeout`. Gemini and Groq translation requests use `http.AbortableRequest`: timeout aborts the individual transport without closing the shared session client. The scheduler test proves a session remains in-flight until the task settles.
- A conservative detector only retries an unchanged, complete, prose-like English result with no Chinese. Commands, IP addresses and paths are excluded. One repair claim is persisted per note in shadow drafts; original subtitles display first, repair is background-only, and failure leaves the original plus durable pending state. Repeated finalization and a restarted context make zero additional repair requests after the one failed repair.

Verification run:

```text
flutter test test/listening_translation_hardening_test.dart test/api_scheduler_lane_test.dart test/translation_mapping_order_test.dart test/translation_recovery_test.dart
# 16 passed
```

`flutter analyze` on the touched listening files had no errors; four pre-existing style infos remain in `ai_orchestrator_service.dart` and `shadow_draft_service.dart`.

The slow-provider degradation is intentional and recoverable: English is emitted before translation admission; overflow remains in the shadow draft for later recovery rather than growing process memory without bound. This is simulated transport/queue evidence, not a substitute for three long real-device lectures or provider-side cancellation telemetry.
