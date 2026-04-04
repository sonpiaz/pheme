import ServiceManagement

enum LaunchAtLogin {
    static func set(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                NSLog("[Pheme] Launch at login enabled")
            } else {
                try SMAppService.mainApp.unregister()
                NSLog("[Pheme] Launch at login disabled")
            }
        } catch {
            NSLog("[Pheme] Launch at login error: %@", error.localizedDescription)
        }
    }
}
