//
//  SuzuApp.swift
//
//  App entry. A menu-bar-only (LSUIElement) app with two scenes: the popover
//  panel and a small Settings window. The welcome screen and the undo toast are
//  presented from AppKit (WelcomePresenter / ToastPresenter), so they don't
//  need a window scene of their own.
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
            LaunchAtLogin.setEnabled(prefs.launchAtLogin)
            audio.start()
            if !prefs.firstRunComplete {
                // Mark seen as soon as it's shown, so it never reappears no
                // matter how she dismisses it.
                prefs.firstRunComplete = true
                WelcomePresenter.shared.show {}
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
            MenuBarLabel(symbol: audio.menuBarSymbol, pending: moments.hasPendingSuggestion)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(prefs)
                .containerBackground(.thinMaterial, for: .window)
        }
    }
}

/// The menu-bar glyph mirrors where sound is going, with a small dot when a
/// Smart Moment is quietly waiting in the menu.
private struct MenuBarLabel: View {
    let symbol: String
    let pending: Bool

    var body: some View {
        Image(systemName: symbol)
            .overlay(alignment: .topTrailing) {
                if pending {
                    Circle()
                        .fill(.tint)
                        .frame(width: 6, height: 6)
                        .offset(x: 2, y: -2)
                }
            }
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
