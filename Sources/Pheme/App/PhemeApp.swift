import SwiftUI
import SwiftData

@main
struct PhemeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(appState)
        }
        .modelContainer(for: [Meeting.self, TranscriptSegment.self])

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuBarView(appState: appState)
                .modelContainer(for: [Meeting.self, TranscriptSegment.self])
        } label: {
            Label("Pheme", systemImage: appState.session.isRecording ? "record.circle" : "waveform")
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "soundEnabled": true,
        ])
        NSLog("[Pheme] App launched")

        if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
            showOnboarding()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showOnboarding() {
        let view = OnboardingView {
            DispatchQueue.main.async { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Pheme"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}
