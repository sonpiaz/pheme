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

    /// Conversation-style transcript with merged consecutive speaker turns.
    /// Format: "Speaker A: text\nSpeaker B: text\n..."
    var formattedTranscript: String {
        let sorted = segments.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return "" }

        var lines: [String] = []
        var currentSpeaker = sorted[0].speaker
        var currentTexts: [String] = []

        for segment in sorted {
            if segment.speaker == currentSpeaker {
                currentTexts.append(segment.text)
            } else {
                lines.append("\(speakerLabel(currentSpeaker)): \(currentTexts.joined(separator: " "))")
                currentSpeaker = segment.speaker
                currentTexts = [segment.text]
            }
        }
        // Flush last speaker
        if !currentTexts.isEmpty {
            lines.append("\(speakerLabel(currentSpeaker)): \(currentTexts.joined(separator: " "))")
        }

        return lines.joined(separator: "\n")
    }

    private func speakerLabel(_ speaker: Speaker) -> String {
        speaker.speakerLabel
    }
}
