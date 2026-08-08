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

enum SentenceRepeatMode: Int, CaseIterable, Identifiable {
    case documentDefault = 0
    case once = 1
    case twice = 2
    case threeTimes = 3

    var id: Int { rawValue }
    var label: String { rawValue == 0 ? "自动" : "\(rawValue)×" }
}
