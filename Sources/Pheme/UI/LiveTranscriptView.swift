import SwiftUI
import SwiftData

/// Real-time scrolling transcript view with speaker labels and timestamps.
/// Shows interleaved Me/Them segments with live streaming text for both.
struct LiveTranscriptView: View {
    let meeting: Meeting?
    let currentMeText: String
    let currentThemText: String
    let isRecording: Bool

    @State private var autoScroll = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let meeting {
                        ForEach(meeting.segments.sorted(by: { $0.timestamp < $1.timestamp })) { segment in
                            SegmentRow(segment: segment)
                        }
                    }

                    // Live streaming text — Me (mic)
                    if !currentMeText.isEmpty {
                        LiveSegmentRow(speaker: .me, text: currentMeText)
                            .id("liveMe")
                    }

                    // Live streaming text — Them (system audio)
                    if !currentThemText.isEmpty {
                        LiveSegmentRow(speaker: .them, text: currentThemText)
                            .id("liveThem")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
            }
            .onChange(of: currentMeText) { scrollToBottom(proxy) }
            .onChange(of: currentThemText) { scrollToBottom(proxy) }
            .onChange(of: meeting?.segments.count ?? 0) { scrollToBottom(proxy) }
        }
        .overlay {
            if meeting == nil && !isRecording {
                ContentUnavailableView(
                    "No Meeting Selected",
                    systemImage: "waveform",
                    description: Text("Select a meeting or start recording")
                )
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if autoScroll {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - Segment Row (finalized)

private struct SegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SpeakerPill(speaker: segment.speaker)

            VStack(alignment: .leading, spacing: 2) {
                Text(segment.text)
                    .textSelection(.enabled)

                Text(formatTimestamp(segment.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .background(segment.speaker == .me ? Color.blue.opacity(0.03) : Color.clear)
    }

    private func formatTimestamp(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - Live Segment Row (streaming, not yet committed)

private struct LiveSegmentRow: View {
    let speaker: Speaker
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SpeakerPill(speaker: speaker)

            Text(text)
                .foregroundStyle(.primary.opacity(0.6))
                .italic()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Speaker Pill

struct SpeakerPill: View {
    let speaker: Speaker

    var body: some View {
        Text(speaker.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(speaker == .me ? Color.blue.opacity(0.15) : Color.orange.opacity(0.12))
            .foregroundStyle(speaker == .me ? .blue : .orange)
            .clipShape(Capsule())
    }
}
