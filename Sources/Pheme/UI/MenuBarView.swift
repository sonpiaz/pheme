import SwiftUI

/// Menu bar dropdown with recording controls, timer, and recent meetings.
struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Recording state
            if appState.session.isRecording {
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording — \(formatElapsed(elapsed))")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                Divider()

                Button("Stop Recording") {
                    appState.session.stopRecording()
                    stopTimer()
                    refreshRecents()
                }
                .keyboardShortcut("s")
            } else {
                Button("Start Recording") {
                    appState.session.startRecording(modelContext: modelContext)
                    startTimer()
                }
                .keyboardShortcut("r")
            }

            Divider()

            // Recent meetings
            if !appState.recentMeetings.isEmpty {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                ForEach(appState.recentMeetings) { meeting in
                    Button(action: { openMainWindow() }) {
                        HStack {
                            Text(meeting.title)
                                .lineLimit(1)
                            Spacer()
                            Text(meeting.relativeDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()
            }

            Button("Open Pheme") {
                openMainWindow()
            }
            .keyboardShortcut("o")

            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit Pheme") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
        .onAppear { refreshRecents() }
    }

    // MARK: - Helpers

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            if window.title == "Pheme" {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    }

    private func refreshRecents() {
        appState.refreshRecentMeetings(from: modelContext)
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func startTimer() {
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in elapsed += 1 }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsed = 0
    }
}
