//
//  SmartMomentsEngine.swift
//
//  The "good instincts, good memory" layer. It watches device arrivals and
//  departures and, for each Smart Moment, follows one pattern:
//
//    • first time            → set a gentle, dismissible suggestion (the menu
//                              shows it as a card; the menu-bar icon hints)
//    • she said "always"     → just do it, with a momentary undo toast
//    • she said "no thanks"  → stay quiet
//
//  A suggestion she ignores expires on its own and won't return this launch.
//  Three explicit declines quietly switch the moment off in Settings.

import CoreAudio
import Foundation
import Observation

/// A single, dismissible offer shown in the menu. Only one exists at a time.
struct Suggestion: Identifiable, Equatable {
    let moment: SmartMoment
    let title: String
    let actionLabel: String
    let dismissLabel: String
    let confirmName: String
    let targetOutputID: AudioObjectID?
    let targetInputID: AudioObjectID?

    var id: SmartMoment { moment }
}

@MainActor
@Observable
final class SmartMomentsEngine {
    /// The card the menu should show, if any.
    var suggestion: Suggestion?

    @ObservationIgnored private let audio: AudioController
    @ObservationIgnored private let prefs: Preferences

    /// Moments ignored this launch - don't re-offer until next launch.
    @ObservationIgnored private var suppressedThisSession: Set<SmartMoment> = []
    @ObservationIgnored private var expiry: Task<Void, Never>?

    private static let declineLimit = 3
    private static let offerLifetime: Duration = .seconds(20)

    init(audio: AudioController, prefs: Preferences) {
        self.audio = audio
        self.prefs = prefs
    }

    var hasPendingSuggestion: Bool { suggestion != nil }

    // MARK: - Reacting to the world

    func handle(_ change: AudioController.WorldChange) {
        // A headset arriving is the headline moment; it wins over the others.
        if let headset = change.added.first(where: { $0.hasInput && $0.hasOutput }) {
            considerHeadset(headset)
            return
        }
        if !change.removed.isEmpty {
            considerBackToSpeakers()
        }
    }

    private func considerHeadset(_ headset: DeviceSnapshot) {
        let moment = SmartMoment.headsetTogether
        guard prefs.isEnabled(moment) else { return }
        // Already fully on the headset - nothing to offer.
        if audio.currentOutputID == headset.id, audio.currentInputID == headset.id { return }

        let suggestion = Suggestion(
            moment: moment,
            title: Copy.headsetTitle,
            actionLabel: Copy.headsetAction,
            dismissLabel: Copy.headsetDismiss,
            confirmName: headset.name,
            targetOutputID: headset.id,
            targetInputID: headset.id
        )
        offer(suggestion)
    }

    private func considerBackToSpeakers() {
        let moment = SmartMoment.backToSpeakers
        guard prefs.isEnabled(moment) else { return }
        // Need the Mac's own speakers to exist...
        guard let speakers = audio.builtInOutput else { return }
        // ...and don't offer them while docked with the lid shut.
        if LidSensor.isLidOpen == false { return }

        let mic = audio.builtInInput
        let alreadyHome = audio.currentOutputID == speakers.id
            && (mic == nil || audio.currentInputID == mic?.id)
        if alreadyHome { return }

        let suggestion = Suggestion(
            moment: moment,
            title: Copy.speakersTitle,
            actionLabel: Copy.speakersAction,
            dismissLabel: Copy.speakersDismiss,
            confirmName: speakers.name,
            targetOutputID: speakers.id,
            targetInputID: mic?.id
        )
        offer(suggestion)
    }

    /// Route a fresh suggestion through the ask / always / never gate.
    private func offer(_ suggestion: Suggestion) {
        switch prefs.policy(suggestion.moment) {
        case .never:
            return
        case .always:
            perform(suggestion)
        case .ask:
            guard !suppressedThisSession.contains(suggestion.moment) else { return }
            present(suggestion)
        }
    }

    // MARK: - The gentle card

    private func present(_ suggestion: Suggestion) {
        self.suggestion = suggestion
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: Self.offerLifetime)
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

    // MARK: - Her answers

    /// "Use headset" / "Switch" - optionally with "Always do this" ticked.
    func accept(_ suggestion: Suggestion, always: Bool) {
        expiry?.cancel()
        self.suggestion = nil
        if always { prefs.setPolicy(suggestion.moment, .always) }
        prefs.resetDeclines(suggestion.moment)
        perform(suggestion)
    }

    /// "Not now" / "Stay" - suppress this launch, and self-disable if she's said
    /// no enough times.
    func decline(_ suggestion: Suggestion) {
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

    // MARK: - Doing it (with undo)

    private func perform(_ suggestion: Suggestion) {
        let previous = audio.currentRoute
        audio.route(outputID: suggestion.targetOutputID, inputID: suggestion.targetInputID)
        ToastPresenter.shared.show(ToastContent(
            message: Copy.switched(to: suggestion.confirmName),
            actionLabel: Copy.undo,
            action: { [weak audio] in audio?.apply(previous) }
        ))
    }
}
