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

enum Speaker: String, Codable {
    case me = "Me"
    case them = "Them"
}
