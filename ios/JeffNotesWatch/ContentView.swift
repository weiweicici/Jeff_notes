import SwiftUI

struct ContentView: View {
    @StateObject private var store = WatchDocumentStore()
    @StateObject private var recording = WatchRecordingStore()
    @State private var autoOpenedDocument: WatchDocument?

    var body: some View {
        NavigationStack {
            WatchHomeView(store: store, recording: recording)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .jeffNotesWatchLibraryChanged
                )
            ) { _ in
                let previousId = store.latest?.id
                store.reload()
                if let latest = store.latest, latest.id != previousId {
                    autoOpenedDocument = latest
                }
            }
        }
        .sheet(item: $autoOpenedDocument) { document in
            NavigationStack {
                WatchPlayerView(document: document, documents: store.documents)
            }
        }
    }
}

struct WatchHomeView: View {
    @ObservedObject var store: WatchDocumentStore
    @ObservedObject var recording: WatchRecordingStore

    var body: some View {
        List {
            NavigationLink {
                WatchLibraryView(documents: store.documents)
            } label: {
                homeRow(
                    icon: "books.vertical.fill",
                    title: "全部文档",
                    subtitle: store.latest?.manifest.title ?? "暂无同步文档",
                    color: .blue
                )
            }
            NavigationLink {
                WatchListeningView(
                    recording: recording,
                    documents: store.documents
                )
            } label: {
                homeRow(
                    icon: "mic.fill",
                    title: "听力录音",
                    subtitle: listeningSubtitle,
                    color: recording.snapshot.isRecording ? .red : .orange
                )
            }
        }
        .navigationTitle("Jeff Notes")
    }

    private var listeningSubtitle: String {
        switch recording.snapshot.state {
        case "standby": return "手机已待命"
        case "recording": return "正在录音"
        case "paused": return "录音已暂停"
        case "processing": return "正在生成速记"
        case "error": return "有可恢复的录音"
        default: return "手机录音与实时字幕"
        }
    }

    private func homeRow(
        icon: String,
        title: String,
        subtitle: String,
        color: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct WatchLibraryView: View {
    let documents: [WatchDocument]

    var body: some View {
        Group {
            if documents.isEmpty {
                ContentUnavailableView(
                    "暂无文档",
                    systemImage: "doc",
                    description: Text("手机生成后会自动同步")
                )
            } else {
                List(documents) { document in
                    NavigationLink {
                        if document.manifest.sentences.isEmpty {
                            WatchMarkdownView(document: document)
                        } else {
                            WatchPlayerView(
                                document: document,
                                documents: documents
                            )
                        }
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
            }
        }
        .navigationTitle("本地文档")
    }
}

struct WatchPlayerView: View {
    let document: WatchDocument
    let documents: [WatchDocument]
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
                Label("控制手机 TTS", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Button {
                    playback.toggleLoop()
                } label: {
                    Image(systemName: playback.loopEnabled ? "repeat.circle.fill" : "repeat.circle")
                }
                .accessibilityLabel("循环播放")
                Button {
                    playback.cycleSpeed()
                } label: {
                    Text(String(format: "%.2g×", playback.speed))
                        .font(.caption2)
                }
                .accessibilityLabel("播放速度")
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


struct WatchListeningView: View {
    @ObservedObject var recording: WatchRecordingStore
    let documents: [WatchDocument]
    @State private var isSending = false
    @State private var localError: String?
    @State private var localStatus: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                stateHeader

                if recording.snapshot.isRecording {
                    liveTranscript
                    Button {
                        send("stopListeningRecording")
                    } label: {
                        Label("停止并生成", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isSending)
                } else if recording.snapshot.isStandby {
                    Button {
                        send("startListeningRecording")
                    } label: {
                        Label("开始录音", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isSending)
                } else if recording.snapshot.isProcessing {
                    ProgressView(value: recording.snapshot.progress)
                    Text(recording.snapshot.message.isEmpty
                         ? "手机正在生成速记 MD"
                         : recording.snapshot.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button {
                        send("startListeningRecording")
                    } label: {
                        Label("开始下一段录音", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isSending)
                } else {
                    Text(recording.snapshot.error.isEmpty
                        ? "请先在手机听力页面开启“录音待命”"
                         : recording.snapshot.error)
                        .font(.caption)
                        .foregroundColor(recording.snapshot.error.isEmpty ? .secondary : .red)
                }

                if let localError {
                    Text(localError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if let localStatus {
                    Text(localStatus)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                NavigationLink {
                    WatchLibraryView(documents: documents)
                } label: {
                    Label("全部文档", systemImage: "books.vertical")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("听力录音")
    }

    @ViewBuilder
    private var stateHeader: some View {
        HStack {
            Circle()
                .fill(stateColor)
                .frame(width: 9, height: 9)
            Text(stateLabel)
                .font(.headline)
            Spacer()
            if recording.snapshot.isRecording,
               let startedAt = recording.snapshot.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedLabel(from: startedAt, to: context.date))
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(recording.snapshot.latestEnglish.isEmpty
                 ? "等待第一段字幕…"
                 : recording.snapshot.latestEnglish)
                .font(.caption)
                .fontWeight(.semibold)
            if !recording.snapshot.latestChinese.isEmpty {
                Text(recording.snapshot.latestChinese)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stateLabel: String {
        switch recording.snapshot.state {
        case "standby": return "手机已待命"
        case "recording": return "正在录音"
        case "paused": return "已暂停"
        case "processing": return "正在生成速记"
        case "error": return "等待恢复"
        default: return "尚未待命"
        }
    }

    private var stateColor: Color {
        switch recording.snapshot.state {
        case "standby": return .green
        case "recording": return .red
        case "processing": return .blue
        case "error": return .orange
        default: return .gray
        }
    }

    private func elapsedLabel(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func send(_ command: String) {
        guard !isSending else { return }
        isSending = true
        localError = nil
        localStatus = "正在发送到手机…"
        Task {
            do {
                let delivery = try await WatchConnectivityReceiver.shared
                    .sendRecordingCommand(command)
                localStatus = delivery == .immediate
                    ? "手机已收到命令"
                    : "命令已排队，等待手机连接"
            } catch {
                localError = error.localizedDescription
                localStatus = nil
            }
            isSending = false
        }
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
        return (try? AttributedString(markdown: content)) ?? AttributedString(content)
    }



}
