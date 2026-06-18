//
//  DeviceRow.swift
//
//  One device, SoundSource-style: a device-appropriate symbol, the friendly
//  name, and a checkmark when it's the current one. The current row is
//  unmistakably highlighted so there's never any hunting for "where am I now".
//  No glass here - rows are the content layer.

import SwiftUI

struct DeviceRow: View {
    let device: DeviceSnapshot
    let isCurrent: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(device.name)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tint)
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
    }

    private var rowBackground: AnyShapeStyle {
        if isCurrent { return AnyShapeStyle(Color.accentColor.opacity(0.15)) }
        if hovering { return AnyShapeStyle(Color.primary.opacity(0.06)) }
        return AnyShapeStyle(Color.clear)
    }
}
