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
