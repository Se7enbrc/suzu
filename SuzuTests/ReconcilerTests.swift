//
//  ReconcilerTests.swift
//
//  The pure reconciliation that used to be locked inside AudioController: the
//  baseline-then-diff, the synthesize-current-default rule, the menu-bar glyph
//  hold, the "right now" collapse, and twin disambiguation.

import Testing
@testable import Suzu

@MainActor
struct ReconcilerTests {
    private let speakers = { makeSnapshot("speakers", .builtInSpeakers, out: true) }()
    private let headset = { makeSnapshot("headset", .headphones, out: true, inp: true) }()

    @Test func baselineEmitsNoWorldChange() {
        let result = DeviceReconciler.reconcile(
            realSnapshots: [speakers], outputFallback: nil, inputFallback: nil,
            previousKnownByUID: [:], emitChanges: false
        )
        #expect(result.worldChange == nil)
        #expect(result.outputs.map(\.uid) == ["speakers"])
    }

    @Test func aPostBaselineArrivalEmitsAdded() {
        let result = DeviceReconciler.reconcile(
            realSnapshots: [speakers, headset], outputFallback: nil, inputFallback: nil,
            previousKnownByUID: ["speakers": speakers], emitChanges: true
        )
        #expect(result.worldChange?.added.map(\.uid) == ["headset"])
        #expect(result.worldChange?.removed.isEmpty == true)
    }

    @Test func aDepartureEmitsRemoved() {
        let result = DeviceReconciler.reconcile(
            realSnapshots: [speakers], outputFallback: nil, inputFallback: nil,
            previousKnownByUID: ["speakers": speakers, "headset": headset], emitChanges: true
        )
        #expect(result.worldChange?.removed.map(\.uid) == ["headset"])
    }

    @Test func aggregateDefaultRendersButNeverCountsAsAnArrival() {
        let aggregate = makeSnapshot("aggregate", .external, out: true)
        let result = DeviceReconciler.reconcile(
            realSnapshots: [speakers], outputFallback: aggregate, inputFallback: nil,
            previousKnownByUID: ["speakers": speakers], emitChanges: true
        )
        #expect(result.outputs.contains { $0.uid == "aggregate" })   // resolves, not "None"
        #expect(result.worldChange == nil)                           // never an arrival
        #expect(result.nowByUID["aggregate"] == nil)
    }

    @Test func menuBarGlyphHoldsLastThroughATransientMiss() {
        #expect(DeviceReconciler.menuBarSymbol(currentOutput: nil, currentOutputUID: "x", lastSymbol: "headphones") == "headphones")
        #expect(DeviceReconciler.menuBarSymbol(currentOutput: nil, currentOutputUID: nil, lastSymbol: "headphones") == "speaker.slash")
        #expect(DeviceReconciler.menuBarSymbol(currentOutput: speakers, currentOutputUID: "speakers", lastSymbol: "x") == "speaker.wave.2.fill")
    }

    @Test func rightNowCollapsesOnlyWhenSameDevice() {
        let mic = makeSnapshot("macmic", .builtInMic, inp: true)
        let together = DeviceReconciler.rightNow(currentOutput: headset, currentInput: headset)
        #expect(together.secondary == nil)
        #expect(together.primary == Copy.soundAndMic("headset"))

        let split = DeviceReconciler.rightNow(currentOutput: speakers, currentInput: mic)
        #expect(split.primary == Copy.sound("speakers"))
        #expect(split.secondary == Copy.mic("macmic"))
    }

    @Test func twinsAreDisambiguated() {
        // Same friendly name, different UIDs.
        let twinA = DeviceSnapshot(id: 0, uid: "uidA", name: "AirPods Pro", kind: .headphones, hasInput: false, hasOutput: true)
        let twinB = DeviceSnapshot(id: 0, uid: "uidB", name: "AirPods Pro", kind: .headphones, hasInput: false, hasOutput: true)
        let out = DeviceReconciler.disambiguate([twinA, twinB]).map(\.name).sorted()
        #expect(out == ["AirPods Pro (1)", "AirPods Pro (2)"])
    }
}
