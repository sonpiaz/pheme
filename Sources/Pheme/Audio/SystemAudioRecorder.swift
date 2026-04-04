import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

/// Captures system audio (all processes except Pheme) using Core Audio Taps (macOS 14.2+).
/// Outputs 16kHz mono Float32 chunks via callback, matching MicRecorder's interface.
final class SystemAudioRecorder {
    static let shared = SystemAudioRecorder()

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var converter: AVAudioConverter?

    private(set) var isRunning = false

    /// Called with Float32 samples at 16kHz mono (same as MicRecorder)
    var onAudioChunk: (([Float]) -> Void)?

    /// Audio level 0..1 for UI meters
    @Published var audioLevel: Float = 0

    private let processingQueue = DispatchQueue(label: "com.sonpiaz.pheme.systemaudio", qos: .userInteractive)

    private init() {}

    // MARK: - Start / Stop

    func start() throws {
        guard !isRunning else { return }

        // 1. Create process tap excluding our own process
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownProcessObject = try translatePID(ownPID)

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcessObject])
        tapDescription.uuid = UUID()
        tapDescription.name = "Pheme System Audio Tap"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard tapStatus == noErr else {
            throw SystemAudioError.tapCreationFailed(tapStatus)
        }
        self.tapID = newTapID

        // 2. Create aggregate device with the tap
        let outputDeviceUID = try readDefaultOutputDeviceUID()

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Pheme-SystemCapture",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapDriftCompensationKey as String: true,
                    kAudioSubTapUIDKey as String: tapDescription.uuid.uuidString,
                ]
            ],
        ]

        var newAggregateID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard aggStatus == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw SystemAudioError.aggregateDeviceFailed(aggStatus)
        }
        self.aggregateDeviceID = newAggregateID

        // 3. Read tap format and set up converter to 16kHz mono
        let tapFormat = try readTapFormat(tapID)
        guard let sourceFormat = AVAudioFormat(streamDescription: tapFormat) else {
            cleanup()
            throw SystemAudioError.badFormat
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        ) else {
            cleanup()
            throw SystemAudioError.badFormat
        }

        guard let newConverter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            cleanup()
            throw SystemAudioError.converterFailed
        }
        self.converter = newConverter

        // 4. Start IOProc for audio capture
        let capturedConverter = newConverter
        let capturedTargetFormat = targetFormat

        var procID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, processingQueue) {
            [weak self] _, inInputData, _, _, _ in
            guard let self else { return }

            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                bufferListNoCopy: inInputData,
                deallocator: nil
            ) else { return }

            self.processAudioBuffer(inputBuffer, converter: capturedConverter, targetFormat: capturedTargetFormat)
        }
        guard ioStatus == noErr else {
            cleanup()
            throw SystemAudioError.ioProcFailed(ioStatus)
        }
        self.ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateDeviceID, procID)
        guard startStatus == noErr else {
            cleanup()
            throw SystemAudioError.startFailed(startStatus)
        }

        isRunning = true
        NSLog("[Pheme] System audio capture started (format: %.0fHz %dch → 16kHz mono)",
              sourceFormat.sampleRate, sourceFormat.channelCount)
    }

    func stop() {
        guard isRunning else { return }
        cleanup()
        isRunning = false
        DispatchQueue.main.async { [weak self] in self?.audioLevel = 0 }
        NSLog("[Pheme] System audio capture stopped")
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ inputBuffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let ratio = 24000.0 / inputBuffer.format.sampleRate
        let frameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        guard frameCount > 0,
              let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

        var error: NSError?
        converter.convert(to: converted, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }
        guard error == nil, let data = converted.floatChannelData?[0] else { return }

        let count = Int(converted.frameLength)
        let samples = Array(UnsafeBufferPointer(start: data, count: count))

        onAudioChunk?(samples)

        // Update level meter
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / max(Float(count), 1))
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = min(1.0, rms * 10)
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        if let procID = ioProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            ioProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        converter = nil
    }

    // MARK: - Core Audio Helpers

    private func translatePID(_ pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processObject: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var mutablePid = pid

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &mutablePid,
            &size,
            &processObject
        )
        guard status == noErr, processObject != kAudioObjectUnknown else {
            throw SystemAudioError.pidTranslationFailed(pid, status)
        }
        return processObject
    }

    private func readDefaultOutputDeviceUID() throws -> String {
        // Get default output device ID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw SystemAudioError.noOutputDevice
        }

        // Get device UID
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)

        status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr else {
            throw SystemAudioError.noOutputDevice
        }

        return uid as String
    }

    private func readTapFormat(_ tapObjectID: AudioObjectID) throws -> UnsafeMutablePointer<AudioStreamBasicDescription> {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let desc = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
        desc.initialize(to: AudioStreamBasicDescription())

        let status = AudioObjectGetPropertyData(tapObjectID, &address, 0, nil, &size, desc)
        guard status == noErr else {
            desc.deallocate()
            throw SystemAudioError.formatReadFailed(status)
        }
        return desc
    }
}

// MARK: - Errors

enum SystemAudioError: LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case badFormat
    case converterFailed
    case ioProcFailed(OSStatus)
    case startFailed(OSStatus)
    case pidTranslationFailed(pid_t, OSStatus)
    case noOutputDevice
    case formatReadFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let s): return "Failed to create audio tap (status: \(s)). Grant system audio permission in System Settings."
        case .aggregateDeviceFailed(let s): return "Failed to create aggregate device (status: \(s))"
        case .badFormat: return "Invalid audio format"
        case .converterFailed: return "Could not create audio converter"
        case .ioProcFailed(let s): return "Failed to create IO proc (status: \(s))"
        case .startFailed(let s): return "Failed to start capture (status: \(s))"
        case .pidTranslationFailed(let pid, let s): return "Failed to translate PID \(pid) (status: \(s))"
        case .noOutputDevice: return "No output audio device found"
        case .formatReadFailed(let s): return "Failed to read tap format (status: \(s))"
        }
    }
}
