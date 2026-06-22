//
//  SmartMomentsTests.swift
//
//  The highest-value logic in the app: the ask / always / never state machine,
//  the undo round-trip (incl. not overriding a later choice), success-gated
//  routing with explicit-failure feedback, and the self-disable rule.

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

    private func makeEngine(_ audio: FakeAudioRouting, _ prefs: Preferences,
                            toast: @escaping @MainActor (ToastContent) -> Void = { _ in }) -> SmartMomentsEngine {
        SmartMomentsEngine(audio: audio, prefs: prefs, presentToast: toast, lidIsOpen: { true }, offerLifetime: .seconds(60))
    }

    @Test func alwaysPolicyRoutesBothToHeadsetSilently() {
        let prefs = ephemeralPreferences()
        prefs.setPolicy(.headsetTogether, .always)
        let (audio, headset) = headsetWorld()
        var toast: ToastContent?
        let sut = makeEngine(audio, prefs) { toast = $0 }

        sut.handle(WorldChange(added: [headset], removed: []))

        #expect(audio.currentOutputUID == "headset")
        #expect(audio.currentInputUID == "headset")
        #expect(sut.suggestion == nil)
        #expect(toast?.actionLabel == Copy.undo)
    }

    @Test func undoRestoresThePreviousRoute() {
        let prefs = ephemeralPreferences()
        prefs.setPolicy(.headsetTogether, .always)
        let (audio, headset) = headsetWorld()
        var toast: ToastContent?
        let sut = makeEngine(audio, prefs) { toast = $0 }

        sut.handle(WorldChange(added: [headset], removed: []))
        #expect(audio.currentOutputUID == "headset")
        toast?.action()

        #expect(audio.currentOutputUID == "speakers")
        #expect(audio.currentInputUID == "macmic")
    }

    @Test func undoIsANoOpAfterTheUserMovesOn() {
        let prefs = ephemeralPreferences()
        prefs.setPolicy(.headsetTogether, .always)
        let (audio, headset) = headsetWorld()
        var toast: ToastContent?
        let sut = makeEngine(audio, prefs) { toast = $0 }

        sut.handle(WorldChange(added: [headset], removed: []))
        audio.route(outputUID: "speakers", inputUID: nil)   // user deliberately moves on
        toast?.action()                                     // stale Undo

        #expect(audio.currentOutputUID == "speakers")       // not reverted past the user's choice
    }

    @Test func askPolicyPresentsACardAndChangesNothing() {
        let prefs = ephemeralPreferences()
        let (audio, headset) = headsetWorld()
        let sut = makeEngine(audio, prefs)

        sut.handle(WorldChange(added: [headset], removed: []))

        #expect(sut.suggestion?.moment == .headsetTogether)
        #expect(audio.routeCalls.isEmpty)
    }

    @Test func acceptRoutesAndIsIdempotent() {
        let prefs = ephemeralPreferences()
        let (audio, headset) = headsetWorld()
        let sut = makeEngine(audio, prefs)
        sut.handle(WorldChange(added: [headset], removed: []))

        sut.accept(always: false)
        sut.accept(always: false)   // double-tap: no-op, card already gone

        #expect(audio.currentOutputUID == "headset")
        #expect(audio.routeCalls.count == 1)
    }

    @Test func failedRouteClaimsNoSuccess() {
        let prefs = ephemeralPreferences()
        prefs.setPolicy(.headsetTogether, .always)
        let (audio, headset) = headsetWorld()
        audio.routeFails = true
        var toast: ToastContent?
        let sut = makeEngine(audio, prefs) { toast = $0 }

        sut.handle(WorldChange(added: [headset], removed: []))

        #expect(toast == nil)
        #expect(audio.currentOutputUID == "speakers")
    }

    @Test func explicitAcceptFailureGivesFeedback() {
        let prefs = ephemeralPreferences()
        let (audio, headset) = headsetWorld()
        var toast: ToastContent?
        let sut = makeEngine(audio, prefs) { toast = $0 }
        sut.handle(WorldChange(added: [headset], removed: []))

        audio.routeFails = true
        sut.accept(always: false)

        #expect(toast?.message == Copy.couldntSwitch)
        #expect(toast?.actionLabel == "")   // no undo on a no-op
    }

    @Test func threeDeclinesAcrossSessionsSelfDisable() {
        let prefs = ephemeralPreferences()
        for round in 1...3 {
            let (audio, headset) = headsetWorld()
            let sut = makeEngine(audio, prefs)   // fresh session each time
            sut.handle(WorldChange(added: [headset], removed: []))
            #expect(sut.suggestion != nil)
            sut.decline()
            if round < 3 { #expect(prefs.isEnabled(.headsetTogether) == true) }
        }
        #expect(prefs.isEnabled(.headsetTogether) == false)
        #expect(prefs.policy(.headsetTogether) == .never)
    }

    @Test func firstEncounterHidesAlwaysSecondShowsIt() {
        let prefs = ephemeralPreferences()
        let (audio1, headset1) = headsetWorld()
        let sut1 = makeEngine(audio1, prefs)
        sut1.handle(WorldChange(added: [headset1], removed: []))
        #expect(sut1.suggestion?.showAlways == false)
        sut1.decline()

        let (audio2, headset2) = headsetWorld()
        let sut2 = makeEngine(audio2, prefs)
        sut2.handle(WorldChange(added: [headset2], removed: []))
        #expect(sut2.suggestion?.showAlways == true)
    }

    @Test func backToSpeakersLeavesAStillValidMicAlone() {
        let prefs = ephemeralPreferences()
        prefs.setPolicy(.backToSpeakers, .always)
        let audio = FakeAudioRouting()
        audio.outputs = [makeSnapshot("speakers", .builtInSpeakers, out: true)]
        audio.inputs = [makeSnapshot("macmic", .builtInMic, inp: true), makeSnapshot("usbmic", .external, inp: true)]
        audio.builtInOutput = audio.outputs[0]
        audio.builtInInput = audio.inputs[0]
        audio.currentOutputUID = "gone-headset-output"
        audio.currentInputUID = "usbmic"
        let sut = makeEngine(audio, prefs)

        sut.handle(WorldChange(added: [], removed: [makeSnapshot("headset", .headphones, out: true, inp: true)]))

        #expect(audio.routeCalls.last?.out == "speakers")
        #expect(audio.routeCalls.last?.inp == nil)
    }
}
