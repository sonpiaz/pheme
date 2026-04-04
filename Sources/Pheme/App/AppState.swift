import SwiftUI
import SwiftData
import Combine

/// Shared app state bridging main window and menu bar.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let session = TranscriptionSession()

    /// Recent meetings for menu bar quick access (last 3)
    @Published var recentMeetings: [RecentMeetingInfo] = []

    private init() {}

    /// Purge stale empty meetings left over from crashed/test sessions.
    /// Removes meetings with no segments, no summary, and default title.
    func purgeEmptyMeetings(from context: ModelContext) {
        // Note: SwiftData #Predicate doesn't support .isEmpty on relationships,
        // so we fetch all non-recording meetings and filter in memory.
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate<Meeting> { meeting in
                !meeting.isRecording &&
                (meeting.title == "New Meeting" || meeting.title == "")
            }
        )

        guard let candidates = try? context.fetch(descriptor), !candidates.isEmpty else { return }

        // Filter to only those with no segments (can't check in predicate)
        let stale = candidates.filter { $0.segments.isEmpty && $0.summary == nil }
        guard !stale.isEmpty else { return }

        NSLog("[Pheme] Purging %d empty meeting(s)", stale.count)
        for meeting in stale {
            context.delete(meeting)
        }
        try? context.save()
    }

    func refreshRecentMeetings(from context: ModelContext) {
        var descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { !$0.isRecording },
            sortBy: [SortDescriptor(\Meeting.date, order: .reverse)]
        )
        descriptor.fetchLimit = 3

        guard let meetings = try? context.fetch(descriptor) else { return }
        recentMeetings = meetings.map { meeting in
            RecentMeetingInfo(
                id: meeting.id,
                title: meeting.title.isEmpty ? "Untitled Meeting" : meeting.title,
                date: meeting.date,
                duration: meeting.duration
            )
        }
    }
}

/// Lightweight struct for menu bar display (avoids passing @Model across scenes)
struct RecentMeetingInfo: Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let duration: TimeInterval

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var durationText: String {
        let minutes = Int(duration) / 60
        if minutes < 1 { return "<1m" }
        return "\(minutes)m"
    }
}
