//
//  DeviceNaming.swift
//
//  Turns a raw CoreAudio device name into one a person would use. Built-in
//  devices keep their real model and become "<model> speakers" / "<model> mic"
//  ("MacBook Pro speakers", "Mac Studio speakers", "iMac mic"); everything else
//  keeps its own name, minus a leading owner possessive ("Robert's AirPods Pro"
//  -> "AirPods Pro"). Conservative on purpose - when unsure, it returns the
//  original name.

import SimplyCoreAudio

enum DeviceNaming {
    static func friendly(rawName: String, transport: TransportType?) -> String {
        if transport == .builtIn {
            for token in ["Speakers", "Speaker"] where rawName.hasSuffix(token) {
                let model = rawName.dropLast(token.count).trimmingCharacters(in: .whitespaces)
                return model.isEmpty ? rawName : "\(model) speakers"
            }
            for token in ["Microphone", "Mic"] where rawName.hasSuffix(token) {
                let model = rawName.dropLast(token.count).trimmingCharacters(in: .whitespaces)
                return model.isEmpty ? rawName : "\(model) mic"
            }
            return rawName
        }
        return stripPossessive(rawName)
    }

    /// Strips only a leading "<Owner>'s " - a single first word, never an
    /// internal split (so "Bose's Best Speaker" loses only the leading word, and
    /// "Studio Display" is untouched). Handles the straight, curly (U+2019), and
    /// modifier-letter (U+02BC) apostrophes.
    static func stripPossessive(_ name: String) -> String {
        guard let space = name.firstIndex(of: " ") else { return name }
        let owner = name[..<space]
        let rest = name[name.index(after: space)...]
        guard !rest.isEmpty else { return name }
        for suffix in ["’s", "'s", "\u{02BC}s", "’S", "'S", "\u{02BC}S"] where owner.hasSuffix(suffix) {
            if owner.count > suffix.count { return String(rest) }
        }
        return name
    }
}
