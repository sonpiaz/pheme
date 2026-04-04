import SwiftData
import Foundation

@Model
final class TranscriptSegment {
    var id: UUID = UUID()
    var text: String = ""
    var speakerRaw: String = Speaker.me.rawValue
    var timestamp: TimeInterval = 0
    var isFinal: Bool = false

    var meeting: Meeting?

    var speaker: Speaker {
        get { Speaker(rawValue: speakerRaw) ?? .me }
        set { speakerRaw = newValue.rawValue }
    }

    init(text: String = "", speaker: Speaker = .me, timestamp: TimeInterval = 0) {
        self.id = UUID()
        self.text = text
        self.speakerRaw = speaker.rawValue
        self.timestamp = timestamp
    }
}

/// Represents a speaker in the meeting.
/// `.me` and `.them` are the built-in dual-stream speakers.
/// `.other(label)` supports multi-speaker diarization for future use.
enum Speaker: Codable, Hashable, Equatable {
    case me
    case them
    case other(String)  // e.g. "Speaker C", "Speaker D"

    var rawValue: String {
        switch self {
        case .me: return "Me"
        case .them: return "Them"
        case .other(let label): return label
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "Me": self = .me
        case "Them": self = .them
        case let label where !label.isEmpty: self = .other(label)
        default: return nil
        }
    }

    /// Display label for summary transcript (Speaker A, Speaker B, Speaker C...)
    var speakerLabel: String {
        switch self {
        case .me: return "Speaker A"
        case .them: return "Speaker B"
        case .other(let label): return label
        }
    }

    /// Accent color index for UI (cycles through palette for N speakers)
    var colorIndex: Int {
        switch self {
        case .me: return 0
        case .them: return 1
        case .other(let label):
            // Stable hash-based index for consistent colors
            return abs(label.hashValue) % 8 + 2
        }
    }
}
