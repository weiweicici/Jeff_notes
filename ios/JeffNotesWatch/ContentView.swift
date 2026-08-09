import SwiftUI

struct ContentView: View {
    @StateObject private var store = WatchDocumentStore()
    @StateObject private var recording = WatchRecordingStore()
    @StateObject private var grammar = WatchGrammarWritingStore()
    @State private var autoOpenedDocument: WatchDocument?

    var body: some View {
        NavigationStack {
            WatchHomeView(store: store, recording: recording, grammar: grammar)
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
    @ObservedObject var grammar: WatchGrammarWritingStore

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
                WatchGrammarWritingView(
                    documents: store.documents,
                    grammar: grammar
                )
            } label: {
                homeRow(
                    icon: "square.and.pencil",
                    title: "语法写作",
                    subtitle: grammar.config.parts.isEmpty
                        ? "听写题目并由手机生成"
                        : "手机预设已同步",
                    color: .green
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
                        WatchPlayerView(document: document, documents: documents)
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

struct WatchGrammarWritingView: View {
    let documents: [WatchDocument]
    @ObservedObject var grammar: WatchGrammarWritingStore
    @State private var topic = ""
    @State private var selectionMode = "phone"
    @State private var selectedPartIds: Set<String> = []
    @State private var selectedUnitIds: Set<String> = []
    @State private var selectedContentType = ""
    @State private var requireAllSelectedGrammar = false
    @State private var isSending = false
    @State private var requestPending = false
    @State private var currentRequestId = ""
    @State private var statusMessage: String?
    @State private var didSendSuccessfully = false
    @State private var initializedFromPhone = false

    var body: some View {
        List {
            Section("老师题目") {
                Text("输入或听写老师给出的题目")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("例如：shopping garage sale", text: $topic, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("写作设置") {
                NavigationLink {
                    WatchThemeSelectionView(
                        options: grammar.config.themes,
                        selection: $selectedContentType
                    )
                } label: {
                    LabeledContent("文章类型", value: selectedThemeLabel)
                }

                Picker("语法来源", selection: $selectionMode) {
                    Text("手机当前选择").tag("phone")
                    Text("AI自动4–6种").tag("automatic")
                    Text("手表重新选择").tag("custom")
                }

                if selectionMode == "custom" {
                    NavigationLink {
                        WatchGrammarSelectionView(
                            parts: grammar.config.parts,
                            selectedPartIds: $selectedPartIds,
                            selectedUnitIds: $selectedUnitIds
                        )
                    } label: {
                        LabeledContent("选择语法", value: grammarSelectionSummary)
                    }

                    if grammarSelectionCount > 6 {
                        Toggle("全部必须使用", isOn: $requireAllSelectedGrammar)
                    }
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isSending || requestPending {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isSending || requestPending ? "正在处理" : "生成文章")
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || requestPending)

                Text(requestSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let visibleStatusMessage {
                    Text(visibleStatusMessage)
                        .font(.caption2)
                        .foregroundStyle(statusIsError ? .red : .green)
                }
            }

            NavigationLink {
                WatchLibraryView(documents: documents)
            } label: {
                Label("全部文档", systemImage: "books.vertical")
            }
        }
        .navigationTitle("语法写作")
        .onAppear {
            applyPhoneConfig(force: !initializedFromPhone)
            Task {
                try? await WatchConnectivityReceiver.shared
                    .requestGrammarWritingConfig()
            }
        }
        .onChange(of: grammar.config.updatedAtMilliseconds) { _, _ in
            applyPhoneConfig(force: selectionMode == "phone")
        }
        .onChange(of: grammar.generationState.updatedAtMilliseconds) { _, _ in
            guard grammar.generationState.requestId == currentRequestId else { return }
            if ["completed", "error"].contains(grammar.generationState.state) {
                requestPending = false
            }
        }
        .onChange(of: selectionMode) { _, mode in
            if mode == "phone" {
                applyPhoneConfig(force: true)
            } else if mode == "automatic" {
                requireAllSelectedGrammar = false
            }
        }
    }

    private var selectedThemeLabel: String {
        if selectedContentType.isEmpty { return "不限定" }
        return grammar.config.themes
            .first(where: { $0.value == selectedContentType })?.label ?? "已选择"
    }

    private var grammarSelectionCount: Int {
        selectedUnitIds.isEmpty ? selectedPartIds.count : selectedUnitIds.count
    }

    private var grammarSelectionSummary: String {
        if grammarSelectionCount == 0 { return "未选择" }
        return "\(grammarSelectionCount)项"
    }

    private var requestSummary: String {
        let type = selectedThemeLabel
        let grammarLabel: String
        switch selectionMode {
        case "automatic": grammarLabel = "AI自动4–6种"
        case "custom": grammarLabel = grammarSelectionSummary
        default:
            let count = grammar.config.selectedUnitIds.isEmpty
                ? grammar.config.selectedPartIds.count
                : grammar.config.selectedUnitIds.count
            grammarLabel = count == 0 ? "手机未选择·AI自动" : "手机已选\(count)项"
        }
        let normalizedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return [normalizedTopic.isEmpty ? "AI自选题目" : normalizedTopic, type, grammarLabel]
            .joined(separator: " · ")
    }

    private var visibleStatusMessage: String? {
        if grammar.generationState.requestId == currentRequestId,
           !grammar.generationState.message.isEmpty {
            return grammar.generationState.message
        }
        return statusMessage
    }

    private var statusIsError: Bool {
        if grammar.generationState.requestId == currentRequestId {
            return grammar.generationState.state == "error"
        }
        return !didSendSuccessfully
    }

    private func applyPhoneConfig(force: Bool) {
        guard force else { return }
        selectedPartIds = grammar.config.selectedPartIds
        selectedUnitIds = grammar.config.selectedUnitIds
        selectedContentType = grammar.config.contentType
        requireAllSelectedGrammar = grammar.config.requireAllSelectedGrammar
        initializedFromPhone = true
    }

    private func submit() {
        isSending = true
        requestPending = true
        statusMessage = nil
        didSendSuccessfully = false
        currentRequestId = UUID().uuidString
        Task {
            do {
                let delivery = try await WatchConnectivityReceiver.shared
                    .sendGrammarWritingRequest(
                    topic: topic,
                    requestId: currentRequestId,
                    selectionMode: selectionMode,
                    selectedPartIds: selectedPartIds,
                    selectedUnitIds: selectedUnitIds,
                    contentType: selectedContentType,
                    requireAllSelectedGrammar: requireAllSelectedGrammar
                )
                didSendSuccessfully = true
                statusMessage = delivery == .immediate
                    ? "手机已收到，正在准备生成"
                    : "已排队，等待手机连接"
            } catch {
                didSendSuccessfully = false
                requestPending = false
                statusMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}

struct WatchThemeSelectionView: View {
    let options: [WatchGrammarThemeOption]
    @Binding var selection: String

    var body: some View {
        List {
            selectionRow(label: "不限定", value: "")
            ForEach(options) { option in
                selectionRow(label: option.label, value: option.value)
            }
        }
        .navigationTitle("文章类型")
    }

    private func selectionRow(label: String, value: String) -> some View {
        Button {
            selection = value
        } label: {
            HStack {
                Text(label)
                Spacer()
                if selection == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

struct WatchGrammarSelectionView: View {
    let parts: [WatchGrammarPartOption]
    @Binding var selectedPartIds: Set<String>
    @Binding var selectedUnitIds: Set<String>

    var body: some View {
        Group {
            if parts.isEmpty {
                ContentUnavailableView(
                    "等待手机同步",
                    systemImage: "iphone.and.arrow.forward",
                    description: Text("请在手机打开一次语法综合练习")
                )
            } else {
                List(parts) { part in
                    NavigationLink {
                        WatchGrammarPartSelectionView(
                            part: part,
                            selectedPartIds: $selectedPartIds,
                            selectedUnitIds: $selectedUnitIds
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.title)
                                .font(.caption)
                                .lineLimit(2)
                            Text(partSummary(part))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("选择语法")
    }

    private func partSummary(_ part: WatchGrammarPartOption) -> String {
        if selectedPartIds.contains(part.id) { return "整章已选" }
        let count = part.units.filter { selectedUnitIds.contains($0.id) }.count
        return count == 0 ? "未选择" : "具体语法 \(count)项"
    }
}

struct WatchGrammarPartSelectionView: View {
    let part: WatchGrammarPartOption
    @Binding var selectedPartIds: Set<String>
    @Binding var selectedUnitIds: Set<String>

    var body: some View {
        List {
            Toggle("选择整个章节", isOn: partBinding)
            Section("具体语法") {
                ForEach(part.units) { unit in
                    Toggle(unit.title, isOn: unitBinding(unit.id))
                        .font(.caption)
                }
            }
        }
        .navigationTitle("语法项目")
    }

    private var partBinding: Binding<Bool> {
        Binding(
            get: { selectedPartIds.contains(part.id) },
            set: { enabled in
                if enabled {
                    selectedPartIds.insert(part.id)
                } else {
                    selectedPartIds.remove(part.id)
                }
            }
        )
    }

    private func unitBinding(_ unitId: String) -> Binding<Bool> {
        Binding(
            get: { selectedUnitIds.contains(unitId) },
            set: { enabled in
                if enabled {
                    selectedUnitIds.insert(unitId)
                } else {
                    selectedUnitIds.remove(unitId)
                }
            }
        )
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
        (try? AttributedString(markdown: content)) ?? AttributedString(content)
    }
}
