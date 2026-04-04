import AVFoundation
import Foundation

/// Centralized permission checks for Pheme.
enum PermissionManager {
    enum MicStatus {
        case granted
        case denied
        case undetermined
    }

    static var microphoneStatus: MicStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
