//
//  SmartMomentsEngine.swift
//
//  The "good instincts, good memory" layer. It watches device arrivals and
//  departures and, for each Smart Moment, follows one pattern:
//
//    • first time            → a gentle, dismissible suggestion (the menu shows
//                              it as a card; the menu-bar icon hints)
//    • answered "always"     → just do it, with a momentary undo toast
//    • answered "no thanks"  → stay quiet
//
//  A suggestion ignored expires on its own and won't return this launch. Three
//  explicit declines quietly switch the moment off in Settings.
//
//  Dependencies are injected (audio, the toast sink, lid state, the offer
//  lifetime) so the whole machine is unit-testable without CoreAudio or AppKit.

import Foundation
import Observation

/// A single, dismissible offer shown in the menu. One exists at a time.
struct Suggestion: Identifiable, Equatable {
    let moment: SmartMoment
    let title: String
    let actionLabel: String
    let dismissLabel: String
    let confirmName: String
    let targetOutputUID: String?
    let targetInputUID: String?
    /// Show the "Always do this" choice only after the moment has been seen
    /// before - the first encounter stays a clean two-button question.
    let showAlways: Bool

    var id: SmartMoment { moment }
}

@MainActor
@Observable
final class SmartMomentsEngine {
    /// The card the menu should show, if any.
    var suggestion: Suggestion?

    @ObservationIgnored private let audio: any AudioRouting
    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private let presentToast: @MainActor (ToastContent) -> Void
    @ObservationIgnored private let lidIsOpen: @MainActor () -> Bool?
    @ObservationIgnored private let offerLifetime: Duration

    /// Moments ignored this launch - don't re-offer until next launch.
    @ObservationIgnored private var suppressedThisSession: Set<SmartMoment> = []
    @ObservationIgnored private var expiry: Task<Void, Never>?

    private static let declineLimit = 3

    init(
        audio: any AudioRouting,
        prefs: Preferences,
        presentToast: @escaping @MainActor (ToastContent) -> Void = { ToastPresenter.shared.show($0) },
        lidIsOpen: @escaping @MainActor () -> Bool? = { LidSensor.isLidOpen },
        offerLifetime: Duration = .seconds(20)
    ) {
        self.audio = audio
        self.prefs = prefs
        self.presentToast = presentToast
        self.lidIsOpen = lidIsOpen
        self.offerLifetime = offerLifetime
    }

    var hasPendingSuggestion: Bool { suggestion != nil }

    // MARK: - Reacting to the world

    func handle(_ change: WorldChange) {
        // A headset arriving (sound + mic) is the headline moment; it wins.
        if let headset = change.added.first(where: { $0.hasInput && $0.hasOutput }) {
            considerHeadset(headset)
            return
        }
        // Observability: a headset whose input stream lags its output arrives
        // output-only and misses the moment this event (rare; the debounce
        // usually coalesces both streams into one change).
        if change.added.contains(where: { $0.kind == .headphones && $0.hasOutput && !$0.hasInput }) {
            Log.moments.info("headset-class device arrived output-only; mic not yet visible")
        }
        if !change.removed.isEmpty {
            considerBackToSpeakers()
        }
    }

    private func considerHeadset(_ headset: DeviceSnapshot) {
        let moment = SmartMoment.headsetTogether
        guard prefs.isEnabled(moment) else { return }
        // Already fully on the headset - nothing to offer.
        if audio.currentOutput?.uid == headset.uid, audio.currentInput?.uid == headset.uid { return }

        offer(Suggestion(
            moment: moment,
            title: Copy.headsetTitle,
            actionLabel: Copy.headsetAction,
            dismissLabel: Copy.headsetDismiss,
            confirmName: headset.name,
            targetOutputUID: headset.uid,
            targetInputUID: headset.uid,
            showAlways: prefs.offers(moment) > 0
        ))
    }

