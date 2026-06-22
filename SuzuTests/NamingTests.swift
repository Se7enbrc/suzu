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
        #expect(DeviceNaming.friendly(rawName: "MacBook Pro Speakers", transport: .builtIn, hasOutput: true) == "MacBook Pro speakers")
        #expect(DeviceNaming.friendly(rawName: "Mac Studio Speakers", transport: .builtIn, hasOutput: true) == "Mac Studio speakers")
        #expect(DeviceNaming.friendly(rawName: "iMac Microphone", transport: .builtIn, hasOutput: false) == "iMac mic")
        #expect(DeviceNaming.friendly(rawName: "MacBook Pro Microphone", transport: .builtIn, hasOutput: false) == "MacBook Pro mic")
    }

    @Test func builtInWithoutRoleWordGetsARoleSuffix() {
        #expect(DeviceNaming.friendly(rawName: "Mac", transport: .builtIn, hasOutput: true) == "Mac speakers")
        #expect(DeviceNaming.friendly(rawName: "Mac", transport: .builtIn, hasOutput: false) == "Mac mic")
    }

    @Test func stripsOnlyALeadingOwnerPossessive() {
        #expect(DeviceNaming.friendly(rawName: "Robert’s AirPods Pro", transport: .bluetooth, hasOutput: true) == "AirPods Pro")
        #expect(DeviceNaming.friendly(rawName: "Sam's Beats", transport: .bluetooth, hasOutput: true) == "Beats")
        // Not a leading possessive / a contraction - left alone.
        #expect(DeviceNaming.friendly(rawName: "Studio Display", transport: .usb, hasOutput: true) == "Studio Display")
        #expect(DeviceNaming.friendly(rawName: "Jabra Speak 750", transport: .usb, hasOutput: true) == "Jabra Speak 750")
        #expect(DeviceNaming.friendly(rawName: "It's a Speaker", transport: .usb, hasOutput: true) == "It's a Speaker")
    }

    @Test func classifiesByNameTokens() {
        #expect(DeviceKind.classify(transport: .usb, hasInput: false, hasOutput: true, name: "Studio Display") == .display)
        #expect(DeviceKind.classify(transport: .thunderbolt, hasInput: false, hasOutput: true, name: "Pro Display XDR") == .display)
        #expect(DeviceKind.classify(transport: .usb, hasInput: true, hasOutput: true, name: "Jabra Speak 750") == .external)
        #expect(DeviceKind.classify(transport: .bluetooth, hasInput: true, hasOutput: true, name: "AirPods Pro") == .headphones)
        #expect(DeviceKind.classify(transport: .bluetooth, hasInput: false, hasOutput: true, name: "AirPods Max") == .headphones)
        #expect(DeviceKind.classify(transport: .builtIn, hasInput: false, hasOutput: true, name: "Mac Studio Speakers") == .builtInSpeakers)
    }
}
