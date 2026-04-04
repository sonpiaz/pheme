import SwiftUI
import SwiftData

/// Right column: editable title, summary/transcript tabs, copy/regenerate buttons.
struct MeetingSummaryView: View {
    @Bindable var meeting: Meeting
    @State private var isRegenerating = false
    @State private var regenerateError: String?
    @State private var selectedTab: Tab = .summary
    @Environment(\.modelContext) private var modelContext

    enum Tab: String, CaseIterable {
        case summary = "Summary"
        case transcript = "Transcript"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Editable title
            TextField("Meeting Title", text: $meeting.title)
                .font(.title3.bold())
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .onChange(of: meeting.title) {
                    try? modelContext.save()
                }

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Content
            switch selectedTab {
            case .summary:
                summaryContent
            case .transcript:
                transcriptContent
            }

            if let error = regenerateError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button(action: copySummary) {
                    Label("Copy Summary", systemImage: "doc.on.clipboard")
                        .font(.caption)
                }
                .disabled(meeting.summary == nil)

                Button(action: copyTranscript) {
                    Label("Copy Transcript", systemImage: "doc.plaintext")
                        .font(.caption)
                }
                .disabled(meeting.segments.isEmpty)

                Spacer()

                Button(action: regenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .disabled(meeting.segments.isEmpty || isRegenerating)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Summary Tab

    @ViewBuilder
    private var summaryContent: some View {
        if isRegenerating {
            Spacer()
            ProgressView("Generating summary...")
                .frame(maxWidth: .infinity)
            Spacer()
        } else if let summary = meeting.summary, !summary.isEmpty {
            ScrollView {
                Text(LocalizedStringKey(summary))
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if meeting.isRecording {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Summary will be generated\nwhen recording ends")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        } else {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No summary yet")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    // MARK: - Raw Transcript Tab

    @ViewBuilder
    private var transcriptContent: some View {
        if meeting.segments.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No transcript yet")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(meeting.segments.sorted(by: { $0.timestamp < $1.timestamp })) { segment in
                        HStack(alignment: .top, spacing: 6) {
                            Text(formatTimestamp(segment.timestamp))
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .frame(width: 36, alignment: .trailing)

                            SpeakerPill(speaker: segment.speaker)

                            Text(segment.text)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Actions

    private func copySummary() {
        guard let summary = meeting.summary else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    private func copyTranscript() {
        let transcript = meeting.rawTranscript
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    private func regenerate() {
        guard let apiKey = UserDefaults.standard.string(forKey: "openaiApiKey"),
              !apiKey.isEmpty else {
            regenerateError = "Set API key in Settings"
            return
        }

        let transcript = meeting.formattedTranscript
        guard !transcript.isEmpty else { return }

        isRegenerating = true
        regenerateError = nil

        Task {
            let generator = SummaryGenerator(apiKey: apiKey)
            do {
                async let title = generator.generateTitle(transcript: transcript)
                async let summary = generator.generateSummary(transcript: transcript)

                let (newTitle, newSummary) = try await (title, summary)

                await MainActor.run {
                    meeting.title = newTitle
                    meeting.summary = newSummary
                    try? modelContext.save()
                    isRegenerating = false
                }
            } catch {
                await MainActor.run {
                    regenerateError = error.localizedDescription
                    isRegenerating = false
                }
            }
        }
    }

    private func formatTimestamp(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
