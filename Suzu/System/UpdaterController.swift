//
//  UpdaterController.swift
//
//  Owns the Sparkle updater for the app's lifetime and surfaces the two pieces
//  of update UI suzu shows: a "Check for Updates…" button and an "automatically
//  check" toggle, both living in Settings (this is a menu-bar-only app, so there
//  is no app menu to host them).
//
//  The whole file is gated on `canImport(Sparkle)` so suzu still builds without
//  the Sparkle package linked - a Mac App Store build drops Sparkle entirely and
//  these symbols simply don't exist (the App Store delivers its own updates).
//  Feed URL + ed25519 public key live in Info.plist (SUFeedURL / SUPublicEDKey);
//  updates are published by `make release-publish`.

#if canImport(Sparkle)
import Sparkle
import SwiftUI

/// Holds the Sparkle updater for the whole run. `SPUStandardUpdaterController`
/// wires the standard user driver (the "update available" / progress panels)
/// and starts the background scheduler. One shared instance.
@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    private init() {
        // Sparkle only offers an update when the appcast's build number is
        // strictly greater than the running build's, so there's nothing to gate
        // by build type: a dev build older than a release picks it up; one at or
        // past the latest release stays quiet.
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var updater: SPUUpdater { controller.updater }
}

/// Mirrors Sparkle's KVO-observable `canCheckForUpdates` as Observation-tracked
/// state, so the button can disable itself while a check is already running.
@MainActor
@Observable
final class UpdateAvailability {
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(_ updater: SPUUpdater) {
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            // Sparkle posts this KVO change on the main thread; assert it so the
            // @MainActor write needs no Task hop.
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }
}

/// The update rows for the Settings "About" section: an automatic-check toggle
/// and a "Check for Updates…" button that greys out mid-check.
struct UpdaterSettingsRows: View {
    private let updater = UpdaterController.shared.updater
    @State private var availability = UpdateAvailability(UpdaterController.shared.updater)

    var body: some View {
        Toggle(Copy.automaticUpdates, isOn: Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        ))
        Button(Copy.checkForUpdates) { updater.checkForUpdates() }
            .disabled(!availability.canCheckForUpdates)
    }
}
#endif
