//
//  SuggestionCard.swift
//
//  The gentle, dismissible offer for a Smart Moment. A small glass card with a
//  warm question, two warmly-worded choices, and an "Always do this" tick. It
//  is never a modal and never blocks; ignoring it lets it fade away on its own.

import SwiftUI

struct SuggestionCard: View {
    let suggestion: Suggestion
    let onAccept: (_ always: Bool) -> Void
    let onDismiss: () -> Void

    @State private var always = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(suggestion.title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Toggle(Copy.alwaysDoThis, isOn: $always)
                .toggleStyle(.checkbox)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(suggestion.actionLabel) { onAccept(always) }
                    .buttonStyle(.glassProminent)
                Button(suggestion.dismissLabel, action: onDismiss)
                    .buttonStyle(.glass)
                Spacer()
            }
            .font(.system(.callout, design: .rounded, weight: .medium))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
