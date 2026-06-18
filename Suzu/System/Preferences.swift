//
//  Preferences.swift
//
//  UserDefaults-backed settings, in the house style: an @Observable held by the
//  app and persisted from `didSet`. The two visible toggles (a Smart Moment's
//  on/off and launch-at-login) are observed stored properties so the Settings
//  controls react; the internal per-moment policy and decline count are read
//  and written on demand (they don't drive a visible control directly).

import Foundation
import Observation

@MainActor
@Observable
final class Preferences {
    @ObservationIgnored private let store = UserDefaults.standard

    var firstRunComplete: Bool { didSet { store.set(firstRunComplete, forKey: Key.firstRun) } }
    var launchAtLogin: Bool {
        didSet {
            store.set(launchAtLogin, forKey: Key.launchAtLogin)
            LaunchAtLogin.setEnabled(launchAtLogin)
        }
    }
    var headsetTogetherEnabled: Bool {
        didSet { store.set(headsetTogetherEnabled, forKey: SmartMoment.headsetTogether.enabledKey) }
    }
    var backToSpeakersEnabled: Bool {
        didSet { store.set(backToSpeakersEnabled, forKey: SmartMoment.backToSpeakers.enabledKey) }
    }

    init() {
        store.register(defaults: [
            Key.launchAtLogin: true,
            SmartMoment.headsetTogether.enabledKey: true,
            SmartMoment.backToSpeakers.enabledKey: true
        ])
        firstRunComplete = store.bool(forKey: Key.firstRun)
        launchAtLogin = store.bool(forKey: Key.launchAtLogin)
        headsetTogetherEnabled = store.bool(forKey: SmartMoment.headsetTogether.enabledKey)
        backToSpeakersEnabled = store.bool(forKey: SmartMoment.backToSpeakers.enabledKey)
    }

    // MARK: - Per-moment enabled (observed, drives the Settings toggle)

    func isEnabled(_ moment: SmartMoment) -> Bool {
        switch moment {
        case .headsetTogether: return headsetTogetherEnabled
        case .backToSpeakers: return backToSpeakersEnabled
        }
    }

    func setEnabled(_ moment: SmartMoment, _ on: Bool) {
        switch moment {
        case .headsetTogether: headsetTogetherEnabled = on
        case .backToSpeakers: backToSpeakersEnabled = on
        }
        // Turning a moment back on clears its "no thanks" memory.
        if on { setPolicy(moment, .ask); resetDeclines(moment) }
    }

    // MARK: - Per-moment policy + decline count (internal memory)

    func policy(_ moment: SmartMoment) -> MomentPolicy {
        MomentPolicy(rawValue: store.string(forKey: moment.policyKey) ?? "") ?? .ask
    }

    func setPolicy(_ moment: SmartMoment, _ policy: MomentPolicy) {
        store.set(policy.rawValue, forKey: moment.policyKey)
    }

    func declines(_ moment: SmartMoment) -> Int { store.integer(forKey: moment.declinesKey) }

    /// Records one decline and returns the new total.
    func recordDecline(_ moment: SmartMoment) -> Int {
        let next = declines(moment) + 1
        store.set(next, forKey: moment.declinesKey)
        return next
    }

    func resetDeclines(_ moment: SmartMoment) { store.set(0, forKey: moment.declinesKey) }

    private enum Key {
        static let firstRun = "suzu.firstRunComplete"
        static let launchAtLogin = "suzu.launchAtLogin"
    }
}
