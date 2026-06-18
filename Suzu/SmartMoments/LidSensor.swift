//
//  LidSensor.swift
//
//  Best-effort clamshell (lid) state. Used only to avoid offering the built-in
//  speakers while the Mac is docked with the lid shut - which would be the
//  wrong suggestion. Reads the IOPMrootDomain "AppleClamshellState" registry
//  property; returns nil when it can't tell (desktop Mac, or the property is
//  unavailable), and callers treat "unknown" as "don't block the offer".

import IOKit

enum LidSensor {
    /// `true` = lid open, `false` = lid closed, `nil` = unknown / not a laptop.
    static var isLidOpen: Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Bool else { return nil }

        // The property reports whether the lid is *closed*.
        return !value
    }
}
