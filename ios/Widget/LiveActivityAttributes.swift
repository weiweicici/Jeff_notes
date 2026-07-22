import ActivityKit

struct JeffNotesAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var activeSentence: String
        var nextSentence: String
        var currentIndex: Int
        var totalCount: Int
        var docTitle: String
        var isPlaying: Bool
    }

    var id: String
}
