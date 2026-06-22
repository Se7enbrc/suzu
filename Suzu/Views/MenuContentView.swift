//
//  MenuContentView.swift
//
//  The whole popover, top to bottom: a Smart Moment card (when there is one),
//  the "right now" header, the output list, the input list, and the quiet
//  footer. That's the entire surface - no EQ, no sliders, no meters. Long
//  device lists scroll so Settings and Quit are never pushed off-screen.

import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(AudioController.self) private var audio
    @Environment(SmartMomentsEngine.self) private var moments
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Beyond this many devices, the lists scroll instead of growing the popover.
    private static let scrollThreshold = 8

    private var isEmpty: Bool { audio.outputs.isEmpty && audio.inputs.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let suggestion = moments.suggestion {
                SuggestionCard(
                    suggestion: suggestion,
                    onAccept: { moments.accept(always: $0) },
                    onDismiss: { moments.decline() }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }

            if isEmpty {
                emptyState
            } else {
                RightNowHeader(rightNow: audio.rightNow)
                if audio.outputs.count + audio.inputs.count > Self.scrollThreshold {
                    ScrollView { deviceLists }
                        .frame(height: 360)
                        .scrollBounceBehavior(.basedOnSize)
                } else {
                    deviceLists
                }
            }

            Divider()
            MenuFooter {
                // A menu-bar-only app can open Settings behind everything.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
        .padding(14)
        .frame(width: 300)
        .animation(reduceMotion ? nil : .smooth, value: moments.suggestion)
        .animation(reduceMotion ? nil : .smooth, value: audio.currentOutputUID)
        .animation(reduceMotion ? nil : .smooth, value: audio.currentInputUID)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(Copy.noDevices)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var deviceLists: some View {
        VStack(alignment: .leading, spacing: 12) {
            deviceSection(Copy.soundSection, devices: audio.outputs, currentUID: audio.currentOutputUID) {
                audio.selectOutput($0)
            }
            deviceSection(Copy.micSection, devices: audio.inputs, currentUID: audio.currentInputUID) {
                audio.selectInput($0)
            }
        }
    }

    @ViewBuilder
    private func deviceSection(
        _ title: String,
        devices: [DeviceSnapshot],
        currentUID: String?,
        select: @escaping (String) -> Void
    ) -> some View {
        if !devices.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .accessibilityAddTraits(.isHeader)
                ForEach(devices) { device in
                    DeviceRow(device: device, isCurrent: device.uid == currentUID) {
                        select(device.uid)
                    }
                }
            }
        }
    }
}
