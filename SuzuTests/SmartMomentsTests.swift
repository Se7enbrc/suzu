//
//  SmartMomentsTests.swift
//
//  The highest-value logic in the app: the ask / always / never state machine,
//  the undo round-trip, success-gated routing, and the self-disable rule.

import Testing
@testable import Suzu

@MainActor
struct SmartMomentsTests {
    /// Speakers + built-in mic current; a headset available to switch to.
    private func headsetWorld() -> (FakeAudioRouting, DeviceSnapshot) {
        let audio = FakeAudioRouting()
        let speakers = makeSnapshot("speakers", .builtInSpeakers, out: true)
        let mic = makeSnapshot("macmic", .builtInMic, inp: true)
        let headset = makeSnapshot("headset", .headphones, out: true, inp: true)
        audio.outputs = [speakers, headset]
        audio.inputs = [mic, headset]
        audio.builtInOutput = speakers
        audio.builtInInput = mic
        audio.currentOutputUID = "speakers"
        audio.currentInputUID = "macmic"
        return (audio, headset)
    }

    private func engine(_ audio: FakeAudioRouting, _ prefs: Preferences, toast: @escaping @MainActor (ToastContent) -> Void = { _ in }) -> SmartMomentsEngine {
        SmartMomentsEngine(audio: audio, prefs: prefs, presentToast: toast, lidIsOpen: { true }, offerLifetime: .seconds(60))
    }

    @Test func alwaysPolicyRoutesBothToHeadsetSilently() {
        let prefs = ephemeralPreferences()
        prefs.setPolicy(.headsetTogether, .always)
        let (audio, headset) = headsetWorld()
        var toast: ToastContent?
        let sut = engine(audio, prefs) { toast = $0 }

        sut.handle(WorldChange(added: [headset], removed: []))

        #expect(audio.currentOutputUID == "headset")
        #expect(audio.currentInputUID == "headset")
        #expect(sut.suggestion == nil)   // silent path - no card
        #expect(toast != nil)            // ...but a momentary undo note
    }

    @Test func undoRestoresThePreviousRoute() {
        let prefs = ephemeralPreferences()
        prefs.setPolicy(.headsetTogether, .always)
        let (audio, headset) = headsetWorld()
        var toast: ToastContent?
        let sut = engine(audio, prefs) { toast = $0 }

        sut.handle(WorldChange(added: [headset], removed: []))
        #expect(audio.currentOutputUID == "headset")

        toast?.action()   // Undo

        #expect(audio.currentOutputUID == "speakers")
        #expect(audio.currentInputUID == "macmic")
    }

    @Test func askPolicyPresentsACardAndChangesNothing() {
        let prefs = ephemeralPreferences()   // defaults to .ask
        let (audio, headset) = headsetWorld()
        let sut = engine(audio, prefs)

        sut.handle(WorldChange(added: [headset], removed: []))

        #expect(sut.suggestion?.moment == .headsetTogether)
        #expect(audio.routeCalls.isEmpty)
    }

    @Test func firstEncounterHidesAlwaysSecondShowsIt() {
        let prefs = ephemeralPreferences()
        let (audio, headset) = headsetWorld()
        let sut = engine(audio, prefs)

        sut.handle(WorldChange(added: [headset], removed: []))
        #expect(sut.suggestion?.showAlways == false)

        // A new session: dismiss this one, offer again.
        if let first = sut.suggestion { sut.decline(first) }
        let prefs2Audio = headsetWorld()
        let sut2 = SmartMomentsEngine(audio: prefs2Audio.0, prefs: prefs, presentToast: { _ in }, lidIsOpen: { true })
        sut2.handle(WorldChange(added: [prefs2Audio.1], removed: []))
        #expect(sut2.suggestion?.showAlways == true)
    }

    @Test func failedRouteClaimsNoSuccess() {
        let prefs = ephemeralPreferences()
        prefs.setPolicy(.headsetTogether, .always)
        let (audio, headset) = headsetWorld()
        audio.routeFails = true
        var toast: ToastContent?
        let sut = engine(audio, prefs) { toast = $0 }

        sut.handle(WorldChange(added: [headset], removed: []))

        #expect(toast == nil)            // no false confirmation
        #expect(audio.currentOutputUID == "speakers")   // nothing actually moved
    }

    @Test func threeDeclinesSelfDisableTheMoment() {
        let prefs = ephemeralPreferences()
        let (audio, _) = headsetWorld()
        let sut = engine(audio, prefs)
        let suggestion = Suggestion(
            moment: .headsetTogether, title: "", actionLabel: "", dismissLabel: "",
            confirmName: "", targetOutputUID: "headset", targetInputUID: "headset", showAlways: false
        )

        sut.decline(suggestion)
        sut.decline(suggestion)
        #expect(prefs.isEnabled(.headsetTogether) == true)
        sut.decline(suggestion)

        #expect(prefs.isEnabled(.headsetTogether) == false)
        #expect(prefs.policy(.headsetTogether) == .never)
    }

    @Test func backToSpeakersLeavesAStillValidMicAlone() {
        let prefs = ephemeralPreferences()
        prefs.setPolicy(.backToSpeakers, .always)
        let audio = FakeAudioRouting()
        let speakers = makeSnapshot("speakers", .builtInSpeakers, out: true)
        let mic = makeSnapshot("macmic", .builtInMic, inp: true)
        let usbMic = makeSnapshot("usbmic", .external, inp: true)
        audio.outputs = [speakers]
        audio.inputs = [mic, usbMic]
        audio.builtInOutput = speakers
        audio.builtInInput = mic
        audio.currentOutputUID = "gone-headset-output"   // fell back to a non-built-in
        audio.currentInputUID = "usbmic"                 // a third mic, still present
        let sut = engine(audio, prefs)

        sut.handle(WorldChange(added: [], removed: [makeSnapshot("headset", .headphones, out: true, inp: true)]))

        #expect(audio.routeCalls.last?.out == "speakers")
        #expect(audio.routeCalls.last?.inp == nil)       // mic left untouched
    }
}
