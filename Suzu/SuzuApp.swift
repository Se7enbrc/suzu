//
//  SuzuApp.swift
//
//  App entry. A menu-bar-only (LSUIElement) app with two scenes: the popover
//  panel and a small Settings window. The welcome screen and the undo toast are
//  presented from AppKit (WelcomePresenter / ToastPresenter), so they don't need
//  a window scene of their own.
//
//  The three managers are created once here, wired together, and started from
//  AppDelegate.applicationDidFinishLaunching so ordering is deterministic and
//  Smart Moments are live whether or not the menu is ever opened.

import AppKit
import SwiftUI

@main
struct SuzuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var audio: AudioController
    @State private var prefs: Preferences
    @State private var moments: SmartMomentsEngine

    init() {
        let prefs = Preferences()
        let audio = AudioController()
        let moments = SmartMomentsEngine(audio: audio, prefs: prefs)
        audio.onWorldChanged = { [weak moments] change in moments?.handle(change) }

        _prefs = State(initialValue: prefs)
        _audio = State(initialValue: audio)
        _moments = State(initialValue: moments)

        AppDelegate.bootstrap = {
            // Enable launch-at-login once (on by default), then never re-assert
            // it - so suzu honors a later removal in System Settings.
            if !prefs.didConfigureLogin {
                prefs.setLaunchAtLogin(true)
                prefs.didConfigureLogin = true
            } else {
                prefs.refreshLaunchAtLogin()
            }
            audio.start()
            if !prefs.firstRunComplete {
                WelcomePresenter.shared.show { prefs.firstRunComplete = true }
            }
            Log.app.notice("suzu launched")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(audio)
                .environment(moments)
                .environment(prefs)
        } label: {
            MenuBarLabel(
                symbol: audio.menuBarSymbol,
                pending: moments.hasPendingSuggestion,
                outputName: audio.currentOutput?.name
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(prefs)
                .containerBackground(.thinMaterial, for: .window)
        }
    }
}

/// The menu-bar glyph mirrors where sound is going, with a soft dot when a Smart
/// Moment is quietly waiting in the menu. The dot reads as a gentle invitation,
/// not an alert - a thin ring keeps it visible on any background.
private struct MenuBarLabel: View {
    let symbol: String
    let pending: Bool
    let outputName: String?

    var body: some View {
        Image(systemName: symbol)
            .overlay(alignment: .topTrailing) {
                if pending {
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
                        .offset(x: 3, y: -2)
                        .accessibilityHidden(true)
                }
            }
            // The dot is decorative; fold its meaning into the label + tooltip so
            // VoiceOver and a mouse hover both surface a waiting suggestion.
            .accessibilityLabel(Copy.menuBarLabel(output: outputName, pending: pending))
            .help(Copy.menuBarLabel(output: outputName, pending: pending))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `SuzuApp.init` and run once at launch. Both the writer (App.init)
    /// and the reader (this delegate method) are main-actor isolated, so the
    /// slot can be too - no `nonisolated(unsafe)` required.
    @MainActor static var bootstrap: (@MainActor () -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.bootstrap?()
    }
}
