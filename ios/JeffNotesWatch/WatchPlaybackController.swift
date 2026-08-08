import AVFoundation
import Foundation

@MainActor
final class WatchPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var document: WatchDocument?
    @Published private(set) var currentSentenceIndex = 0
    @Published private(set) var currentRepeatIndex = 1
    @Published private(set) var isPlaying = false
    @Published var loopEnabled = true
    @Published var speed: Float = 1.0
    @Published var repeatMode: SentenceRepeatMode = .documentDefault
    @Published private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var transitionTask: Task<Void, Never>?
    private var handlingSentenceEnd = false

    var currentSentence: WatchSentence? {
        guard let sentences = document?.manifest.sentences,
              sentences.indices.contains(currentSentenceIndex) else { return nil }
        return sentences[currentSentenceIndex]
    }

    var sentencePositionLabel: String {
        guard let count = document?.manifest.sentences.count, count > 0 else { return "" }
        return "\(currentSentenceIndex + 1)/\(count) · \(currentRepeatIndex)/\(targetRepeatCount)次"
    }

    var targetRepeatCount: Int {
        if repeatMode.rawValue > 0 { return repeatMode.rawValue }
        return min(max(currentSentence?.repeatCount ?? 1, 1), 3)
    }

    func load(_ document: WatchDocument) {
        guard self.document?.id != document.id else { return }
        stop()
        self.document = document
        loopEnabled = document.manifest.loopEnabled
        currentSentenceIndex = 0
        currentRepeatIndex = 1
        errorMessage = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                policy: .longFormAudio,
                options: []
            )
            try session.setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: document.audioURL)
            newPlayer.delegate = self
            newPlayer.enableRate = true
            newPlayer.rate = speed
            newPlayer.prepareToPlay()
            player = newPlayer
            seekToCurrentSentenceStart()
            startProgressTimer()
        } catch {
            errorMessage = "音频无法打开：\(error.localizedDescription)"
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player, currentSentence != nil else { return }
        transitionTask?.cancel()
        if player.currentTime >= (currentSentence?.endTime ?? 0) - 0.03 {
            seekToCurrentSentenceStart()
        }
        player.enableRate = true
        player.rate = speed
        player.play()
        isPlaying = true
    }

    func pause() {
        transitionTask?.cancel()
        player?.pause()
        isPlaying = false
    }

    func stop() {
        transitionTask?.cancel()
        progressTimer?.invalidate()
        progressTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
    }

    func previousSentence() {
        moveToSentence(max(0, currentSentenceIndex - 1))
    }

    func nextSentence() {
        guard let count = document?.manifest.sentences.count, count > 0 else { return }
        if currentSentenceIndex + 1 < count {
            moveToSentence(currentSentenceIndex + 1)
        } else if loopEnabled {
            moveToSentence(0)
        }
    }

    func seekBy(seconds: TimeInterval) {
        guard let player, let document else { return }
        let wasPlaying = isPlaying
        transitionTask?.cancel()
        let target = min(max(player.currentTime + seconds, 0), player.duration)
        player.currentTime = target
        if let index = document.manifest.sentences.lastIndex(where: {
            $0.startTime <= target + 0.001
        }) {
            currentSentenceIndex = min(index, document.manifest.sentences.count - 1)
        }
        currentRepeatIndex = 1
        handlingSentenceEnd = false
        if wasPlaying {
            player.rate = speed
            player.play()
        }
    }

    func setSpeed(_ newSpeed: Float) {
        speed = newSpeed
        player?.enableRate = true
        player?.rate = newSpeed
    }

    func setRepeatMode(_ mode: SentenceRepeatMode) {
        repeatMode = mode
        currentRepeatIndex = min(currentRepeatIndex, targetRepeatCount)
    }

    private func moveToSentence(_ index: Int) {
        guard let sentences = document?.manifest.sentences,
              sentences.indices.contains(index) else { return }
        let shouldResume = isPlaying
        transitionTask?.cancel()
        player?.pause()
        currentSentenceIndex = index
        currentRepeatIndex = 1
        handlingSentenceEnd = false
        seekToCurrentSentenceStart()
        if shouldResume { play() }
    }

    private func seekToCurrentSentenceStart() {
        guard let sentence = currentSentence else { return }
        player?.currentTime = sentence.startTime
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSentenceBoundary()
            }
        }
    }

    private func checkSentenceBoundary() {
        guard isPlaying, !handlingSentenceEnd,
              let sentence = currentSentence,
              let player,
              player.currentTime >= sentence.endTime - 0.025 else { return }
        handlingSentenceEnd = true
        player.pause()
        isPlaying = false

        let pauseMilliseconds = min(
            max(document?.manifest.pauseMilliseconds ?? 0, 0),
            5_000
        )
        transitionTask = Task { [weak self] in
            if pauseMilliseconds > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(pauseMilliseconds) * 1_000_000
                )
            }
            guard !Task.isCancelled else { return }
            self?.advanceAfterSentenceIteration()
        }
    }

    private func advanceAfterSentenceIteration() {
        guard let document else { return }
        if currentRepeatIndex < targetRepeatCount {
            currentRepeatIndex += 1
        } else if currentSentenceIndex + 1 < document.manifest.sentences.count {
            currentSentenceIndex += 1
            currentRepeatIndex = 1
        } else if loopEnabled {
            currentSentenceIndex = 0
            currentRepeatIndex = 1
        } else {
            handlingSentenceEnd = false
            seekToCurrentSentenceStart()
            return
        }
        handlingSentenceEnd = false
        seekToCurrentSentenceStart()
        play()
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            self?.checkSentenceBoundary()
        }
    }

    deinit {
        progressTimer?.invalidate()
        transitionTask?.cancel()
    }
}
