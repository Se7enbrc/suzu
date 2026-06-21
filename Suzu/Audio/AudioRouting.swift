//
//  AudioRouting.swift
//
//  Stable, value-typed model types plus the narrow protocol the Smart Moments
//  engine depends on. Routing is keyed on the device UID - stable across
//  disconnect/reconnect - never the transient AudioObjectID, which CoreAudio
//  recycles. The protocol lets the engine be unit-tested against a fake.

import Foundation

/// A pair of default devices identified by UID. Snapshotted before a change and
/// re-applied to undo it - so Undo survives a device flapping in and out.
struct Route: Equatable, Sendable {
    var outputUID: String?
    var inputUID: String?
}

/// What changed between two refreshes - the input to Smart Moments. Built only
/// from real (non-aggregate, non-virtual) devices.
struct WorldChange: Sendable {
    var added: [DeviceSnapshot]
    var removed: [DeviceSnapshot]
}

/// The slice of the audio layer the Smart Moments engine needs. A protocol so
/// the engine can run against an in-memory fake in tests, with no CoreAudio.
@MainActor
protocol AudioRouting: AnyObject {
    var outputs: [DeviceSnapshot] { get }
    var inputs: [DeviceSnapshot] { get }
    var currentOutput: DeviceSnapshot? { get }
    var currentInput: DeviceSnapshot? { get }
    var builtInOutput: DeviceSnapshot? { get }
    var builtInInput: DeviceSnapshot? { get }
    var currentRoute: Route { get }

    /// Sets either default (or both) by UID. Returns whether the write actually
    /// took effect - the caller must not claim success it didn't get.
    @discardableResult
    func route(outputUID: String?, inputUID: String?) -> Bool
}

extension AudioRouting {
    @discardableResult
    func apply(_ route: Route) -> Bool {
        self.route(outputUID: route.outputUID, inputUID: route.inputUID)
    }
}
