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
        // A device you've used before reconnecting wins - restore it (this also
        // covers a remembered headset, for both sound and mic at once).
        if let returning = change.added.first(where: { prefs.isPreferredOutput($0.uid) || prefs.isPreferredInput($0.uid) }),
           considerFavorite(returning) {
            return
        }
        // A new headset arriving (sound + mic) is the next headline moment.
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

    /// A remembered device reconnected. Restore it for whichever role(s) it's
    /// preferred in and isn't already current - both at once for a headset.
    /// Returns whether it handled the device (so the caller stops here).
    private func considerFavorite(_ device: DeviceSnapshot) -> Bool {
        let moment = SmartMoment.favoriteReturned
        guard prefs.isEnabled(moment) else { return false }

        let outUID = (device.hasOutput && prefs.isPreferredOutput(device.uid) && audio.currentOutput?.uid != device.uid) ? device.uid : nil
        let inUID = (device.hasInput && prefs.isPreferredInput(device.uid) && audio.currentInput?.uid != device.uid) ? device.uid : nil
        guard outUID != nil || inUID != nil else { return false }

        offer(Suggestion(
            moment: moment,
            title: Copy.favoriteTitle(device.name),
            actionLabel: Copy.favoriteAction,
            dismissLabel: Copy.headsetDismiss,
            confirmName: device.name,
            targetOutputUID: outUID,
            targetInputUID: inUID,
            showAlways: true
        ))
        return true
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

        let outTarget = landingOutput()
        // Only move the mic if the current input is unresolved (its device left).
        // A still-present third mic (a USB interface, a desk mic) is left alone.
        let inTarget = audio.currentInput == nil ? landingInput() : nil
        guard outTarget != nil || inTarget != nil else { return }

        // Name the offer after what actually moves: the Mac's own speakers/mic
        // keep the familiar "back to your Mac" wording; a remembered device that's
        // still here is phrased like a returning favourite.
        let title: String, action: String, confirmName: String
        if let outTarget {
            let onMac = outTarget.uid == audio.builtInOutput?.uid
            confirmName = outTarget.name
            title = onMac ? Copy.speakersTitle : Copy.favoriteTitle(outTarget.name)
            action = onMac ? Copy.speakersAction : Copy.favoriteAction
        } else if let inTarget {
            let onMac = inTarget.uid == audio.builtInInput?.uid
            confirmName = inTarget.name
            title = onMac ? Copy.micTitle : Copy.favoriteTitle(inTarget.name)
            action = onMac ? Copy.micAction : Copy.favoriteAction
        } else {
            return
        }

        offer(Suggestion(
            moment: moment,
            title: title,
            actionLabel: action,
            dismissLabel: Copy.speakersDismiss,
            confirmName: confirmName,
            targetOutputUID: outTarget?.uid,
            targetInputUID: inTarget?.uid,
            showAlways: true
        ))
    }

    /// Where sound should land when the current output device leaves. Lean on
    /// remembered presence: a device you deliberately chose before that's still
    /// connected (most recent first) beats the bare Mac. The Mac's own speakers
    /// are the last resort - and never offered while clamshell-docked (lid shut),
    /// where they're muffled and you plainly have an external setup suzu just
    /// doesn't remember yet. Returns nil when you're already somewhere sensible.
    private func landingOutput() -> DeviceSnapshot? {
        // Already on your Mac, or a device you've chosen before? Leave it be.
        if let current = audio.currentOutput,
           current.uid == audio.builtInOutput?.uid || prefs.isPreferredOutput(current.uid) {
            return nil
        }
        let builtIn = audio.builtInOutput?.uid
        for uid in prefs.preferredOutputs where uid != builtIn {
            if let dev = audio.outputs.first(where: { $0.uid == uid }) { return dev }
        }
        if lidIsOpen() != false { return audio.builtInOutput }
        return nil
    }

    /// Where the mic should land when its device leaves: a remembered input that's
    /// still here, else the Mac's own mic (which a closed lid never muffles).
    private func landingInput() -> DeviceSnapshot? {
        let builtIn = audio.builtInInput?.uid
        for uid in prefs.preferredInputs where uid != builtIn {
            if let dev = audio.inputs.first(where: { $0.uid == uid }) { return dev }
        }
        return audio.builtInInput
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
            // An explicit acceptance is a deliberate choice - remember it.
            if let uid = suggestion.targetOutputUID { prefs.recordPreferredOutput(uid) }
            if let uid = suggestion.targetInputUID { prefs.recordPreferredInput(uid) }
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
