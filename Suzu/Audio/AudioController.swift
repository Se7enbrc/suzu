//
//  AudioController.swift
//
//  The one place that talks to CoreAudio (through SimplyCoreAudio). It keeps a
//  live, value-typed picture of the output/input devices and which ones are
//  current, refreshing the instant anything changes (a device plugged in, a
//  default changed by us or by something else). Everything above it works with
//  `DeviceSnapshot` values, never the live device objects.
//
//  Concurrency: MainActor-isolated. CoreAudio posts its notifications off the
//  main thread, so the observer block just hops back onto the main actor before
//  touching any state.

import CoreAudio
import Foundation
import Observation
import SimplyCoreAudio

@MainActor
@Observable
final class AudioController {
    /// What changed between two refreshes, handed to the Smart Moments engine.
    struct WorldChange: Sendable {
        var added: [DeviceSnapshot]
        var removed: [DeviceSnapshot]
    }

    /// A pair of defaults we can capture and re-apply - the basis of "Undo".
    struct Route: Equatable, Sendable {
        var outputID: AudioObjectID?
        var inputID: AudioObjectID?
    }

    /// Two lines (or one) describing where sound and mic are right now.
    struct RightNow: Equatable {
        var primary: String
        var secondary: String?
    }

    private(set) var outputs: [DeviceSnapshot] = []
    private(set) var inputs: [DeviceSnapshot] = []
    private(set) var currentOutputID: AudioObjectID?
    private(set) var currentInputID: AudioObjectID?

    /// Called after every refresh except the first (launch) one, so device
    /// arrivals/departures can drive Smart Moments without re-subscribing.
    @ObservationIgnored var onWorldChanged: ((WorldChange) -> Void)?

    @ObservationIgnored private let coreAudio = SimplyCoreAudio()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var knownByUID: [String: DeviceSnapshot] = [:]
    @ObservationIgnored private var didBaseline = false

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
            // Delivered off-main by SimplyCoreAudio; bounce to the main actor.
            Task { @MainActor [weak self] in self?.refresh() }
        }
        observers.append(token)
    }

    // MARK: - Snapshot

    func refresh(emitChange: Bool = true) {
        let devices = coreAudio.allDevices.filter { ($0.transportType ?? .unknown) != .aggregate }
        let snapshots = devices.compactMap(snapshot(for:))

        outputs = snapshots.filter(\.hasOutput)
        inputs = snapshots.filter(\.hasInput)
        currentOutputID = coreAudio.defaultOutputDevice?.id
        currentInputID = coreAudio.defaultInputDevice?.id

        let nowByUID = Dictionary(snapshots.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
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

    private func snapshot(for device: AudioDevice) -> DeviceSnapshot? {
        guard let uid = device.uid else { return nil }
        let hasOutput = device.channels(scope: .output) > 0
        let hasInput = device.channels(scope: .input) > 0
        guard hasOutput || hasInput else { return nil }

        let transport = device.transportType
        let isInputOnly = hasInput && !hasOutput
        return DeviceSnapshot(
            id: device.id,
            uid: uid,
            name: DeviceNaming.friendly(rawName: device.name, transport: transport, isInputOnly: isInputOnly),
            kind: DeviceKind.classify(transport: transport, hasInput: hasInput, hasOutput: hasOutput),
            hasInput: hasInput,
            hasOutput: hasOutput
        )
    }

    // MARK: - Derived

    var currentOutput: DeviceSnapshot? { outputs.first { $0.id == currentOutputID } }
    var currentInput: DeviceSnapshot? { inputs.first { $0.id == currentInputID } }
    var builtInOutput: DeviceSnapshot? { outputs.first { $0.kind == .builtInSpeakers } }
    var builtInInput: DeviceSnapshot? { inputs.first { $0.kind == .builtInMic } }

    /// The menu-bar glyph mirrors where sound is going right now.
    var menuBarSymbol: String { currentOutput?.kind.symbol ?? "speaker.slash" }

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

    var currentRoute: Route { Route(outputID: currentOutputID, inputID: currentInputID) }

    // MARK: - Actions

    func selectOutput(_ id: AudioObjectID) {
        AudioDevice.lookup(by: id)?.isDefaultOutputDevice = true
        refresh()
    }

    func selectInput(_ id: AudioObjectID) {
        AudioDevice.lookup(by: id)?.isDefaultInputDevice = true
        refresh()
    }

    /// Sets either default (or both). We only ever touch the main output and
    /// main input - never the system-sounds output, so alert dings stay put.
    func route(outputID: AudioObjectID?, inputID: AudioObjectID?) {
        if let outputID { AudioDevice.lookup(by: outputID)?.isDefaultOutputDevice = true }
        if let inputID { AudioDevice.lookup(by: inputID)?.isDefaultInputDevice = true }
        refresh()
    }

    func apply(_ route: Route) { self.route(outputID: route.outputID, inputID: route.inputID) }
}
