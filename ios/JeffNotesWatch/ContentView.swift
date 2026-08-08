import SwiftUI

struct ContentView: View {
    @StateObject private var store = WatchDocumentStore()

    var body: some View {
        NavigationStack {
            Group {
                if let latest = store.latest {
                    WatchPlayerView(document: latest)
                        .id(latest.id)
                } else {
                    ContentUnavailableView(
                        "等待手机同步",
                        systemImage: "iphone.and.arrow.forward",
                        description: Text("在 Jeff Notes 中生成并播放一次 TTS")
                    )
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .jeffNotesWatchLibraryChanged
                )
            ) { _ in
                store.reload()
            }
            .toolbar {
                if !store.documents.isEmpty {
                    NavigationLink {
                        WatchLibraryView(documents: store.documents)
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
        }
    }
}

struct WatchLibraryView: View {
    let documents: [WatchDocument]

    var body: some View {
        List(documents) { document in
            NavigationLink {
                WatchPlayerView(document: document)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.manifest.title)
                        .font(.headline)
                    Text("\(document.manifest.sentences.count)句")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("本地文档")
    }
}

struct WatchPlayerView: View {
    let document: WatchDocument
    @StateObject private var playback = WatchPlaybackController()

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(document.manifest.title)
                    .font(.caption2)
                    .lineLimit(1)
                Spacer()
                Text(playback.sentencePositionLabel)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(playback.currentSentence?.text ?? "准备播放")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 70)

            if let error = playback.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 5) {
                controlButton("backward.end.fill") { playback.previousSentence() }
                controlButton("gobackward.5") { playback.seekBy(seconds: -5) }
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                controlButton("goforward.5") { playback.seekBy(seconds: 5) }
                controlButton("forward.end.fill") { playback.nextSentence() }
            }

            HStack(spacing: 8) {
                Button {
                    let modes = SentenceRepeatMode.allCases
                    let current = modes.firstIndex(of: playback.repeatMode) ?? 0
                    playback.setRepeatMode(modes[(current + 1) % modes.count])
                } label: {
                    Label(playback.repeatMode.label, systemImage: "repeat.1")
                        .font(.caption2)
                }

                Button {
                    playback.loopEnabled.toggle()
                } label: {
                    Image(systemName: playback.loopEnabled ? "repeat.circle.fill" : "repeat.circle")
                }
                .accessibilityLabel("循环播放")

                Button {
                    let speeds: [Float] = [0.75, 1.0, 1.25, 1.5]
                    let current = speeds.firstIndex(of: playback.speed) ?? 0
                    playback.setSpeed(speeds[(current + 1) % speeds.count])
                } label: {
                    Text(String(format: "%.2g×", playback.speed))
                        .font(.caption2)
                }

                NavigationLink {
                    WatchMarkdownView(document: document)
                } label: {
                    Image(systemName: "doc.text")
                }
                .accessibilityLabel("查看文档")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .onAppear { playback.load(document) }
        .onDisappear { playback.pause() }
    }

    private func controlButton(
        _ systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 23, height: 28)
        }
        .buttonStyle(.plain)
    }
}

struct WatchMarkdownView: View {
    let document: WatchDocument
    @State private var content = ""

    var body: some View {
        ScrollView {
            Text(markdownText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("文档")
        .task {
            content = (try? String(contentsOf: document.markdownURL)) ?? "无法读取文档"
        }
    }

    private var markdownText: AttributedString {
        (try? AttributedString(markdown: content)) ?? AttributedString(content)
    }
}
