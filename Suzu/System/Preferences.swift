//
//  Preferences.swift
//
//  UserDefaults-backed settings, in the house style: an @Observable held by the
//  app and persisted from `didSet`. The store is injectable so tests run against
//  a disposable suite. Launch-at-login is deliberately NOT a stored guess - it
//  mirrors the real SMAppService status, so the toggle can never lie or
//  re-assert a login item the user removed in System Settings.

import Foundation
import Observation

@MainActor
@Observable
final class Preferences {
    @ObservationIgnored private let store: UserDefaults

    var firstRunComplete: Bool { didSet { store.set(firstRunComplete, forKey: Key.firstRun) } }
    /// One-time guard: suzu enables launch-at-login once (on by default), then
    /// never re-asserts it - see `setLaunchAtLogin`.
    var didConfigureLogin: Bool { didSet { store.set(didConfigureLogin, forKey: Key.didConfigureLogin) } }
    var headsetTogetherEnabled: Bool {
        didSet { store.set(headsetTogetherEnabled, forKey: SmartMoment.headsetTogether.enabledKey) }
    }
    var backToSpeakersEnabled: Bool {
        didSet { store.set(backToSpeakersEnabled, forKey: SmartMoment.backToSpeakers.enabledKey) }
    }
    var favoriteReturnedEnabled: Bool {
        didSet { store.set(favoriteReturnedEnabled, forKey: SmartMoment.favoriteReturned.enabledKey) }
    }

    /// Reflects the real login-item status. Updated only by the two methods
    /// below, never blindly written on launch.
    private(set) var launchAtLogin: Bool

    init(store: UserDefaults = .standard) {
        self.store = store
        store.register(defaults: [
            SmartMoment.headsetTogether.enabledKey: true,
            SmartMoment.backToSpeakers.enabledKey: true,
            SmartMoment.favoriteReturned.enabledKey: true
        ])
        firstRunComplete = store.bool(forKey: Key.firstRun)
        didConfigureLogin = store.bool(forKey: Key.didConfigureLogin)
        headsetTogetherEnabled = store.bool(forKey: SmartMoment.headsetTogether.enabledKey)
        backToSpeakersEnabled = store.bool(forKey: SmartMoment.backToSpeakers.enabledKey)
        favoriteReturnedEnabled = store.bool(forKey: SmartMoment.favoriteReturned.enabledKey)
        launchAtLogin = LaunchAtLogin.isEnabled
        preferredOutputs = store.stringArray(forKey: Key.preferredOutputs) ?? []
        preferredInputs = store.stringArray(forKey: Key.preferredInputs) ?? []
    }

    // MARK: - Launch at login (mirrors SMAppService)

    /// Re-read the real status (e.g. when Settings appears) so a change made in
    /// System Settings shows up here.
    func refreshLaunchAtLogin() { launchAtLogin = LaunchAtLogin.isEnabled }

    /// Register/unregister in response to a user toggle, then reflect the actual
    /// resulting status - a failed write leaves the toggle showing the truth.
    func setLaunchAtLogin(_ on: Bool) {
        LaunchAtLogin.setEnabled(on)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    // MARK: - Per-moment enabled (observed, drives the Settings toggle)

    func isEnabled(_ moment: SmartMoment) -> Bool {
        switch moment {
        case .headsetTogether: return headsetTogetherEnabled
        case .backToSpeakers: return backToSpeakersEnabled
        case .favoriteReturned: return favoriteReturnedEnabled
        }
    }

    func setEnabled(_ moment: SmartMoment, _ on: Bool) {
        switch moment {
        case .headsetTogether: headsetTogetherEnabled = on
        case .backToSpeakers: backToSpeakersEnabled = on
        case .favoriteReturned: favoriteReturnedEnabled = on
        }
        // Turning a moment back on clears its "no thanks" memory.
        if on { setPolicy(moment, .ask); resetDeclines(moment) }
    }

    // MARK: - Per-moment memory (policy, declines, how many times offered)

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

    /// How many times this moment has been offered before (across launches) -
    /// used to hold the "Always do this" choice back until the second encounter.
    func offers(_ moment: SmartMoment) -> Int { store.integer(forKey: moment.offersKey) }
    func recordOffer(_ moment: SmartMoment) { store.set(offers(moment) + 1, forKey: moment.offersKey) }

    // MARK: - Preferred devices (most-recently chosen first)

    /// The output/input devices the user has *deliberately* chosen, newest first.
    /// Auto-fallbacks are never recorded here, so a temporary "back to built-in"
    /// never erases "I prefer the dock speakers". Drives the favourite-returned
    /// moment when a remembered device reconnects.
    @ObservationIgnored private(set) var preferredOutputs: [String]
    @ObservationIgnored private(set) var preferredInputs: [String]

    private static let preferredCap = 10

    func recordPreferredOutput(_ uid: String) {
        preferredOutputs = Self.promote(uid, in: preferredOutputs)
        store.set(preferredOutputs, forKey: Key.preferredOutputs)
    }

    func recordPreferredInput(_ uid: String) {
        preferredInputs = Self.promote(uid, in: preferredInputs)
        store.set(preferredInputs, forKey: Key.preferredInputs)
    }

    func isPreferredOutput(_ uid: String) -> Bool { preferredOutputs.contains(uid) }
    func isPreferredInput(_ uid: String) -> Bool { preferredInputs.contains(uid) }

    private static func promote(_ uid: String, in list: [String]) -> [String] {
        Array(([uid] + list.filter { $0 != uid }).prefix(preferredCap))
    }

    private enum Key {
        static let firstRun = "suzu.firstRunComplete"
        static let didConfigureLogin = "suzu.didConfigureLogin"
        static let preferredOutputs = "suzu.preferredOutputs"
        static let preferredInputs = "suzu.preferredInputs"
    }
}
