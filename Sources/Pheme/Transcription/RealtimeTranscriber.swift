import Foundation

/// WebSocket client for OpenAI Realtime Transcription API.
/// Handles connect, session config, audio streaming, transcript deltas, reconnection.
final class RealtimeTranscriber {
    enum State {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    private(set) var state: State = .disconnected

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var autoCommitTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let apiKey: String
    private let language: String

    // Local audio buffer for resilience during reconnection (~5s at 100ms chunks = 50 chunks)
    private var audioBuffer: [String] = []
    private let maxBufferSize = 50
    private let bufferLock = NSLock()

    /// Called with partial transcript text (delta)
    var onTranscriptDelta: ((String) -> Void)?

    /// Called with final completed transcript for a turn
    var onTranscriptCompleted: ((String) -> Void)?

    /// Called when connection state changes
    var onStateChanged: ((State) -> Void)?

    /// Called on error
    var onError: ((Error) -> Void)?

    init(apiKey: String, language: String = "vi") {
        self.apiKey = apiKey
        self.language = language
    }

    // MARK: - Connect

    func connect() {
        guard state == .disconnected || state == .reconnecting else { return }
        state = .connecting
        onStateChanged?(state)

        let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        receiveMessage()
        sendSessionUpdate()

        state = .connected
        onStateChanged?(state)
        let wasReconnecting = reconnectAttempts > 0
        reconnectAttempts = 0
        startPingTimer()
        startAutoCommitTimer()

        NSLog("[Pheme] WebSocket connected")

        // Replay buffered audio from during disconnection
        if wasReconnecting {
            replayBuffer()
        }
    }

    func disconnect() {
        stopPingTimer()
        stopAutoCommitTimer()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        state = .disconnected
        onStateChanged?(state)
        NSLog("[Pheme] WebSocket disconnected")
    }

    // MARK: - Send Audio

    func sendAudio(base64Chunk: String) {
        // Buffer audio during reconnection
        if state != .connected {
            bufferLock.lock()
            audioBuffer.append(base64Chunk)
            if audioBuffer.count > maxBufferSize {
                audioBuffer.removeFirst(audioBuffer.count - maxBufferSize)
            }
            bufferLock.unlock()
            return
        }

        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Chunk,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(json)) { [weak self] error in
            if let error {
                NSLog("[Pheme] Send audio error: %@", error.localizedDescription)
                self?.handleDisconnect()
            }
        }
    }

    /// Replay buffered audio chunks after reconnection
    private func replayBuffer() {
        bufferLock.lock()
        let chunks = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        guard !chunks.isEmpty else { return }
        NSLog("[Pheme] Replaying %d buffered audio chunks", chunks.count)

        for chunk in chunks {
            sendAudio(base64Chunk: chunk)
        }
    }

    /// Commit the audio buffer (call on stop to finalize last segment)
    func commitBuffer() {
        guard state == .connected else { return }

        let message = ["type": "input_audio_buffer.commit"]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(json)) { error in
            if let error {
                // "buffer too small" is expected when committing with < 100ms audio — safe to ignore
                Self.debugLog("Commit buffer: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Session Configuration

    private func sendSessionUpdate() {
        let prompt = CustomDictionary.promptFragment

        // Transcription-only intent uses "transcription_session.update"
        let sessionConfig: [String: Any] = [
            "type": "transcription_session.update",
            "session": [
                "input_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "gpt-4o-transcribe",
                    "language": language,
                    "prompt": prompt,
                ] as [String: Any],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.3,
                    "prefix_padding_ms": 200,
                    "silence_duration_ms": 300,
                ] as [String: Any],
            ] as [String: Any],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: sessionConfig),
              let json = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(json)) { error in
            if let error {
                NSLog("[Pheme] Session update error: %@", error.localizedDescription)
            } else {
                NSLog("[Pheme] Session configured: model=gpt-4o-transcribe, lang=%@", self.language)
            }
        }
    }

    // MARK: - Receive

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()

            case .failure(let error):
                NSLog("[Pheme] WebSocket receive error: %@", error.localizedDescription)
                self.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        Self.debugLog("EVENT: \(type)")

        switch type {
        // Transcription-only intent events
        case "conversation.item.input_audio_transcription.delta":
            if let delta = json["delta"] as? String {
                Self.debugLog("DELTA: \(delta)")
                DispatchQueue.main.async { self.onTranscriptDelta?(delta) }
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                Self.debugLog("COMPLETED: \(transcript)")
                DispatchQueue.main.async { self.onTranscriptCompleted?(transcript) }
            }

        case "conversation.item.input_audio_transcription.failed":
            if let errorObj = json["error"] as? [String: Any] {
                Self.debugLog("TRANSCRIPTION FAILED: \(errorObj)")
            }

        case "error":
            if let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                Self.debugLog("ERROR: \(message)")
                // "buffer too small" is benign — don't surface to UI
                guard !message.contains("buffer too small") else { break }
                DispatchQueue.main.async {
                    self.onError?(TranscriberError.apiError(message))
                }
            }

        case "transcription_session.created", "transcription_session.updated",
             "session.created", "session.updated":
            Self.debugLog("SESSION: \(type)")

        case "input_audio_buffer.speech_started":
            Self.debugLog("SPEECH STARTED")

        case "input_audio_buffer.speech_stopped":
            Self.debugLog("SPEECH STOPPED")

        case "input_audio_buffer.committed":
            Self.debugLog("BUFFER COMMITTED")

        default:
            Self.debugLog("UNHANDLED: \(type)")
        }
    }

    // MARK: - Debug Logging

    private static let logFile: URL = {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Pheme")
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path.appendingPathComponent("transcriber.log")
    }()

    static func debugLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        stopPingTimer()
        webSocket?.cancel(with: .abnormalClosure, reason: nil)
        webSocket = nil

        guard reconnectAttempts < maxReconnectAttempts else {
            state = .disconnected
            onStateChanged?(state)
            onError?(TranscriberError.maxReconnectAttemptsReached)
            return
        }

        state = .reconnecting
        onStateChanged?(state)
        reconnectAttempts += 1

        let delay = min(pow(2.0, Double(reconnectAttempts)), 16.0)
        NSLog("[Pheme] Reconnecting in %.0fs (attempt %d)", delay, reconnectAttempts)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    // MARK: - Auto-Commit (for real-time partial transcripts)

    private func startAutoCommitTimer() {
        stopAutoCommitTimer()
        autoCommitTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.commitBuffer()
        }
    }

    private func stopAutoCommitTimer() {
        autoCommitTimer?.invalidate()
        autoCommitTimer = nil
    }

    // MARK: - Keepalive

    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.webSocket?.sendPing { error in
                if let error {
                    NSLog("[Pheme] Ping failed: %@", error.localizedDescription)
                    self?.handleDisconnect()
                }
            }
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
}

enum TranscriberError: LocalizedError {
    case apiError(String)
    case maxReconnectAttemptsReached

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "API error: \(msg)"
        case .maxReconnectAttemptsReached: return "Max reconnection attempts reached"
        }
    }
}
