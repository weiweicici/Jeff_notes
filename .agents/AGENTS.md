# Project Rules for Jeff Notes

## Headphone Detection & Audio Safety Rules (iOS / Android)
1. **AVAudioSession Category Recovery**:
   - Before checking headphones or starting TTS / audio playback (`speakChinese`, `speakEnglish`, `playChinese`, `playEnglish`, `speakRecordedAudio`), `TtsService` MUST call `ensurePlaybackSession()`.
   - `ensurePlaybackSession()` re-configures `AudioSessionCategory` to `playback` with `AVAudioSessionCategoryOptions.none` and activates it (`setActive(true)`).
   - This clears any `playAndRecord` + `defaultToSpeaker` options left by the recording provider.

2. **Strict Speaker Blocking on iOS**:
   - On iOS/macOS, `_queryCurrentRoute()` MUST inspect `AVAudioSession.currentRoute.outputs`.
   - If `currentRoute.outputs` contains `builtInSpeaker` or `builtInReceiver`, it MUST return `false` IMMEDIATELY (blocked).
   - NEVER return `true` based solely on `AudioSession.instance.getDevices()`, because paired Bluetooth devices remain in `getDevices()` even when headphones are taken out of ears or when audio output has routed to the built-in speaker.

3. **Microsoft Edge TTS WebSocket Credentials & Sec-MS-GEC**:
   - URL: `wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4&Sec-MS-GEC=$secMsGec&Sec-MS-GEC-Version=1-143.0.3650.75`
   - TrustedClientToken: `6A5AA1D4EAFF4E9FB37E23D68491D6F4`
   - Sec-MS-GEC formula: 100-nanosecond Windows FileTime ticks since Jan 1, 1601 (`(unixSec + 11644473600) * 10000000`), aligned to 5-minute intervals (`ticks -= (ticks % 3000000000)`), hashed via SHA256 with the token.
   - Headers: Must pass `Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold`, `Cookie: muid=$muid;`, and custom `HttpClient` with Chrome/Edge User-Agent to prevent 401/403 HTTP errors.
