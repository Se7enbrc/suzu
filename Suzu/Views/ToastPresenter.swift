//
//  ToastPresenter.swift
//
//  The momentary "Switched to … · Undo" note that follows a silent (automatic)
//  switch. A small non-activating glass panel near the menu bar that fades in,
//  offers a single Undo, and fades out after a few seconds. It never steals
//  focus. On show it posts a high-priority accessibility announcement, so the
//  auto-switch and its Undo are perceivable to VoiceOver users, not just seen.
//  Hovering the toast pauses the countdown and resumes the remaining time, so
//  reaching for Undo never races a fade. Glass here is legitimate - the panel
//  floats over arbitrary content.

import AppKit
import SwiftUI

@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()
    private init() {}

    private static let size = NSSize(width: 320, height: 64)
    private static let lifetime: Duration = .seconds(8)

    private let clock = ContinuousClock()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var deadline: ContinuousClock.Instant?
    private var hovering = false

    func show(_ content: ToastContent) {
        dismissal?.cancel()
        hovering = false

        let panel = panel ?? makePanel()
        self.panel = panel

        panel.contentView = NSHostingView(rootView:
            ToastView(
                content: content,
                onUndo: { [weak self] in
                    content.action()
                    self?.dismiss()
                },
                onHover: { [weak self] hovering in self?.setHovering(hovering) }
            )
            .frame(width: Self.size.width, height: Self.size.height)
        )
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 1
        }

        Announce.say(announcement(for: content), priority: .high)
        startCountdown(Self.lifetime)
    }

    func dismiss() {
        dismissal?.cancel()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            // The completion handler is delivered on the main thread.
            MainActor.assumeIsolated { panel?.orderOut(nil) }
        })
    }

    private func setHovering(_ hovering: Bool) {
        self.hovering = hovering
        if hovering {
            dismissal?.cancel()   // pause; the deadline is retained
        } else if let deadline {
            let remaining = clock.now.duration(to: deadline)
            if remaining > .zero { startCountdown(remaining) } else { dismiss() }
        } else {
            startCountdown(Self.lifetime)
        }
    }

    private func startCountdown(_ duration: Duration) {
        dismissal?.cancel()
        deadline = clock.now.advanced(by: duration)
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func announcement(for content: ToastContent) -> String {
        content.actionLabel.isEmpty ? content.message : "\(content.message). \(content.actionLabel) available."
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let inset: CGFloat = 12
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - Self.size.width - inset,
            y: visible.maxY - Self.size.height - inset
        ))
    }
}

private struct ToastView: View {
    let content: ToastContent
    let onUndo: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(content.message)
                .font(.system(.callout, design: .rounded, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if !content.actionLabel.isEmpty {
                Button(content.actionLabel, action: onUndo)
                    .buttonStyle(.glass)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onHover(perform: onHover)
    }
}
