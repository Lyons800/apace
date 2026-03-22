import Foundation

struct TranscriptionResult {
    let text: String
    let duration: TimeInterval
    let language: String?
    let segments: [Segment]
    let timestamp: Date

    struct Segment {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    init(text: String, duration: TimeInterval = 0, language: String? = nil, segments: [Segment] = [], timestamp: Date = .now) {
        self.text = text
        self.duration = duration
        self.language = language
        self.segments = segments
        self.timestamp = timestamp
    }
}
