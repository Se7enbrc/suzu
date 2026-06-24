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

    // Smart Moment: back to the built-in speakers (and the mic-only variant).
    static let speakersTitle = "Switch back to your Mac’s speakers and mic?"
    static let speakersAction = "Switch"
    static let speakersDismiss = "Not now"
    static let micTitle = "Use your Mac’s mic again?"
    static let micAction = "Use mic"

    // Smart Moment: a device you've used before reconnects.
    static func favoriteTitle(_ name: String) -> String { "Use \(name) again?" }
    static let favoriteAction = "Use it"

    static let alwaysDoThis = "Always do this"
    static let alwaysHint = "Remember this choice and stop asking"

    // Undo toast + announcements.
    static let undo = "Undo"
    static func switched(to name: String) -> String { "Switched to \(name)" }
    static func soundOn(_ name: String) -> String { "Sound on \(name)" }
    static func micOn(_ name: String) -> String { "Mic on \(name)" }
    static let couldntSwitch = "Couldn’t switch — that device just left"

    // Menu surface.
    static let soundSection = "Sound"
    static let micSection = "Mic"
    static let settings = "Settings…"
    static let quit = "Quit suzu"
    static let noDevices = "No audio devices found"

    static func soundAndMic(_ name: String) -> String { "Sound and mic: \(name)" }
    static func sound(_ name: String) -> String { "Sound: \(name)" }
    static func mic(_ name: String) -> String { "Mic: \(name)" }
    static let nowhere = "None"

    // Accessibility.
    static func deviceCurrent(_ name: String) -> String { "\(name), current" }
    static let switchHint = "Switches to this device"
    static func menuBarLabel(output: String?, pending: Bool) -> String {
        let base = output.map { "suzu, sound on \($0)" } ?? "suzu"
        return pending ? "\(base), a suggestion is waiting" : base
    }

    // First run.
    static let welcomeTitle = "Welcome to suzu"
    static let welcomeBody =
        "suzu keeps your sound and mic where you want them. Click the menu bar "
        + "icon to see where they are, or to move them — every change can be undone."
    static let welcomeButton = "Get started"

    // Settings.
    static let settingsTitle = "suzu"
    static let settingsSubtitle = "Keep your sound and mic where you want them."
    static let launchAtLogin = "Open suzu automatically at login"
    static let smartHeading = "Automatic switching"
    static let aboutHeading = "About"

    // Updates (Settings → About).
    static let automaticUpdates = "Check for updates automatically"
    static let checkForUpdates = "Check for Updates…"
}
