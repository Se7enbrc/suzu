//
//  NamingTests.swift
//
//  Friendly device naming across real Macs and peripherals.

import SimplyCoreAudio
import Testing
@testable import Suzu

@MainActor
struct NamingTests {
    @Test func builtInKeepsRealModelName() {
        #expect(DeviceNaming.friendly(rawName: "MacBook Pro Speakers", transport: .builtIn) == "MacBook Pro speakers")
        #expect(DeviceNaming.friendly(rawName: "Mac Studio Speakers", transport: .builtIn) == "Mac Studio speakers")
        #expect(DeviceNaming.friendly(rawName: "iMac Microphone", transport: .builtIn) == "iMac mic")
        #expect(DeviceNaming.friendly(rawName: "MacBook Pro Microphone", transport: .builtIn) == "MacBook Pro mic")
    }

    @Test func stripsOnlyALeadingOwnerPossessive() {
        #expect(DeviceNaming.friendly(rawName: "Robert’s AirPods Pro", transport: .bluetooth) == "AirPods Pro")
        #expect(DeviceNaming.friendly(rawName: "Sam's Beats", transport: .bluetooth) == "Beats")
        // Not a leading possessive - left alone.
        #expect(DeviceNaming.friendly(rawName: "Studio Display", transport: .usb) == "Studio Display")
        #expect(DeviceNaming.friendly(rawName: "Jabra Speak 750", transport: .usb) == "Jabra Speak 750")
    }

    @Test func classifiesByNameTokens() {
        #expect(DeviceKind.classify(transport: .usb, hasInput: false, hasOutput: true, name: "Studio Display") == .display)
        #expect(DeviceKind.classify(transport: .usb, hasInput: true, hasOutput: true, name: "Jabra Speak 750") == .external)
        #expect(DeviceKind.classify(transport: .bluetooth, hasInput: true, hasOutput: true, name: "AirPods Pro") == .headphones)
        #expect(DeviceKind.classify(transport: .builtIn, hasInput: false, hasOutput: true, name: "Mac Studio Speakers") == .builtInSpeakers)
    }
}
