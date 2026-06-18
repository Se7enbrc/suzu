//
//  RightNowHeader.swift
//
//  The calm header that says, in plain words, where sound and mic are right
//  now - one line when they're together, two when they're split. Content
//  layer: no glass, just clear type.

import SwiftUI

struct RightNowHeader: View {
    let rightNow: AudioController.RightNow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rightNow.primary)
                .font(.system(.headline, design: .rounded))
            if let secondary = rightNow.secondary {
                Text(secondary)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
