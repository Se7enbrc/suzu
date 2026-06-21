//
//  Copy.swift
//
//  Every user-facing string lives here. Voice: clear, calm, and plain -
//  friendly without being cute, and free of audio jargon. Devices are named the
//  way a person would ("MacBook speakers", "AirPods Pro"), never by their
//  CoreAudio identifiers. A string is part of the design; keep it that way.

enum Copy {
    // Smart Moment: a headset connects.
    static let headsetTitle = "Use your headset for sound and mic?"
    static let headsetAction = "Use headset"
    static let headsetDismiss = "Not now"

    // Smart Moment: back to the built-in speakers.
    static let speakersTitle = "Switch back to your Mac’s speakers and mic?"
    static let speakersAction = "Switch"
    static let speakersDismiss = "Stay"

    static let alwaysDoThis = "Always do this"

    // Undo toast.
    static let undo = "Undo"
    static func switched(to name: String) -> String { "Switched to \(name)" }

    // Menu surface.
    static let soundSection = "Sound"
    static let micSection = "Mic"
    static let settings = "Settings…"
    static let quit = "Quit suzu"

    static func soundAndMic(_ name: String) -> String { "Sound and mic: \(name)" }
    static func sound(_ name: String) -> String { "Sound: \(name)" }
    static func mic(_ name: String) -> String { "Mic: \(name)" }
    static let nowhere = "—"

    // First run.
    static let welcomeTitle = "Welcome to suzu"
    static let welcomeBody =
        "suzu keeps your sound and mic where you want them. Click the menu bar "
        + "icon to see where they’re going, or to move them — every change can be undone."
    static let welcomeButton = "Get started"

    // Settings.
    static let settingsTitle = "suzu"
    static let settingsSubtitle = "Keep your sound and mic where you want them."
    static let launchAtLogin = "Open suzu automatically at login"
    static let smartHeading = "Automatic switching"
    static let aboutHeading = "About"
}
