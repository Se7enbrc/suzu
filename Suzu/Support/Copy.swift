//
//  Copy.swift
//
//  Every user-facing string lives here. Voice: warm, plain, lightly
//  first-person, never technical. Devices are named the way a person would
//  ("MacBook speakers", "AirPods Pro"), so none of these strings carry
//  CoreAudio vocabulary. Keep it that way - a string is part of the design.

enum Copy {
    // Smart Moment: headset arrives.
    static let headsetTitle = "Use your headset for sound and mic?"
    static let headsetAction = "Use headset"
    static let headsetDismiss = "Not now"

    // Smart Moment: back to the built-in speakers.
    static let speakersTitle = "Back to your Mac’s speakers and mic?"
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

    static func soundAndMic(_ name: String) -> String { "Sound and mic: \(name)." }
    static func sound(_ name: String) -> String { "Sound: \(name)" }
    static func mic(_ name: String) -> String { "Mic: \(name)" }
    static let nowhere = "—"

    // First run.
    static let welcomeTitle = "Hi — I’m suzu"
    static let welcomeBody =
        "I’ll keep your sound and mic where you want them. Click the bell in the "
        + "menu bar any time to see where they’re going — or to move them. "
        + "Nothing I do can’t be undone."
    static let welcomeButton = "Sounds good"

    // Settings.
    static let settingsTitle = "suzu"
    static let settingsSubtitle = "Keep your sound and mic where you want them."
    static let launchAtLogin = "Open suzu automatically when I log in"
    static let smartHeading = "Looking after you"
    static let aboutHeading = "About"
}
