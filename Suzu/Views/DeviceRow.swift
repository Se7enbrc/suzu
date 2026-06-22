//
//  DeviceRow.swift
//
//  One device, SoundSource-style: a device-appropriate symbol, the friendly
//  name, and a checkmark when it's the current one. The current row is
//  unmistakably highlighted - by tint, a checkmark, and a VoiceOver "selected"
//  trait, never colour alone - so there's never any hunting for "where am I
//  now". No glass here: rows are the content layer.

import SwiftUI

struct DeviceRow: View {
    let device: DeviceSnapshot
    let isCurrent: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let row = Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
                Text(device.name)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(rowBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(isCurrent ? Copy.deviceCurrent(device.name) : device.name)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)

        if isCurrent {
            row
        } else {
            row.accessibilityHint(Copy.switchHint)
        }
    }

    private var rowBackground: AnyShapeStyle {
        if isCurrent {
            // Same tint as the checkmark; stronger fill when Increase Contrast is
            // on, so the highlight never washes out against vibrancy.
            return AnyShapeStyle(.tint.opacity(contrast == .increased ? 0.32 : 0.16))
        }
        if hovering { return AnyShapeStyle(Color.primary.opacity(0.06)) }
        return AnyShapeStyle(Color.clear)
    }
}
