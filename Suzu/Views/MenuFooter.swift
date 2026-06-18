//
//  MenuFooter.swift
//
//  The quiet footer: a small Settings affordance and Quit. Deliberately
//  understated - secondary text, no shouting.

import AppKit
import SwiftUI

struct MenuFooter: View {
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Button(Copy.settings, action: openSettings)
                .buttonStyle(.plain)
            Spacer()
            Button(Copy.quit) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
        }
        .font(.system(.callout, design: .rounded))
        .foregroundStyle(.secondary)
    }
}
