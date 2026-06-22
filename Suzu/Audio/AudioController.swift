//
//  AudioController.swift
//
//  The one place that talks to CoreAudio (through SimplyCoreAudio). It builds
//  value-typed snapshots of the devices and hands the pure reconciliation
//  (diff, current-default resolution, glyph, "right now") to DeviceReconciler,
//  which is unit-tested without CoreAudio. Everything above works with
//  `DeviceSnapshot` values, never the live device objects.
//
//  Concurrency: MainActor-isolated. CoreAudio posts notifications off the main
//  thread, so the observer block only schedules a debounced refresh back on the
//  main actor. Self-initiated changes update the current defaults directly and
//  let the one debounced notification do the authoritative sweep.

import AppKit
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
        guard observers.isEmpty else { return }   // idempotent
        refresh(emitChange: false)
        subscribe(.deviceListChanged)
        subscribe(.defaultOutputDeviceChanged)
        subscribe(.defaultInputDeviceChanged)
        // A headset unplugged (or the Mac undocked) during sleep can settle a new
        // default by wake while our snapshot is stale; refresh on wake.
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { _ in Task { @MainActor [weak self] in self?.scheduleRefresh() } }
        observers.append(wake)
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
        var realSnaps: [DeviceSnapshot] = []
        for device in coreAudio.allDevices {
            let transport = device.transportType    // one HAL read per device
            guard isReal(transport) else { continue }
            if let snap = snapshot(for: device, transport: transport) { realSnaps.append(snap) }
        }

        currentOutputUID = coreAudio.defaultOutputDevice?.uid
        currentInputUID = coreAudio.defaultInputDevice?.uid
        let outputFallback = fallbackSnapshot(uid: currentOutputUID, in: realSnaps, device: coreAudio.defaultOutputDevice)
        let inputFallback = fallbackSnapshot(uid: currentInputUID, in: realSnaps, device: coreAudio.defaultInputDevice)

        let result = DeviceReconciler.reconcile(
            realSnapshots: realSnaps,
            outputFallback: outputFallback,
            inputFallback: inputFallback,
            previousKnownByUID: knownByUID,
            emitChanges: emitChange && didBaseline
        )
        outputs = result.outputs
        inputs = result.inputs
        if let symbol = currentOutput?.kind.symbol { lastOutputSymbol = symbol }
        knownByUID = result.nowByUID
        didBaseline = true
        if let change = result.worldChange { onWorldChanged?(change) }
    }

    private func fallbackSnapshot(uid: String?, in snaps: [DeviceSnapshot], device: AudioDevice?) -> DeviceSnapshot? {
        guard let uid, !snaps.contains(where: { $0.uid == uid }), let device else { return nil }
        return snapshot(for: device, transport: device.transportType)
    }

    private func isReal(_ transport: TransportType?) -> Bool {
        switch transport ?? .unknown {
        case .aggregate, .virtual: return false
        default: return true
        }
    }

    private func snapshot(for device: AudioDevice, transport: TransportType?) -> DeviceSnapshot? {
        guard let uid = device.uid else { return nil }
        // Presence by stream existence - avoids a physicalFormat HAL round-trip.
        let hasOutput = device.streams(scope: .output)?.isEmpty == false
        let hasInput = device.streams(scope: .input)?.isEmpty == false
        guard hasOutput || hasInput else { return nil }
        return DeviceSnapshot(
            id: device.id,
            uid: uid,
            name: DeviceNaming.friendly(rawName: device.name, transport: transport, hasOutput: hasOutput),
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

    var menuBarSymbol: String {
        DeviceReconciler.menuBarSymbol(currentOutput: currentOutput, currentOutputUID: currentOutputUID, lastSymbol: lastOutputSymbol)
    }

    var rightNow: RightNow {
        DeviceReconciler.rightNow(currentOutput: currentOutput, currentInput: currentInput)
    }

    var currentRoute: Route { Route(outputUID: currentOutputUID, inputUID: currentInputUID) }

    // MARK: - Actions

    func selectOutput(_ uid: String) {
        if route(outputUID: uid, inputUID: nil), let name = currentOutput?.name {
            Announce.say(Copy.soundOn(name))
        }
    }

    func selectInput(_ uid: String) {
        if route(outputUID: nil, inputUID: uid), let name = currentInput?.name {
            Announce.say(Copy.micOn(name))
        }
    }

    /// Sets either default (or both) by UID, atomically: if any leg fails, the
    /// previous route is restored so the caller's `false` is honest - nothing is
    /// ever left half-applied. We only ever touch the main output and input,
    /// never the system-sounds output, so alert dings stay put.
    @discardableResult
    func route(outputUID: String?, inputUID: String?) -> Bool {
        guard outputUID != nil || inputUID != nil else { return false }
        let previous = currentRoute

        var ok = true
        if let outputUID { ok = setDefaultOutput(outputUID) }
        if ok, let inputUID { ok = setDefaultInput(inputUID) }
        if !ok {
            if let uid = previous.outputUID { _ = setDefaultOutput(uid) }
            if let uid = previous.inputUID { _ = setDefaultInput(uid) }
        }

        // Self-initiated: update the current defaults from the real state (two
        // cheap reads) and skip the full re-enumeration - the resulting CoreAudio
        // notification does the one authoritative debounced sweep.
        currentOutputUID = coreAudio.defaultOutputDevice?.uid
        currentInputUID = coreAudio.defaultInputDevice?.uid
        if let symbol = currentOutput?.kind.symbol { lastOutputSymbol = symbol }
        return ok
    }

    private func setDefaultOutput(_ uid: String) -> Bool {
        guard let device = AudioDevice.lookup(by: uid) else { return false }
        device.isDefaultOutputDevice = true
        return coreAudio.defaultOutputDevice?.uid == uid
    }

    private func setDefaultInput(_ uid: String) -> Bool {
        guard let device = AudioDevice.lookup(by: uid) else { return false }
        device.isDefaultInputDevice = true
        return coreAudio.defaultInputDevice?.uid == uid
    }
}
