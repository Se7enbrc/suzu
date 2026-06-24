//
//  SmartMoment.swift
//
//  The situations suzu can quietly help with. Each is independently toggleable
//  in Settings (plain-English title), on by default, and remembers its own
//  answer ("ask" / "always" / "never") plus how many times it's been declined.

enum SmartMoment: String, CaseIterable, Identifiable, Sendable {
    /// A headset (sound *and* mic) arrives - keep both together on it.
    case headsetTogether
    /// The current device left - land on a remembered device that's still here,
    /// else the Mac's own speakers/mic.
    case backToSpeakers
    /// A device you've used before reconnected - offer to switch back to it.
    case favoriteReturned

    var id: String { rawValue }

    /// Plain-words label for the Settings toggle. No jargon.
    var settingsTitle: String {
        switch self {
        case .headsetTogether: return "When a headset connects, use it for sound and mic"
        case .backToSpeakers: return "When a device disconnects, fall back to your Mac or one you’ve used"
        case .favoriteReturned: return "When a device I’ve used before reconnects, switch back to it"
        }
    }

    var enabledKey: String { "suzu.moment.\(rawValue).enabled" }
    var policyKey: String { "suzu.moment.\(rawValue).policy" }
    var declinesKey: String { "suzu.moment.\(rawValue).declines" }
    var offersKey: String { "suzu.moment.\(rawValue).offers" }
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
