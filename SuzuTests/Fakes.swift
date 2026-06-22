//
//  Fakes.swift
//
//  In-memory test doubles + helpers. The Smart Moments engine depends only on
//  the AudioRouting protocol, a disposable Preferences, and injected closures,
//  so the whole machine runs here without CoreAudio or AppKit.

import Foundation
import Testing
@testable import Suzu

@MainActor
final class FakeAudioRouting: AudioRouting {
    var outputs: [DeviceSnapshot] = []
    var inputs: [DeviceSnapshot] = []
    var currentOutputUID: String?
    var currentInputUID: String?
    var builtInOutput: DeviceSnapshot?
    var builtInInput: DeviceSnapshot?

    /// Make the next routing write fail, to test the "don't claim success" path.
    var routeFails = false
    private(set) var routeCalls: [(out: String?, inp: String?)] = []

    var currentOutput: DeviceSnapshot? { outputs.first { $0.uid == currentOutputUID } }
    var currentInput: DeviceSnapshot? { inputs.first { $0.uid == currentInputUID } }
    var currentRoute: Route { Route(outputUID: currentOutputUID, inputUID: currentInputUID) }

    func route(outputUID: String?, inputUID: String?) -> Bool {
        routeCalls.append((outputUID, inputUID))
        if routeFails { return false }
        if let outputUID { currentOutputUID = outputUID }
        if let inputUID { currentInputUID = inputUID }
        return true
    }
}

@MainActor
func makeSnapshot(_ uid: String, _ kind: DeviceKind, out: Bool = false, inp: Bool = false) -> DeviceSnapshot {
    DeviceSnapshot(id: 0, uid: uid, name: uid, kind: kind, hasInput: inp, hasOutput: out)
}

@MainActor
func ephemeralPreferences() -> Preferences {
    let suite = UserDefaults(suiteName: "suzu.tests.\(UUID().uuidString)")!
    return Preferences(store: suite)
}
