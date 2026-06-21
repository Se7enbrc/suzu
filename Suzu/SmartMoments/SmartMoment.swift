//
//  SmartMoment.swift
//
//  The situations suzu can quietly help with. Each is independently toggleable
//  in Settings (plain-English title), on by default, and remembers its own
//  answer ("ask" / "always" / "never") plus how many times it's been declined.

enum SmartMoment: String, CaseIterable, Identifiable, Sendable {
    /// A headset (sound *and* mic) arrives - keep both together on it.
    case headsetTogether
    /// The headset left and the lid is open - offer the Mac's own speakers/mic.
    case backToSpeakers

    var id: String { rawValue }

    /// Plain-words label for the Settings toggle. No jargon.
    var settingsTitle: String {
        switch self {
        case .headsetTogether: return "When a headset connects, use it for sound and mic"
        case .backToSpeakers: return "When a headset disconnects, offer the built-in speakers"
        }
    }

    var enabledKey: String { "suzu.moment.\(rawValue).enabled" }
    var policyKey: String { "suzu.moment.\(rawValue).policy" }
    var declinesKey: String { "suzu.moment.\(rawValue).declines" }
}

/// What suzu does the next time a moment happens.
enum MomentPolicy: String, Sendable {
    /// Ask with a gentle, dismissible card (the default).
    case ask
    /// Just do it, with a momentary undo.
    case always
    /// Leave it alone.
    case never
}
