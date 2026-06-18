//
//  DeviceNaming.swift
//
//  Turns a raw CoreAudio device name into one a person would use. Built-in
//  devices become "MacBook speakers" / "MacBook mic"; everything else keeps its
//  own name, minus the owner's possessive ("Robert's AirPods Pro" → "AirPods
//  Pro"). Conservative on purpose - when unsure, it returns the original name.

import SimplyCoreAudio

enum DeviceNaming {
    static func friendly(rawName: String, transport: TransportType?, isInputOnly: Bool) -> String {
        if transport == .builtIn {
            let descriptor = isInputOnly ? "mic" : "speakers"
            if rawName.localizedCaseInsensitiveContains("MacBook") { return "MacBook \(descriptor)" }
            if rawName.localizedCaseInsensitiveContains("Mac") { return "Mac \(descriptor)" }
            return rawName
        }
        return stripPossessive(rawName)
    }

    /// "Robert's AirPods Pro" → "AirPods Pro". Leaves names without a leading
    /// possessive untouched.
    static func stripPossessive(_ name: String) -> String {
        for separator in ["’s ", "'s "] {
            if let range = name.range(of: separator) {
                return String(name[range.upperBound...])
            }
        }
        return name
    }
}
