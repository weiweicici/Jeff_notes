import Foundation

struct WatchSentence: Codable, Identifiable, Equatable {
    let text: String
    let offsetMicroseconds: Int64
    let durationMicroseconds: Int64
    let repeatCount: Int

    var id: String { "\(offsetMicroseconds)-\(durationMicroseconds)" }
    var startTime: TimeInterval { TimeInterval(offsetMicroseconds) / 1_000_000 }
    var duration: TimeInterval { TimeInterval(durationMicroseconds) / 1_000_000 }
    var endTime: TimeInterval { startTime + duration }

    enum CodingKeys: String, CodingKey {
        case text
        case offsetMicroseconds = "offset_us"
        case durationMicroseconds = "duration_us"
        case repeatCount = "repeat_count"
    }
}

struct WatchDocumentManifest: Codable, Identifiable {
    let schemaVersion: Int
    let documentId: String
    let title: String
    let createdAt: String
    let audioFile: String
    let markdownFile: String
    let loopEnabled: Bool
    let pauseMilliseconds: Int
    let sentences: [WatchSentence]

    var id: String { documentId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case documentId = "document_id"
        case title
        case createdAt = "created_at"
        case audioFile = "audio_file"
        case markdownFile = "markdown_file"
        case loopEnabled = "loop_enabled"
        case pauseMilliseconds = "pause_ms"
        case sentences
    }
}

struct WatchDocument: Identifiable {
    let manifest: WatchDocumentManifest
    let directoryURL: URL

    var id: String { manifest.id }
    var audioURL: URL { directoryURL.appendingPathComponent(manifest.audioFile) }
    var markdownURL: URL { directoryURL.appendingPathComponent(manifest.markdownFile) }
}

struct WatchRecordingSnapshot {
    var state = "idle"
    var isStandby = false
    var isRecording = false
    var isPaused = false
    var isProcessing = false
    var startedAtMilliseconds: Int64 = 0
    var progress = 0.0
    var message = ""
    var error = ""
    var latestEnglish = ""
    var latestChinese = ""

    var startedAt: Date? {
        guard startedAtMilliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(startedAtMilliseconds) / 1000)
    }

    init() {}

    init(dictionary: [String: Any]) {
        state = dictionary["state"] as? String ?? "idle"
        isStandby = dictionary["is_standby"] as? Bool ?? false
        isRecording = dictionary["is_recording"] as? Bool ?? false
        isPaused = dictionary["is_paused"] as? Bool ?? false
        isProcessing = dictionary["is_processing"] as? Bool ?? false
        startedAtMilliseconds = (dictionary["started_at_ms"] as? NSNumber)?.int64Value ?? 0
        progress = (dictionary["progress"] as? NSNumber)?.doubleValue ?? 0
        message = dictionary["message"] as? String ?? ""
        error = dictionary["error"] as? String ?? ""
        latestEnglish = dictionary["latest_english"] as? String ?? ""
        latestChinese = dictionary["latest_chinese"] as? String ?? ""
    }
}

struct WatchGrammarThemeOption: Identifiable, Equatable {
    let label: String
    let value: String

    var id: String { value }

    init?(dictionary: [String: Any]) {
        guard let label = dictionary["label"] as? String,
              let value = dictionary["value"] as? String else { return nil }
        self.label = label
        self.value = value
    }
}

struct WatchGrammarUnitOption: Identifiable, Equatable {
    let id: String
    let title: String

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let title = dictionary["title"] as? String else { return nil }
        self.id = id
        self.title = title
    }
}

struct WatchGrammarPartOption: Identifiable, Equatable {
    let id: String
    let title: String
    let units: [WatchGrammarUnitOption]

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let title = dictionary["title"] as? String else { return nil }
        self.id = id
        self.title = title
        let rawUnits = dictionary["units"] as? [[String: Any]] ?? []
        units = rawUnits.compactMap(WatchGrammarUnitOption.init(dictionary:))
    }
}

struct WatchGrammarWritingConfig {
    var selectedPartIds: Set<String> = []
    var selectedUnitIds: Set<String> = []
    var contentType = ""
    var requireAllSelectedGrammar = false
    var themes: [WatchGrammarThemeOption] = []
    var parts: [WatchGrammarPartOption] = []
    var updatedAtMilliseconds: Int64 = 0

    init() {}

    init(dictionary: [String: Any]) {
        selectedPartIds = Set(dictionary["selected_part_ids"] as? [String] ?? [])
        selectedUnitIds = Set(dictionary["selected_unit_ids"] as? [String] ?? [])
        contentType = dictionary["content_type"] as? String ?? ""
        requireAllSelectedGrammar =
            dictionary["require_all_selected_grammar"] as? Bool ?? false
        themes = (dictionary["themes"] as? [[String: Any]] ?? [])
            .compactMap(WatchGrammarThemeOption.init(dictionary:))
        parts = (dictionary["parts"] as? [[String: Any]] ?? [])
            .compactMap(WatchGrammarPartOption.init(dictionary:))
        updatedAtMilliseconds =
            (dictionary["updated_at_ms"] as? NSNumber)?.int64Value ?? 0
    }
}

struct WatchGrammarWritingState {
    var requestId = ""
    var state = "idle"
    var message = ""
    var updatedAtMilliseconds: Int64 = 0

    init() {}

    init(dictionary: [String: Any]) {
        requestId = dictionary["request_id"] as? String ?? ""
        state = dictionary["state"] as? String ?? "idle"
        message = dictionary["message"] as? String ?? ""
        updatedAtMilliseconds =
            (dictionary["updated_at_ms"] as? NSNumber)?.int64Value ?? 0
    }
}

enum SentenceRepeatMode: Int, CaseIterable, Identifiable {
    case documentDefault = 0
    case once = 1
    case twice = 2
    case threeTimes = 3

    var id: Int { rawValue }
    var label: String { rawValue == 0 ? "自动" : "\(rawValue)×" }
}
