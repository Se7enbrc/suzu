//
//  SuggestionCard.swift
//
//  The gentle, dismissible offer for a Smart Moment. A warm question and two
//  warmly-worded choices; the "Always do this" tick only appears once the
//  moment has been seen before, so the first encounter is a clean question.
//
//  This is a CONTENT-layer card - a solid elevated fill, not glass - because it
//  lives inside the popover's own glass, and glass-on-glass is forbidden. The
//  buttons keep their glass: they're functional controls floating on the card.

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

            if suggestion.showAlways {
                Toggle(Copy.alwaysDoThis, isOn: $always)
                    .toggleStyle(.checkbox)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(suggestion.actionLabel) { onAccept(suggestion.showAlways && always) }
                    .buttonStyle(.glassProminent)
                Button(suggestion.dismissLabel, action: onDismiss)
                    .buttonStyle(.glass)
                Spacer()
            }
            .font(.system(.callout, design: .rounded, weight: .medium))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
