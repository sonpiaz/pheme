import SwiftData
import Foundation

@Model
final class Meeting {
    var id: UUID = UUID()
    var title: String = ""
    var summary: String?
    var date: Date = Date()
    var duration: TimeInterval = 0
    var isRecording: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.meeting)
    var segments: [TranscriptSegment] = []

    init(title: String = "", date: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.date = date
    }

    var rawTranscript: String {
        segments
            .sorted { $0.timestamp < $1.timestamp }
            .map { "[\($0.speaker.rawValue)] \($0.text)" }
            .joined(separator: "\n")
    }

    var formattedTranscript: String {
        segments
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                let time = formatTimestamp($0.timestamp)
                return "[\(time)] [\($0.speaker.rawValue)] \($0.text)"
            }
            .joined(separator: "\n")
    }

    private func formatTimestamp(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
