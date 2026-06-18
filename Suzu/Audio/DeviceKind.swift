//
//  DeviceKind.swift
//
//  Maps a device to the friendly SF Symbol that represents it in a row and in
//  the menu-bar icon. The classification is deliberately coarse - just enough
//  to pick the right little picture (headphones, a speaker, a display).

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

    static func classify(transport: TransportType?, hasInput: Bool, hasOutput: Bool) -> DeviceKind {
        switch transport {
        case .builtIn:
            return hasOutput ? .builtInSpeakers : .builtInMic
        case .bluetooth, .bluetoothLE:
            return .headphones
        case .usb:
            // A USB device with a mic is a headset; output-only is a speaker.
            return hasInput ? .headphones : .external
        case .hdmi, .displayPort:
            return .display
        case .airPlay, .thunderbolt, .pci, .fireWire, .avb, .network:
            return .external
        default:
            return hasOutput ? .external : .unknown
        }
    }
}
