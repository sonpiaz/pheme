import AVFoundation
import Foundation

/// Streams mic audio as 16kHz mono Float32 chunks via callback.
/// Adapted from Yap's AudioRecorder — no RAM buffer, continuous streaming.
final class MicRecorder {
    static let shared = MicRecorder()

    private var engine: AVAudioEngine?
    private let lock = NSLock()

    var isRunning: Bool { engine != nil }

    /// Called on audio thread with Float32 samples at 16kHz mono
    var onAudioChunk: (([Float]) -> Void)?

    /// Audio level 0..1 for UI meters
    @Published var audioLevel: Float = 0

    private init() {}

    func start() throws {
        let eng = AVAudioEngine()
        self.engine = eng

        let inputNode = eng.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            self.engine = nil
            throw MicRecorderError.badFormat
        }
        NSLog("[Pheme] Mic format: %.0fHz, %dch", hwFormat.sampleRate, hwFormat.channelCount)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        ) else {
            self.engine = nil
            throw MicRecorderError.badFormat
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            self.engine = nil
            throw MicRecorderError.converterFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] pcm, _ in
            self?.processTapBuffer(pcm, converter: converter, targetFormat: targetFormat)
        }

        eng.prepare()
        try eng.start()
        NSLog("[Pheme] Mic recording started")
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        DispatchQueue.main.async { [weak self] in self?.audioLevel = 0 }
        NSLog("[Pheme] Mic recording stopped")
    }

    private func processTapBuffer(_ pcm: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let ratio = 24000.0 / pcm.format.sampleRate
        let frameCount = AVAudioFrameCount(Double(pcm.frameLength) * ratio)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

        var error: NSError?
        converter.convert(to: converted, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return pcm
        }
        guard error == nil, let data = converted.floatChannelData?[0] else { return }

        let count = Int(converted.frameLength)
        let samples = Array(UnsafeBufferPointer(start: data, count: count))

        // Forward chunk to consumer
        onAudioChunk?(samples)

        // Update level meter
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / max(Float(count), 1))
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = min(1.0, rms * 10)
        }
    }
}

enum MicRecorderError: LocalizedError {
    case badFormat
    case converterFailed

    var errorDescription: String? {
        switch self {
        case .badFormat: return "Invalid audio format"
        case .converterFailed: return "Could not create audio converter"
        }
    }
}
