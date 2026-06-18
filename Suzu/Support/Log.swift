//
//  Log.swift
//
//  Thin os.Logger facade. One subsystem, a category per area. Messages are
//  written with the default privacy level - suzu logs device names and state,
//  never secrets.

import os

enum Log {
    private static let subsystem = "io.ugfugl.Suzu"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let moments = Logger(subsystem: subsystem, category: "SmartMoments")
}
