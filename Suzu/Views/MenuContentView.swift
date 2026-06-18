//
//  MenuContentView.swift
//
//  The whole popover, top to bottom: a Smart Moment card (when there is one),
//  the "right now" header, the output list, the input list, and the quiet
//  footer. That's the entire surface - no EQ, no sliders, no meters.

import CoreAudio
import SwiftUI

struct MenuContentView: View {
    @Environment(AudioController.self) private var audio
    @Environment(SmartMomentsEngine.self) private var moments
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let suggestion = moments.suggestion {
                SuggestionCard(
                    suggestion: suggestion,
                    onAccept: { moments.accept(suggestion, always: $0) },
                    onDismiss: { moments.decline(suggestion) }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            RightNowHeader(rightNow: audio.rightNow)

            deviceSection(Copy.soundSection, devices: audio.outputs, currentID: audio.currentOutputID) {
                audio.selectOutput($0)
            }
            deviceSection(Copy.micSection, devices: audio.inputs, currentID: audio.currentInputID) {
                audio.selectInput($0)
            }

            Divider()
            MenuFooter { openSettings() }
        }
        .padding(14)
        .frame(width: 300)
        .animation(.bouncy, value: moments.suggestion)
        .animation(.bouncy, value: audio.currentOutputID)
        .animation(.bouncy, value: audio.currentInputID)
    }

    @ViewBuilder
    private func deviceSection(
        _ title: String,
        devices: [DeviceSnapshot],
        currentID: AudioObjectID?,
        select: @escaping (AudioObjectID) -> Void
    ) -> some View {
        if !devices.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                ForEach(devices) { device in
                    DeviceRow(device: device, isCurrent: device.id == currentID) {
                        select(device.id)
                    }
                }
            }
        }
    }
}
