//
//  DeviceKind.swift
//
//  Maps a device to the friendly SF Symbol that represents it in a row and in
//  the menu-bar icon. Name tokens settle the cases transport type can't:
//  a Studio Display connects over Thunderbolt (not HDMI), and a USB speakerphone
//  has a mic but isn't a headset.

import SimplyCoreAudio

enum DeviceKind: Sendable {
    case builtInSpeakers
    case builtInMic
    case headphones
    case display
    case external
    case unknown

    /// SF Symbol name. All are long-stable system symbols so a row never
    /// renders an empty glyph.
    var symbol: String {
        switch self {
        case .builtInSpeakers: return "speaker.wave.2.fill"
        case .builtInMic: return "mic.fill"
        case .headphones: return "headphones"
        case .display: return "display"
        case .external: return "hifispeaker.fill"
        case .unknown: return "waveform"
        }
    }

    static func classify(transport: TransportType?, hasInput: Bool, hasOutput: Bool, name: String) -> DeviceKind {
        if transport == .builtIn { return hasOutput ? .builtInSpeakers : .builtInMic }

        // Name tokens win - the speakerphone case is knowingly approximate.
        let lower = name.lowercased()
        if lower.contains("display") || lower.contains("monitor") { return .display }
        if lower.contains("airpod") || lower.contains("headphone") || lower.contains("headset") || lower.contains("buds") {
            return .headphones
        }
        if lower.contains("speak") || lower.contains("conf") { return .external }

        switch transport {
        case .bluetooth, .bluetoothLE: return .headphones
        case .usb: return .external            // unknown USB audio: a neutral speaker, not "headphones"
        case .hdmi, .displayPort: return .display
        case .airPlay, .thunderbolt, .pci, .fireWire, .avb, .network: return .external
        default: return hasOutput ? .external : .unknown
        }
    }
}
