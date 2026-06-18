//
//  FirstRunView.swift
//
//  One warm screen, not a wizard: a sentence about what suzu does and a single
//  button that drops her straight into a working menu. No account, no
//  permissions, no steps. Presented once by WelcomePresenter.

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

/// Shows the welcome screen exactly once, as a centered, focus-taking window.
@MainActor
final class WelcomePresenter {
    static let shared = WelcomePresenter()
    private init() {}

    private var window: NSWindow?

    func show(onContinue: @escaping () -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: FirstRunView(onContinue: { [weak self] in
            onContinue()
            self?.close()
        }))
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func close() { window?.close() }
}
