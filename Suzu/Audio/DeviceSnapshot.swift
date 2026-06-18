//
//  DeviceSnapshot.swift
//
//  An immutable, Sendable value describing one audio device at a moment in
//  time. The UI and the Smart Moments engine work entirely with these - the
//  live `AudioDevice` reference type never leaves AudioController.

import CoreAudio

struct DeviceSnapshot: Identifiable, Equatable, Sendable {
    /// CoreAudio object id. Stable while the device is connected; we re-look-up
    /// the live device by id only at the moment we change a default.
    let id: AudioObjectID
    /// Persistent unique id - stable across disconnect/reconnect, so it's what
    /// we use to tell "the same headset came back" from "a new device".
    let uid: String
    /// The name as a person would say it ("MacBook speakers", "AirPods Pro").
    let name: String
    let kind: DeviceKind
    let hasInput: Bool
    let hasOutput: Bool
}
