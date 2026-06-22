//
//  Announce.swift
//
//  Posts a VoiceOver announcement. Used so every audio change - the silent
//  auto-switch (high priority, via the toast) and an explicit switch (medium,
//  so it doesn't interrupt) - is perceivable, not just visible.

import AppKit

enum Announce {
    static func say(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: priority.rawValue]
        )
    }
}
