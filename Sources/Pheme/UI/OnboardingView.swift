import SwiftUI
import AVFoundation

/// First-launch permission wizard: Mic → System Audio → API Key.
struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var micGranted = false
    @State private var apiKey = ""
    @State private var checkTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 24)

            Spacer()

            // Step content
            Group {
                switch step {
                case 0: micStep
                case 1: systemAudioStep
                case 2: apiKeyStep
                default: completionStep
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()
        }
        .frame(width: 400, height: 420)
        .onAppear { startPolling() }
        .onDisappear { checkTimer?.invalidate() }
    }

    // MARK: - Step 1: Microphone

    private var micStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Microphone Access")
                .font(.title2.bold())

            Text("Pheme needs your microphone to capture\nyour voice in meetings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if micGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Access") {
                    Task {
                        let granted = await AVCaptureDevice.requestAccess(for: .audio)
                        await MainActor.run {
                            micGranted = granted
                            if granted { advanceStep() }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Step 2: System Audio

    private var systemAudioStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("System Audio Access")
                .font(.title2.bold())

            Text("Pheme captures system audio to hear other\nmeeting participants (Zoom, Meet, Teams).\n\nA system dialog will appear when you first record.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("This permission is granted automatically\nwhen you start your first recording.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Continue") {
                advanceStep()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Step 3: API Key

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("OpenAI API Key")
                .font(.title2.bold())

            Text("Pheme uses OpenAI for real-time transcription\nand meeting summaries.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            SecureField("sk-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            Button("Get Started") {
                let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                UserDefaults.standard.set(trimmed, forKey: "openaiApiKey")
                advanceStep()
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Done

    private var completionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title2.bold())

            Text("Click the record button to start\nyour first meeting.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Open Pheme") {
                UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                onComplete()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func advanceStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            step += 1
        }
    }

    private func startPolling() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if micGranted && step == 0 {
            advanceStep()
        }

        checkTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                if granted && !micGranted {
                    micGranted = true
                    if step == 0 { advanceStep() }
                }
            }
        }
    }
}
