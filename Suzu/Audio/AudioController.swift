//
//  AudioController.swift
//
//  The one place that talks to CoreAudio (through SimplyCoreAudio). It keeps a
//  live, value-typed picture of the output/input devices and which are current,
//  refreshing when anything changes. Everything above it works with
//  `DeviceSnapshot` values, never the live device objects.
//
//  Concurrency: MainActor-isolated. CoreAudio posts notifications off the main
//  thread, so the observer block only schedules a refresh back on the main
//  actor. Refreshes are debounced so one physical event (which can fire two or
//  three notifications) does one HAL sweep, and self-initiated changes refresh
//  without feeding Smart Moments.

import CoreAudio
import Foundation
import Observation
import SimplyCoreAudio

@MainActor
@Observable
final class AudioController: AudioRouting {
    private(set) var outputs: [DeviceSnapshot] = []
    private(set) var inputs: [DeviceSnapshot] = []
    private(set) var currentOutputUID: String?
    private(set) var currentInputUID: String?

    /// Called after a refresh driven by an external change (device added/removed
    /// or a default we didn't set), never for our own routing or the baseline.
    @ObservationIgnored var onWorldChanged: ((WorldChange) -> Void)?

    @ObservationIgnored private let coreAudio = SimplyCoreAudio()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var knownByUID: [String: DeviceSnapshot] = [:]
    @ObservationIgnored private var didBaseline = false
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var lastOutputSymbol = "speaker.wave.2.fill"

    // MARK: - Lifecycle

    func start() {
        refresh(emitChange: false)
        subscribe(.deviceListChanged)
        subscribe(.defaultOutputDeviceChanged)
        subscribe(.defaultInputDeviceChanged)
        Log.audio.info("ready: \(self.outputs.count, privacy: .public) outputs, \(self.inputs.count, privacy: .public) inputs")
    }

    private func subscribe(_ name: Notification.Name) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
            // Delivered off-main by SimplyCoreAudio; coalesce on the main actor.
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
        observers.append(token)
    }

    /// Collapse a burst of notifications (one physical plug event can fire
    /// several) into a single trailing refresh.
    private func scheduleRefresh() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: - Snapshot

    func refresh(emitChange: Bool = true) {
        let realDevices = coreAudio.allDevices.filter { isReal($0) }
        let realSnaps = realDevices.compactMap(snapshot(for:))

        currentOutputUID = coreAudio.defaultOutputDevice?.uid
        currentInputUID = coreAudio.defaultInputDevice?.uid

        var outs = realSnaps.filter(\.hasOutput)
        var ins = realSnaps.filter(\.hasInput)
        // The system default can legitimately be an aggregate/multi-output. Never
        // render it as "nowhere": synthesize a snapshot for it so it resolves.
        if let uid = currentOutputUID, !outs.contains(where: { $0.uid == uid }),
           let device = coreAudio.defaultOutputDevice, let snap = snapshot(for: device) {
            outs.append(snap)
        }
        if let uid = currentInputUID, !ins.contains(where: { $0.uid == uid }),
           let device = coreAudio.defaultInputDevice, let snap = snapshot(for: device) {
            ins.append(snap)
        }
        outputs = outs
        inputs = ins
        if let symbol = currentOutput?.kind.symbol { lastOutputSymbol = symbol }

        // Smart Moments see only real devices, so an aggregate becoming default
        // never reads as an arrival.
        let nowByUID = Dictionary(realSnaps.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        defer {
            knownByUID = nowByUID
            didBaseline = true
        }
        guard emitChange, didBaseline else { return }
        let added = Set(nowByUID.keys).subtracting(knownByUID.keys).compactMap { nowByUID[$0] }
        let removed = Set(knownByUID.keys).subtracting(nowByUID.keys).compactMap { knownByUID[$0] }
        if added.isEmpty && removed.isEmpty { return }
        onWorldChanged?(WorldChange(added: added, removed: removed))
    }

    private func isReal(_ device: AudioDevice) -> Bool {
        switch device.transportType ?? .unknown {
        case .aggregate, .virtual: return false
        default: return true
        }
    }

    private func snapshot(for device: AudioDevice) -> DeviceSnapshot? {
        guard let uid = device.uid else { return nil }
        // Presence by stream existence - avoids a physicalFormat HAL round-trip.
        let hasOutput = device.streams(scope: .output)?.isEmpty == false
        let hasInput = device.streams(scope: .input)?.isEmpty == false
        guard hasOutput || hasInput else { return nil }

        let transport = device.transportType
        return DeviceSnapshot(
            id: device.id,
            uid: uid,
            name: DeviceNaming.friendly(rawName: device.name, transport: transport),
            kind: DeviceKind.classify(transport: transport, hasInput: hasInput, hasOutput: hasOutput, name: device.name),
            hasInput: hasInput,
            hasOutput: hasOutput
        )
    }

    // MARK: - Derived

    var currentOutput: DeviceSnapshot? { outputs.first { $0.uid == currentOutputUID } }
    var currentInput: DeviceSnapshot? { inputs.first { $0.uid == currentInputUID } }
    var builtInOutput: DeviceSnapshot? { outputs.first { $0.kind == .builtInSpeakers } }
    var builtInInput: DeviceSnapshot? { inputs.first { $0.kind == .builtInMic } }

    /// The menu-bar glyph mirrors the current output. Holds the last known glyph
    /// through a transient lookup miss (the instant during an unplug) so it never
    /// flashes "speaker.slash" while a new default is still settling.
    var menuBarSymbol: String {
        if let output = currentOutput { return output.kind.symbol }
        return currentOutputUID == nil ? "speaker.slash" : lastOutputSymbol
    }

    var rightNow: RightNow {
        let out = currentOutput
        let mic = currentInput
        if let out, let mic, out.uid == mic.uid {
            return RightNow(primary: Copy.soundAndMic(out.name), secondary: nil)
        }
        return RightNow(
            primary: Copy.sound(out?.name ?? Copy.nowhere),
            secondary: Copy.mic(mic?.name ?? Copy.nowhere)
        )
    }

    var currentRoute: Route { Route(outputUID: currentOutputUID, inputUID: currentInputUID) }

    struct RightNow: Equatable {
        var primary: String
        var secondary: String?
    }

    // MARK: - Actions

    func selectOutput(_ uid: String) { _ = route(outputUID: uid, inputUID: nil) }
    func selectInput(_ uid: String) { _ = route(outputUID: nil, inputUID: uid) }

    /// Sets either default (or both) by UID and reports whether it actually took.
    /// We only ever touch the main output and main input - never the
    /// system-sounds output, so alert dings stay put. Self-initiated, so the
    /// follow-up refresh does not feed Smart Moments.
    @discardableResult
    func route(outputUID: String?, inputUID: String?) -> Bool {
        var ok = true
        if let outputUID {
            if let device = AudioDevice.lookup(by: outputUID) {
                device.isDefaultOutputDevice = true
                ok = ok && coreAudio.defaultOutputDevice?.uid == outputUID
            } else {
                ok = false
            }
        }
        if let inputUID {
            if let device = AudioDevice.lookup(by: inputUID) {
                device.isDefaultInputDevice = true
                ok = ok && coreAudio.defaultInputDevice?.uid == inputUID
            } else {
                ok = false
            }
        }
        refresh(emitChange: false)
        return ok
    }
}
