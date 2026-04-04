import SwiftUI
import SwiftData

/// Left sidebar: meeting list grouped by date with search and delete.
struct MeetingListView: View {
    @Query(sort: \Meeting.date, order: .reverse)
    private var meetings: [Meeting]

    @Binding var selectedMeeting: Meeting?
    @State private var searchText = ""
    @Environment(\.modelContext) private var modelContext

    private var filteredMeetings: [Meeting] {
        guard !searchText.isEmpty else { return meetings }
        let query = searchText.lowercased()
        return meetings.filter { meeting in
            meeting.title.lowercased().contains(query) ||
            meeting.segments.contains { $0.text.lowercased().contains(query) }
        }
    }

    var body: some View {
        List(selection: $selectedMeeting) {
            if filteredMeetings.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Meetings",
                        systemImage: "rectangle.stack",
                        description: Text("Start recording to capture your first meeting")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                ForEach(groupedMeetings, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.meetings) { meeting in
                            MeetingRow(meeting: meeting)
                                .tag(meeting)
                        }
                        .onDelete { offsets in
                            deleteMeetings(from: group.meetings, at: offsets)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search meetings")
    }

    // MARK: - Delete

    private func deleteMeetings(from meetings: [Meeting], at offsets: IndexSet) {
        for index in offsets {
            let meeting = meetings[index]
            if selectedMeeting?.id == meeting.id {
                selectedMeeting = nil
            }
            modelContext.delete(meeting)
        }
        try? modelContext.save()
    }

    // MARK: - Date Grouping

    private struct MeetingGroup {
        let title: String
        let meetings: [Meeting]
    }

    private var groupedMeetings: [MeetingGroup] {
        let calendar = Calendar.current
        let now = Date()

        var today: [Meeting] = []
        var yesterday: [Meeting] = []
        var thisWeek: [Meeting] = []
        var earlier: [Meeting] = []

        for meeting in filteredMeetings {
            if calendar.isDateInToday(meeting.date) {
                today.append(meeting)
            } else if calendar.isDateInYesterday(meeting.date) {
                yesterday.append(meeting)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      meeting.date > weekAgo {
                thisWeek.append(meeting)
            } else {
                earlier.append(meeting)
            }
        }

        var groups: [MeetingGroup] = []
        if !today.isEmpty { groups.append(MeetingGroup(title: "Today", meetings: today)) }
        if !yesterday.isEmpty { groups.append(MeetingGroup(title: "Yesterday", meetings: yesterday)) }
        if !thisWeek.isEmpty { groups.append(MeetingGroup(title: "This Week", meetings: thisWeek)) }
        if !earlier.isEmpty { groups.append(MeetingGroup(title: "Earlier", meetings: earlier)) }

        return groups
    }
}

// MARK: - Meeting Row

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        HStack {
            if meeting.isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(meeting.date, style: .time)
                    if meeting.duration > 0 {
                        Text("·")
                        Text(formatDuration(meeting.duration))
                    }
                    if meeting.summary != nil {
                        Text("·")
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 9))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        let minutes = Int(d) / 60
        if minutes < 1 { return "<1m" }
        return "\(minutes)m"
    }
}
