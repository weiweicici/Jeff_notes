import Foundation

/// Controls the iPhone TTS player through WatchConnectivity.
///
/// The Watch keeps the synced text for reference, but audio always plays on
/// the iPhone and therefore uses the iPhone's current Bluetooth/output route.
@MainActor
final class WatchPlaybackController: ObservableObject {
    @Published private(set) var document: WatchDocument?
    @Published private(set) var currentSentenceIndex = 0
    @Published private(set) var isPlaying = true
    @Published private(set) var loopEnabled = true
    @Published private(set) var speed: Float = 1.0
    @Published private(set) var errorMessage: String?

    var currentSentence: WatchSentence? {
        guard let sentences = document?.manifest.sentences,
              sentences.indices.contains(currentSentenceIndex) else { return nil }
        return sentences[currentSentenceIndex]
    }

    var sentencePositionLabel: String {
        guard let count = document?.manifest.sentences.count, count > 0 else { return "" }
        return "\(currentSentenceIndex + 1)/\(count)"
    }

    func load(_ document: WatchDocument) {
        guard self.document?.id != document.id else { return }
        self.document = document
        currentSentenceIndex = 0
        isPlaying = true
        loopEnabled = document.manifest.loopEnabled
        errorMessage = nil
    }

    func togglePlayPause() {
        isPlaying.toggle()
        send("togglePlayPause")
    }

    func previousSentence() {
        currentSentenceIndex = max(0, currentSentenceIndex - 1)
        send("previousSentence")
    }

    func nextSentence() {
        guard let count = document?.manifest.sentences.count, count > 0 else { return }
        currentSentenceIndex = min(count - 1, currentSentenceIndex + 1)
        send("nextSentence")
    }

    func seekBy(seconds: TimeInterval) {
        send(seconds < 0 ? "rewind5" : "forward5")
    }

    func toggleLoop() {
        loopEnabled.toggle()
        send("toggleLoop")
    }

    func cycleSpeed() {
        let speeds: [Float] = [0.75, 1.0, 1.25, 1.5]
        let current = speeds.firstIndex(of: speed) ?? 1
        speed = speeds[(current + 1) % speeds.count]
        send("setSpeed:\(speed)")
    }

    private func send(_ command: String) {
        errorMessage = nil
        Task { [weak self] in
            do {
                try await WatchConnectivityReceiver.shared.sendRemoteCommand(command)
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }
}
