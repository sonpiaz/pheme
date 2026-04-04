import Foundation
import SwiftData

/// Orchestrates dual-stream transcription: mic (Me) + system audio (Them).
/// Each stream gets its own WebSocket → RealtimeTranscriber.
/// Segments are merged by timestamp into a single Meeting.
@MainActor
final class TranscriptionSession: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var currentMeText = ""
    @Published var currentThemText = ""
    @Published var error: String?
    @Published var systemAudioActive = false
    @Published var isGeneratingSummary = false

    private let mixer = DualStreamMixer.shared
    private var meTranscriber: RealtimeTranscriber?
    private var themTranscriber: RealtimeTranscriber?

    private var meeting: Meeting?
    private var modelContext: ModelContext?
    private var recordingStartDate: Date?

    var micLevel: Float { mixer.micLevel }
    var systemLevel: Float { mixer.systemLevel }

    func startRecording(modelContext: ModelContext) {
        guard !isRecording else { return }

        self.modelContext = modelContext
        self.error = nil

        guard let apiKey = UserDefaults.standard.string(forKey: "openaiApiKey"),
              !apiKey.isEmpty else {
            self.error = "Please set your OpenAI API key in Settings"
            return
        }

        // Create meeting
        let meeting = Meeting(title: "New Meeting", date: Date())
        meeting.isRecording = true
        modelContext.insert(meeting)
        try? modelContext.save()
        self.meeting = meeting
        self.recordingStartDate = Date()

        // Set up "Me" transcriber (mic)
        let meTranscriber = RealtimeTranscriber(apiKey: apiKey)
        self.meTranscriber = meTranscriber

        meTranscriber.onTranscriptDelta = { [weak self] delta in
            self?.currentMeText += delta
        }
        meTranscriber.onTranscriptCompleted = { [weak self] transcript in
            self?.handleCompleted(transcript, speaker: .me)
            self?.currentMeText = ""
        }
        meTranscriber.onError = { [weak self] error in
            NSLog("[Pheme] Me transcriber error: %@", error.localizedDescription)
            self?.error = error.localizedDescription
        }

        // Wire mic chunker → me transcriber
        mixer.micChunker.reset()
        mixer.micChunker.onChunkReady = { [weak meTranscriber] base64 in
            meTranscriber?.sendAudio(base64Chunk: base64)
        }

        // Set up "Them" transcriber (system audio)
        let themTranscriber = RealtimeTranscriber(apiKey: apiKey)
        self.themTranscriber = themTranscriber

        themTranscriber.onTranscriptDelta = { [weak self] delta in
            self?.currentThemText += delta
        }
        themTranscriber.onTranscriptCompleted = { [weak self] transcript in
            self?.handleCompleted(transcript, speaker: .them)
            self?.currentThemText = ""
        }
        themTranscriber.onError = { error in
            NSLog("[Pheme] Them transcriber error: %@", error.localizedDescription)
        }

        // Wire system chunker → them transcriber
        mixer.systemChunker.reset()
        mixer.systemChunker.onChunkReady = { [weak themTranscriber] base64 in
            themTranscriber?.sendAudio(base64Chunk: base64)
        }

        // Connect both WebSockets
        meTranscriber.connect()
        themTranscriber.connect()

        // Start audio capture (mic required, system audio optional)
        do {
            try mixer.start()
            systemAudioActive = mixer.systemAudioAvailable
        } catch {
            self.error = error.localizedDescription
            meTranscriber.disconnect()
            themTranscriber.disconnect()
            return
        }

        // If no system audio, disconnect the them transcriber to save cost
        if !mixer.systemAudioAvailable {
            themTranscriber.disconnect()
        }

        isRecording = true

        if UserDefaults.standard.bool(forKey: "soundEnabled") {
            SoundFeedback.shared.playStartTone()
        }

        NSLog("[Pheme] Recording session started (system audio: %@)",
              systemAudioActive ? "active" : "unavailable")
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        mixer.pause()
        isPaused = true

        if UserDefaults.standard.bool(forKey: "soundEnabled") {
            SoundFeedback.shared.playStopTone()
        }
        NSLog("[Pheme] Recording paused")
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        mixer.resume()
        isPaused = false

        if UserDefaults.standard.bool(forKey: "soundEnabled") {
            SoundFeedback.shared.playStartTone()
        }
        NSLog("[Pheme] Recording resumed")
    }

    func stopRecording() {
        guard isRecording else { return }

        // Stop audio capture
        mixer.stop()

        // Flush remaining audio then disconnect pipeline
        mixer.micChunker.flush()
        mixer.systemChunker.flush()

        // Commit buffers to trigger final transcription
        meTranscriber?.commitBuffer()
        themTranscriber?.commitBuffer()

        isRecording = false
        isPaused = false
        systemAudioActive = false

        if UserDefaults.standard.bool(forKey: "soundEnabled") {
            SoundFeedback.shared.playStopTone()
        }

        NSLog("[Pheme] Recording stopped, waiting for final transcripts...")

        // Wait 5 seconds for completed events, then finalize
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.finalizeRecording()
        }
    }

    private func finalizeRecording() {
        // Save any remaining delta text that never got a completed event
        if !currentMeText.isEmpty {
            saveSegment(text: currentMeText, speaker: .me)
            currentMeText = ""
        }
        if !currentThemText.isEmpty {
            saveSegment(text: currentThemText, speaker: .them)
            currentThemText = ""
        }

        // Disconnect WebSockets
        meTranscriber?.disconnect()
        meTranscriber = nil
        themTranscriber?.disconnect()
        themTranscriber = nil

        // Disconnect chunker callbacks
        mixer.micChunker.onChunkReady = nil
        mixer.systemChunker.onChunkReady = nil

        // Finalize meeting
        if let meeting, let startDate = recordingStartDate {
            meeting.isRecording = false
            meeting.duration = Date().timeIntervalSince(startDate)
            try? modelContext?.save()
        }

        NSLog("[Pheme] Recording finalized")

        // Auto-generate summary
        generateSummary()
    }

    private func saveSegment(text: String, speaker: Speaker) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let meeting, let modelContext else { return }

        let timestamp: TimeInterval
        if let startDate = recordingStartDate {
            timestamp = Date().timeIntervalSince(startDate)
        } else {
            timestamp = 0
        }

        let segment = TranscriptSegment(text: trimmed, speaker: speaker, timestamp: timestamp)
        segment.isFinal = true
        segment.meeting = meeting
        meeting.segments.append(segment)
        try? modelContext.save()

        NSLog("[Pheme] Saved fallback segment [%@]: %@", speaker.rawValue, trimmed.prefix(60).description)
    }

    // MARK: - Summary Generation

    private func generateSummary() {
        guard let meeting, !meeting.segments.isEmpty,
              let apiKey = UserDefaults.standard.string(forKey: "openaiApiKey"),
              !apiKey.isEmpty else { return }

        let transcript = meeting.formattedTranscript
        guard !transcript.isEmpty else { return }

        isGeneratingSummary = true

        Task {
            let generator = SummaryGenerator(apiKey: apiKey)
            do {
                async let titleResult = generator.generateTitle(transcript: transcript)
                async let summaryResult = generator.generateSummary(transcript: transcript)

                let (title, summary) = try await (titleResult, summaryResult)

                meeting.title = title
                meeting.summary = summary
                try? modelContext?.save()

                isGeneratingSummary = false
                NSLog("[Pheme] Summary generated: %@", title)
            } catch {
                NSLog("[Pheme] Summary generation failed: %@", error.localizedDescription)
                self.error = "Summary failed: \(error.localizedDescription)"
                isGeneratingSummary = false
            }
        }
    }

    // MARK: - Transcript Handling

    private func handleCompleted(_ transcript: String, speaker: Speaker) {
        guard let meeting, let modelContext,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let timestamp: TimeInterval
        if let startDate = recordingStartDate {
            timestamp = Date().timeIntervalSince(startDate)
        } else {
            timestamp = 0
        }

        let segment = TranscriptSegment(
            text: transcript,
            speaker: speaker,
            timestamp: timestamp
        )
        segment.isFinal = true
        segment.meeting = meeting
        meeting.segments.append(segment)

        try? modelContext.save()

        NSLog("[Pheme] [%@] %@", speaker.rawValue, transcript.prefix(60).description)
    }
}
