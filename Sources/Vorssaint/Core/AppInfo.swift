// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Static identity of the app, shared by UI, notifications and tooling.
enum AppInfo {
    // Juno Island is an unofficial fork of Vorssaint (GPL-3.0-or-later). The
    // name, icon and bundle identity are the fork's own, as TRADEMARKS.md asks.
    static let name = "Juno Island"
    static let copyright = "© 2026 Maurin Rasi · based on Juno Island"
    /// The upstream project this fork is built on.
    static let upstreamName = "Juno Island"
    static let upstreamRepositoryURL = URL(string: "https://github.com/vorssaint/vorssaint-utils")!
    /// This fork's GitHub repository; releases (DMG) are downloaded from here by hand.
    static let repositoryURL = URL(string: "https://github.com/maurinrasi/vorssaint-utils")!
    static let websiteURL = repositoryURL
    static let coffeeURL = URL(string: "https://buymeacoffee.com/vorssaint")!
    static let discordURL = repositoryURL
    static let socialURL = repositoryURL
    /// The fork ships unsigned builds from its own GitHub releases, which the
    /// upstream self-updater cannot verify or install. Updates are manual.
    static let updatesDisabled = true

    /// The bundle version. The fallback only applies to the bare binary
    /// (e.g. `--selftest`), never the shipped app, which reads its Info.plist.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// True for the local "Vorssaint (Developer)" build (bundle id ends in `.dev`).
    /// It is never published and never auto-updates; all work is tested here first.
    static var isDeveloperBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".dev")
    }

    /// True when the current version is a pre-release (e.g. 3.3.4-beta.1 or 3.3.4-rc.1).
    static var isBeta: Bool {
        if isDeveloperBuild && UserDefaults.standard.bool(forKey: DefaultsKey.simulateBetaUI) {
            return true
        }
        let v = version.lowercased()
        return v.contains("-beta") || v.contains("-rc") || v.contains("-alpha")
    }

    /// The git commit a Developer build was compiled from, e.g. "ed2ebba · 2026-06-15 21:30"
    /// (or with a "-dirty" suffix on the SHA for uncommitted changes). build.sh stamps
    /// this into the Developer bundle only, so you can confirm at a glance that the
    /// running dev app matches the source you are about to change. nil in the official app.
    static var buildCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "VorssaintBuildCommit") as? String
    }
}
