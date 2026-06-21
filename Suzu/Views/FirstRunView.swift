//
//  FirstRunView.swift
//
//  One warm screen, not a wizard: a sentence about what suzu does and a single
//  button that drops you straight into a working menu. No account, no
//  permissions, no steps. Presented once by WelcomePresenter, which marks first
//  run complete on ANY dismissal so it never reappears - and never gets lost.

import AppKit
import SwiftUI

struct FirstRunView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.fill")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text(Copy.welcomeTitle)
                .font(.system(.title, design: .rounded, weight: .bold))

            Text(Copy.welcomeBody)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            Button(Copy.welcomeButton, action: onContinue)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(width: 460)
    }
}

/// Shows the welcome screen once, as a centered window. Completion fires on any
/// dismissal (button, close box, Cmd-W) exactly once, so first-run survives a
/// force-quit mid-onboarding.
@MainActor
final class WelcomePresenter: NSObject, NSWindowDelegate {
    static let shared = WelcomePresenter()
    private override init() { super.init() }

    private var window: NSWindow?
    private var onComplete: (() -> Void)?
    private var completed = false

    func show(onContinue: @escaping () -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        completed = false
        onComplete = onContinue

        let controller = NSHostingController(rootView: FirstRunView(onContinue: { [weak self] in self?.finish() }))
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        onComplete?()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) { finish() }
}
