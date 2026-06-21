//
//  LaunchAtLogin.swift
//
//  Login-item registration via SMAppService. Sandbox-safe and needs no extra
//  entitlement. Best-effort: a failure (e.g. an unsigned local build) is logged
//  and swallowed rather than surfaced to the person.

import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns whether the change was applied. A failure is logged, swallowed,
    /// and reported so the toggle can revert to the real status.
    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            Log.app.error("launch-at-login \(on ? "register" : "unregister") failed: \(error.localizedDescription)")
            return false
        }
    }
}
