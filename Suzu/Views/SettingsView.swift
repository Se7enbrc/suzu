//
//  SettingsView.swift
//
//  A small, calm window. Just the Smart Moment toggles in plain English, a
//  launch-at-login switch, and an about. Glass chrome (the window), plain
//  content. Resist every urge to add a tab.

import SwiftUI

struct SettingsView: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.settingsTitle)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(Copy.settingsSubtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section(Copy.smartHeading) {
                ForEach(SmartMoment.allCases) { moment in
                    Toggle(moment.settingsTitle, isOn: Binding(
                        get: { prefs.isEnabled(moment) },
                        set: { prefs.setEnabled(moment, $0) }
                    ))
                }
            }

            Section {
                Toggle(Copy.launchAtLogin, isOn: $prefs.launchAtLogin)
            }

            Section(Copy.aboutHeading) {
                LabeledContent("Version", value: Self.versionString)
                Text(Self.copyrightString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private static var copyrightString: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }
}
