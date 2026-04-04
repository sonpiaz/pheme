import SwiftUI
import SwiftData

/// Main layout: meeting list | summary (center) + transcript (collapsible bottom)
struct MainContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var selectedMeeting: Meeting?

    private var session: TranscriptionSession { appState.session }

    var body: some View {
        NavigationSplitView {
            MeetingListView(selectedMeeting: $selectedMeeting)
                .frame(minWidth: 200)
        } detail: {
            VStack(spacing: 0) {
                if let meeting = activeMeeting {
                    MeetingDetailView(meeting: meeting, session: session)
                } else {
                    ContentUnavailableView(
                        "No Meeting Selected",
                        systemImage: "waveform",
                        description: Text("Select a meeting or start recording")
                    )
                }

                Divider()

                RecordingControlView(
                    session: session,
                    onStart: {
                        session.startRecording(modelContext: modelContext)
                        // Auto-select the new meeting after a brief delay for SwiftData to flush
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if let meeting = currentRecordingMeeting {
                                selectedMeeting = meeting
                            }
                        }
                    },
                    onStop: {
                        session.stopRecording()
                        appState.refreshRecentMeetings(from: modelContext)
                    }
                )
                .animation(.easeInOut(duration: 0.2), value: session.isRecording)
                .animation(.easeInOut(duration: 0.2), value: session.isPaused)
            }
        }
        .navigationTitle("Pheme")
        .onAppear {
            appState.purgeEmptyMeetings(from: modelContext)
            appState.refreshRecentMeetings(from: modelContext)
        }
        .onChange(of: session.isRecording) { _, isRecording in
            if isRecording, let meeting = currentRecordingMeeting {
                selectedMeeting = meeting
            }
        }
    }

    private var activeMeeting: Meeting? {
        if session.isRecording {
            return currentRecordingMeeting
        }
        return selectedMeeting
    }

    private var currentRecordingMeeting: Meeting? {
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.isRecording },
            sortBy: [SortDescriptor(\Meeting.date, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Meeting Detail (Summary center + Transcript collapsible)

struct MeetingDetailView: View {
    @Bindable var meeting: Meeting
    @ObservedObject var session: TranscriptionSession
    @State private var showTranscript = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // CENTER: Summary (main content)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    TextField("Meeting Title", text: $meeting.title)
                        .font(.title.bold())
                        .textFieldStyle(.plain)
                        .onChange(of: meeting.title) {
                            try? modelContext.save()
                        }

                    // Meta info
                    HStack(spacing: 12) {
                        Label(meeting.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        if meeting.duration > 0 {
                            Label(formatDuration(meeting.duration), systemImage: "clock")
                        }
                        if meeting.isRecording {
                            if session.isPaused {
                                Label("Paused", systemImage: "pause.circle")
                                    .foregroundStyle(.orange)
                            } else {
                                Label("Recording", systemImage: "waveform")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider()

                    // Summary content
                    if session.isGeneratingSummary {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generating summary...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                    } else if let summary = meeting.summary, !summary.isEmpty {
                        Text(LocalizedStringKey(summary))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if meeting.isRecording || !session.currentMeText.isEmpty {
                        // Live transcript during recording
                        LiveStreamView(
                            currentMeText: session.currentMeText,
                            currentThemText: session.currentThemText
                        )
                    } else if !meeting.segments.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No summary yet")
                                .foregroundStyle(.secondary)
                            regenerateButton
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("Start recording to capture meeting notes")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(24)
            }

            // Action bar
            if meeting.summary != nil || !meeting.segments.isEmpty {
                Divider()
                actionBar
            }

            // BOTTOM: Collapsible transcript
            if showTranscript {
                Divider()
                transcriptPanel
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            // Transcript toggle
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showTranscript.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: showTranscript ? "text.alignleft" : "text.alignleft")
                    Text(showTranscript ? "Hide Transcript" : "Show Transcript")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button(action: copySummary) {
                Label("Copy Summary", systemImage: "doc.on.clipboard")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(meeting.summary == nil)

            Button(action: copyTranscript) {
                Label("Copy Transcript", systemImage: "doc.plaintext")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(meeting.segments.isEmpty)

            regenerateButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Transcript Panel

    private var transcriptPanel: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(mergedTranscriptTurns, id: \.id) { turn in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(turn.label)
                            .font(.caption.bold())
                            .foregroundStyle(SpeakerPill.palette[turn.speaker.colorIndex % SpeakerPill.palette.count].fg)
                        Text(turn.text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .foregroundStyle(.primary.opacity(0.9))
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 250)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Merge consecutive segments from the same speaker into single turns
    private var mergedTranscriptTurns: [TranscriptTurn] {
        let sorted = meeting.segments.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return [] }

        var turns: [TranscriptTurn] = []
        var currentSpeaker = sorted[0].speaker
        var currentTexts: [String] = []

        for segment in sorted {
            if segment.speaker == currentSpeaker {
                currentTexts.append(segment.text)
            } else {
                turns.append(TranscriptTurn(speaker: currentSpeaker, texts: currentTexts))
                currentSpeaker = segment.speaker
                currentTexts = [segment.text]
            }
        }
        if !currentTexts.isEmpty {
            turns.append(TranscriptTurn(speaker: currentSpeaker, texts: currentTexts))
        }
        return turns
    }

    // MARK: - Helpers

    @State private var isRegenerating = false

    private var regenerateButton: some View {
        Button(action: regenerate) {
            Label("Regenerate", systemImage: "arrow.clockwise")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .disabled(meeting.segments.isEmpty || isRegenerating)
    }

    private func copySummary() {
        guard let summary = meeting.summary else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    private func copyTranscript() {
        let transcript = meeting.formattedTranscript
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    private func regenerate() {
        guard let apiKey = UserDefaults.standard.string(forKey: "openaiApiKey"),
              !apiKey.isEmpty else { return }
        let transcript = meeting.formattedTranscript
        guard !transcript.isEmpty else { return }

        isRegenerating = true
        Task {
            let generator = SummaryGenerator(apiKey: apiKey)
            do {
                async let title = generator.generateTitle(transcript: transcript)
                async let summary = generator.generateSummary(transcript: transcript)
                let (t, s) = try await (title, summary)
                await MainActor.run {
                    meeting.title = t
                    meeting.summary = s
                    try? modelContext.save()
                    isRegenerating = false
                }
            } catch {
                await MainActor.run { isRegenerating = false }
            }
        }
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        let minutes = Int(d) / 60
        if minutes < 1 { return "<1m" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    private func formatTimestamp(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Live Stream (during recording)

private struct LiveStreamView: View {
    let currentMeText: String
    let currentThemText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !currentMeText.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    SpeakerPill(speaker: .me)
                    Text(currentMeText)
                        .foregroundStyle(.primary.opacity(0.7))
                        .italic()
                }
            }
            if !currentThemText.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    SpeakerPill(speaker: .them)
                    Text(currentThemText)
                        .foregroundStyle(.primary.opacity(0.7))
                        .italic()
                }
            }
        }
    }
}

// MARK: - Transcript Turn (merged consecutive segments)

private struct TranscriptTurn: Identifiable {
    let id = UUID()
    let speaker: Speaker
    let texts: [String]

    var label: String {
        speaker.speakerLabel
    }

    var text: String {
        texts.joined(separator: " ")
    }
}
