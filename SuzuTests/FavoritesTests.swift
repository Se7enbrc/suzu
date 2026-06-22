//
//  FavoritesTests.swift
//
//  Preferred-device memory: remembering deliberate choices and restoring a
//  remembered device when it reconnects (ask once, then automatic) - including
//  a both-capable device for sound and mic at once.

import Testing
@testable import Suzu

@MainActor
struct FavoritesTests {
    private func engine(_ audio: FakeAudioRouting, _ prefs: Preferences,
                        toast: @escaping @MainActor (ToastContent) -> Void = { _ in }) -> SmartMomentsEngine {
        SmartMomentsEngine(audio: audio, prefs: prefs, presentToast: toast, lidIsOpen: { true }, offerLifetime: .seconds(60))
    }

    private func onBuiltIn() -> FakeAudioRouting {
        let audio = FakeAudioRouting()
        audio.outputs = [makeSnapshot("speakers", .builtInSpeakers, out: true)]
        audio.inputs = [makeSnapshot("macmic", .builtInMic, inp: true)]
        audio.builtInOutput = audio.outputs[0]
        audio.builtInInput = audio.inputs[0]
        audio.currentOutputUID = "speakers"
        audio.currentInputUID = "macmic"
        return audio
    }

    @Test func reconnectingRememberedOutputAsksToRestore() {
        let prefs = ephemeralPreferences()
        prefs.recordPreferredOutput("dock")
        let audio = onBuiltIn()
        let sut = engine(audio, prefs)

        sut.handle(WorldChange(added: [makeSnapshot("dock", .external, out: true)], removed: []))

        #expect(sut.suggestion?.moment == .favoriteReturned)
        #expect(sut.suggestion?.targetOutputUID == "dock")
        #expect(audio.routeCalls.isEmpty)   // asked, not yet switched
    }

    @Test func reconnectingRememberedOutputRestoresSilentlyWhenAlways() {
        let prefs = ephemeralPreferences()
        prefs.recordPreferredOutput("dock")
        prefs.setPolicy(.favoriteReturned, .always)
        let audio = onBuiltIn()
        var toast: ToastContent?
        let sut = engine(audio, prefs) { toast = $0 }

        sut.handle(WorldChange(added: [makeSnapshot("dock", .external, out: true)], removed: []))

        #expect(audio.currentOutputUID == "dock")
        #expect(audio.currentInputUID == "macmic")   // input untouched
        #expect(toast?.actionLabel == Copy.undo)
    }

    @Test func aRememberedHeadsetIsRestoredForBothSoundAndMic() {
        let prefs = ephemeralPreferences()
        prefs.recordPreferredOutput("buds")
        prefs.recordPreferredInput("buds")
        prefs.setPolicy(.favoriteReturned, .always)
        let audio = onBuiltIn()
        let sut = engine(audio, prefs)

        sut.handle(WorldChange(added: [makeSnapshot("buds", .headphones, out: true, inp: true)], removed: []))

        #expect(audio.currentOutputUID == "buds")
        #expect(audio.currentInputUID == "buds")
    }

    @Test func aRememberedDeviceWinsOverTheNewHeadsetOffer() {
        let prefs = ephemeralPreferences()
        prefs.recordPreferredOutput("buds")
        prefs.recordPreferredInput("buds")
        prefs.setPolicy(.favoriteReturned, .always)
        let audio = onBuiltIn()
        let sut = engine(audio, prefs)

        sut.handle(WorldChange(added: [makeSnapshot("buds", .headphones, out: true, inp: true)], removed: []))

        #expect(sut.suggestion == nil)               // restored silently...
        #expect(audio.currentOutputUID == "buds")    // ...not offered as a new headset
    }

    @Test func anExplicitAcceptRemembersTheDevice() {
        let prefs = ephemeralPreferences()
        let audio = onBuiltIn()
        audio.outputs.append(makeSnapshot("headset", .headphones, out: true, inp: true))
        audio.inputs.append(makeSnapshot("headset", .headphones, out: true, inp: true))
        let sut = engine(audio, prefs)
        sut.handle(WorldChange(added: [makeSnapshot("headset", .headphones, out: true, inp: true)], removed: []))

        sut.accept(always: false)

        #expect(prefs.isPreferredOutput("headset"))
        #expect(prefs.isPreferredInput("headset"))
    }

    @Test func aSilentAutomaticSwitchDoesNotRecordAPreference() {
        let prefs = ephemeralPreferences()
        prefs.setPolicy(.headsetTogether, .always)
        let audio = onBuiltIn()
        let sut = engine(audio, prefs)

        sut.handle(WorldChange(added: [makeSnapshot("headset", .headphones, out: true, inp: true)], removed: []))

        #expect(audio.currentOutputUID == "headset")           // it switched
        #expect(prefs.isPreferredOutput("headset") == false)   // but didn't auto-remember
    }

    @Test func mostRecentChoiceRanksFirst() {
        let prefs = ephemeralPreferences()
        prefs.recordPreferredOutput("a")
        prefs.recordPreferredOutput("b")
        prefs.recordPreferredOutput("a")
        #expect(prefs.preferredOutputs == ["a", "b"])
    }
}
