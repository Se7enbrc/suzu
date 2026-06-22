//
//  DeviceReconciler.swift
//
//  The pure heart of AudioController, pulled out so it can be unit-tested
//  without CoreAudio. Given value-typed snapshots and the current defaults, it
//  produces the output/input lists (with the current default always
//  resolvable), the added/removed world diff, the menu-bar glyph, and the
//  "right now" lines. No live devices, no side effects.

enum DeviceReconciler {
    struct Result {
        var outputs: [DeviceSnapshot]
        var inputs: [DeviceSnapshot]
        var nowByUID: [String: DeviceSnapshot]
        var worldChange: WorldChange?
    }

    /// `realSnapshots` are the non-aggregate/virtual devices. `outputFallback` /
    /// `inputFallback` are the synthesized snapshot of the live default when it
    /// isn't a real device (an aggregate/multi-output), so it never reads as
    /// "None" while never appearing in the Smart Moments diff.
    static func reconcile(
        realSnapshots: [DeviceSnapshot],
        outputFallback: DeviceSnapshot?,
        inputFallback: DeviceSnapshot?,
        previousKnownByUID: [String: DeviceSnapshot],
        emitChanges: Bool
    ) -> Result {
        var outs = realSnapshots.filter(\.hasOutput)
        var ins = realSnapshots.filter(\.hasInput)
        if let outputFallback, !outs.contains(where: { $0.uid == outputFallback.uid }) { outs.append(outputFallback) }
        if let inputFallback, !ins.contains(where: { $0.uid == inputFallback.uid }) { ins.append(inputFallback) }
        outs = disambiguate(outs)
        ins = disambiguate(ins)

        let nowByUID = Dictionary(realSnapshots.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        var worldChange: WorldChange?
        if emitChanges {
            let added = Set(nowByUID.keys).subtracting(previousKnownByUID.keys).compactMap { nowByUID[$0] }
            let removed = Set(previousKnownByUID.keys).subtracting(nowByUID.keys).compactMap { previousKnownByUID[$0] }
            if !(added.isEmpty && removed.isEmpty) { worldChange = WorldChange(added: added, removed: removed) }
        }
        return Result(outputs: outs, inputs: ins, nowByUID: nowByUID, worldChange: worldChange)
    }

    /// When two devices share a friendly name (a pair of identical AirPods, two
    /// of the same interface), append "(2)", "(3)" by stable UID order so rows
    /// and confirmations are distinguishable. Untouched in the common case.
    static func disambiguate(_ snaps: [DeviceSnapshot]) -> [DeviceSnapshot] {
        let counts = Dictionary(grouping: snaps, by: \.name).filter { $0.value.count > 1 }
        guard !counts.isEmpty else { return snaps }
        var ordinal: [String: Int] = [:]
        for (_, group) in counts {
            for (index, snap) in group.sorted(by: { $0.uid < $1.uid }).enumerated() {
                ordinal[snap.uid] = index + 1
            }
        }
        return snaps.map { snap in
            guard let nth = ordinal[snap.uid] else { return snap }
            return DeviceSnapshot(
                id: snap.id, uid: snap.uid, name: "\(snap.name) (\(nth))",
                kind: snap.kind, hasInput: snap.hasInput, hasOutput: snap.hasOutput
            )
        }
    }

    /// The menu-bar glyph. Holds the last known glyph through a transient lookup
    /// miss; the slash only for a genuinely absent default output.
    static func menuBarSymbol(currentOutput: DeviceSnapshot?, currentOutputUID: String?, lastSymbol: String) -> String {
        if let currentOutput { return currentOutput.kind.symbol }
        return currentOutputUID == nil ? "speaker.slash" : lastSymbol
    }

    static func rightNow(currentOutput: DeviceSnapshot?, currentInput: DeviceSnapshot?) -> RightNow {
        if let out = currentOutput, let mic = currentInput, out.uid == mic.uid {
            return RightNow(primary: Copy.soundAndMic(out.name), secondary: nil)
        }
        return RightNow(
            primary: Copy.sound(currentOutput?.name ?? Copy.nowhere),
            secondary: Copy.mic(currentInput?.name ?? Copy.nowhere)
        )
    }
}