    private func considerBackToSpeakers() {
        let moment = SmartMoment.backToSpeakers
        guard prefs.isEnabled(moment) else { return }
        guard let speakers = audio.builtInOutput else { return }
        // Don't offer the built-in speakers while docked with the lid shut.
        if lidIsOpen() == false { return }

        let needOutput = audio.currentOutput?.uid != speakers.uid
        // Only move the mic if the current input is unresolved (its device left).
        // A still-present third mic (a USB interface, a desk mic) is left alone.
        let micTarget = audio.currentInput == nil ? audio.builtInInput?.uid : nil
        guard needOutput || micTarget != nil else { return }

        // Name the offer after what actually moves - don't say "speakers" when
        // only the mic is changing.
        let confirmName = needOutput ? speakers.name : (audio.builtInInput?.name ?? speakers.name)
        offer(Suggestion(
            moment: moment,
            title: needOutput ? Copy.speakersTitle : Copy.micTitle,
            actionLabel: needOutput ? Copy.speakersAction : Copy.micAction,
            dismissLabel: Copy.speakersDismiss,
            confirmName: confirmName,
            targetOutputUID: needOutput ? speakers.uid : nil,
            targetInputUID: micTarget,
            showAlways: prefs.offers(moment) > 0
        ))
    }

    /// Route a fresh suggestion through the ask / always / never gate.
    private func offer(_ suggestion: Suggestion) {
        switch prefs.policy(suggestion.moment) {
        case .never:
            return
        case .always:
            perform(suggestion, silent: true)
        case .ask:
            guard !suppressedThisSession.contains(suggestion.moment) else { return }
            present(suggestion)
        }
    }

    // MARK: - The gentle card

    private func present(_ suggestion: Suggestion) {
        self.suggestion = suggestion
        prefs.recordOffer(suggestion.moment)
        expiry?.cancel()
        expiry = Task { [weak self, lifetime = offerLifetime] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            self?.expire(suggestion.moment)
        }
        Log.moments.info("offering \(suggestion.moment.rawValue, privacy: .public)")
    }

    /// Auto-dismiss of an ignored card: quiet for the session, but not a decline.
    private func expire(_ moment: SmartMoment) {
        guard suggestion?.moment == moment else { return }
        suppressedThisSession.insert(moment)
        suggestion = nil
    }

    // MARK: - The answers (act on the current card; idempotent against double-tap)

    /// "Use headset" / "Switch" - optionally with "Always do this" ticked. The
    /// card vanishing and the row highlight moving are the visual confirmation,
    /// so the explicit path shows no toast (but does announce for VoiceOver).
    func accept(always: Bool) {
        guard let suggestion else { return }
        expiry?.cancel()
        self.suggestion = nil
        if always { prefs.setPolicy(suggestion.moment, .always) }
        perform(suggestion, silent: false)
    }

    /// "Not now" / "Stay" - suppress this launch, and self-disable if declined
    /// enough times.
    func decline() {
        guard let suggestion else { return }
        expiry?.cancel()
        self.suggestion = nil
        suppressedThisSession.insert(suggestion.moment)
        let count = prefs.recordDecline(suggestion.moment)
        if count >= Self.declineLimit {
            prefs.setEnabled(suggestion.moment, false)
            prefs.setPolicy(suggestion.moment, .never)
            Log.moments.info("self-disabled \(suggestion.moment.rawValue, privacy: .public) after \(count) declines")
        }
    }

    // MARK: - Doing it (only claim success that actually happened)

    private func perform(_ suggestion: Suggestion, silent: Bool) {
        let previous = audio.currentRoute
        guard audio.route(outputUID: suggestion.targetOutputUID, inputUID: suggestion.targetInputUID) else {
            // route() is atomic - nothing moved. Don't lie; on the explicit path
            // give a calm, undo-less acknowledgement so the tap isn't swallowed.
            Log.moments.notice("route did not take for \(suggestion.moment.rawValue, privacy: .public)")
            if !silent { presentToast(ToastContent(message: Copy.couldntSwitch, actionLabel: "", action: {})) }
            return
        }
        prefs.resetDeclines(suggestion.moment)
        let applied = audio.currentRoute

        guard silent else {
            Announce.say(Copy.switched(to: suggestion.confirmName))
            return
        }
        presentToast(ToastContent(
            message: Copy.switched(to: suggestion.confirmName),
            actionLabel: Copy.undo,
            action: { [weak audio] in
                // Don't override a deliberate choice the user has since made.
                guard let audio, audio.currentRoute == applied else { return }
                _ = audio.apply(previous)
            }
        ))
    }
}
