import Foundation

/// Converts Float32 audio samples → PCM16LE → base64 chunks.
/// Accumulates samples and emits 100ms chunks (2,400 samples at 24kHz).
final class AudioChunker {
    private let chunkSize: Int  // samples per chunk
    private var buffer: [Float] = []
    private let lock = NSLock()

    /// Called with base64-encoded PCM16LE chunk ready for WebSocket
    var onChunkReady: ((String) -> Void)?

    init(sampleRate: Int = 24000, chunkDurationMs: Int = 100) {
        self.chunkSize = sampleRate * chunkDurationMs / 1000  // 2400 at 24kHz/100ms
    }

    /// Feed Float32 samples from MicRecorder
    func feed(_ samples: [Float]) {
        lock.lock()
        buffer.append(contentsOf: samples)

        while buffer.count >= chunkSize {
            let chunk = Array(buffer.prefix(chunkSize))
            buffer.removeFirst(chunkSize)
            lock.unlock()

            let base64 = encodeToBase64PCM16LE(chunk)
            onChunkReady?(base64)

            lock.lock()
        }
        lock.unlock()
    }

    /// Flush remaining samples (on stop)
    func flush() {
        lock.lock()
        let remaining = buffer
        buffer.removeAll()
        lock.unlock()

        guard !remaining.isEmpty else { return }
        let base64 = encodeToBase64PCM16LE(remaining)
        onChunkReady?(base64)
    }

    func reset() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }

    /// Convert Float32 samples to PCM16LE Data, then base64 encode
    private func encodeToBase64PCM16LE(_ samples: [Float]) -> String {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: int16.littleEndian) { data.append(contentsOf: $0) }
        }
        return data.base64EncodedString()
    }
}
