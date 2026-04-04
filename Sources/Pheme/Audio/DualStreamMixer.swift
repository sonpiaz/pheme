import Foundation

/// Manages both mic and system audio recorders.
/// Routes audio chunks to separate chunkers with speaker labels (Me / Them).
final class DualStreamMixer {
    static let shared = DualStreamMixer()

    private let micRecorder = MicRecorder.shared
    private let systemRecorder = SystemAudioRecorder.shared

    let micChunker = AudioChunker()
    let systemChunker = AudioChunker()

    private(set) var isRunning = false
    private(set) var isPaused = false
    var systemAudioAvailable = true

    /// Audio levels for UI
    var micLevel: Float { micRecorder.audioLevel }
    var systemLevel: Float { systemRecorder.audioLevel }

    private init() {}

    /// Start both audio streams.
    /// If system audio fails (no permission), continues with mic only.
    func start() throws {
        guard !isRunning else { return }

        // Wire mic → micChunker
        micRecorder.onAudioChunk = { [weak self] samples in
            self?.micChunker.feed(samples)
        }

        // Wire system → systemChunker
        systemRecorder.onAudioChunk = { [weak self] samples in
            self?.systemChunker.feed(samples)
        }

        // Start mic (required)
        try micRecorder.start()

        // Start system audio (optional — may fail if no permission)
        do {
            try systemRecorder.start()
            systemAudioAvailable = true
            NSLog("[Pheme] Dual stream: mic + system audio active")
        } catch {
            systemAudioAvailable = false
            NSLog("[Pheme] System audio unavailable: %@. Running mic-only mode.", error.localizedDescription)
        }

        isRunning = true
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true

        // Mute the audio callbacks — engines keep running to avoid reinit cost
        micRecorder.onAudioChunk = nil
        if systemAudioAvailable {
            systemRecorder.onAudioChunk = nil
        }
        NSLog("[Pheme] Dual stream paused")
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false

        // Re-wire audio callbacks
        micRecorder.onAudioChunk = { [weak self] (samples: [Float]) in
            self?.micChunker.feed(samples)
        }
        if systemAudioAvailable {
            systemRecorder.onAudioChunk = { [weak self] (samples: [Float]) in
                self?.systemChunker.feed(samples)
            }
        }
        NSLog("[Pheme] Dual stream resumed")
    }

    func stop() {
        guard isRunning else { return }

        micRecorder.stop()
        micRecorder.onAudioChunk = nil
        micChunker.flush()

        if systemAudioAvailable {
            systemRecorder.stop()
            systemRecorder.onAudioChunk = nil
            systemChunker.flush()
        }

        isRunning = false
        isPaused = false
        NSLog("[Pheme] Dual stream stopped")
    }
}
