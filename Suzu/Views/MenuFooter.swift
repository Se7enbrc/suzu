//
//  MenuFooter.swift
//
//  The quiet footer: a small Settings affordance and Quit. Understated, but
//  each has a hover highlight so it reads as tappable (Quit must always be
//  findable), and a keyboard shortcut (Cmd-, / Cmd-Q) while the popover is open.

import AppKit
import SwiftUI

struct MenuFooter: View {
    let openSettings: () -> Void

    var body: some View {
        HStack {
            FooterButton(title: Copy.settings, key: ",", action: openSettings)
            Spacer()
            FooterButton(title: Copy.quit, key: "q") { NSApplication.shared.terminate(nil) }
        }
        .font(.system(.callout, design: .rounded))
        .foregroundStyle(.secondary)
    }
}

private struct FooterButton: View {
    let title: String
    let key: KeyEquivalent
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? AnyShapeStyle(Color.primary.opacity(0.08)) : AnyShapeStyle(Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(key, modifiers: .command)
    }
}
