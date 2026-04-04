import SwiftUI

/// Granola-style bottom bar: minimal, elegant recording controls.
struct RecordingControlView: View {
    @ObservedObject var session: TranscriptionSession
    let onStart: () -> Void
    let onStop: () -> Void

    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var wavePhase: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            if session.isRecording {
                recordingControls
            } else if session.isGeneratingSummary {
                analyzingView
            } else {
                idleControls
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Idle State

    private var idleControls: some View {
        HStack(spacing: 12) {
            Button(action: {
                onStart()
                startTimer()
            }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: 8, height: 8)
                    Text("Start recording")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            if let error = session.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Recording State

    private var recordingControls: some View {
        HStack(spacing: 16) {
            // Waveform indicator + timer
            HStack(spacing: 10) {
                WaveformIndicator(
                    level: session.isPaused ? 0 : session.micLevel,
                    isPaused: session.isPaused
                )

                Text(formatElapsed(elapsed))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // System audio indicator
            if session.systemAudioActive && !session.isPaused {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 10))
                    Text("System")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary.opacity(0.6))
            }

            // Pause / Resume
            Button(action: {
                if session.isPaused {
                    session.resumeRecording()
                } else {
                    session.pauseRecording()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11))
                    Text(session.isPaused ? "Resume" : "Pause")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Stop
            Button(action: {
                onStop()
                stopTimer()
            }) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 9, height: 9)
                    Text("Stop")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Analyzing State

    private var analyzingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)

            Text("Analyzing transcript...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Timer

    private func formatElapsed(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func startTimer() {
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if !session.isPaused {
                elapsed += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsed = 0
    }
}

// MARK: - Waveform Indicator

/// Subtle animated waveform bars that react to mic level.
struct WaveformIndicator: View {
    let level: Float
    var isPaused: Bool = false

    private let barCount = 4
    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 16
    private let minHeight: CGFloat = 3

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(isPaused ? 0.2 : 0.5))
                    .frame(width: barWidth, height: barHeight(for: index))
                    .animation(
                        isPaused ? .easeOut(duration: 0.3) : .easeInOut(duration: 0.15),
                        value: level
                    )
            }
        }
        .frame(width: CGFloat(barCount) * (barWidth + 2), height: maxHeight)
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard !isPaused else { return minHeight }
        let scale = [0.6, 1.0, 0.8, 0.5][index]
        let height = minHeight + CGFloat(level) * (maxHeight - minHeight) * CGFloat(scale)
        return max(minHeight, min(maxHeight, height))
    }
}
