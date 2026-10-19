// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import Foundation

/// What makes Juno Island itself: the island with its first extensions, the
/// Pad, Juno the companion, and the Dock pages. Installed and switched on
/// once at launch, whatever a first run or an earlier build left behind, so
/// an update brings them without a visit to the Features page. Versioned:
/// a later build that adds to the set bumps the version and runs again.
enum JunoSetup {
    static let version = 1

    /// The features every Juno Island install has.
    static var core: [AppFeature] {
        [.notch] + AppFeature.dynamicIslandInitialExtensions
            + [.notchPad, .notchMascot, .dockTuning, .dockPreview, .dockClick]
    }

    /// Installs the core and turns its switches on. Returns whether it did
    /// anything, which it does once per version.
    @discardableResult
    static func run(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.integer(forKey: DefaultsKey.junoSetupVersion) < version else { return false }
        for feature in core {
            defaults.set(true, forKey: feature.availabilityKey)
        }
        defaults.set(true, forKey: DefaultsKey.notchInitialExtensionsInstalled)
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchPadEnabled)
        defaults.set(true, forKey: DefaultsKey.notchMascotEnabled)
        defaults.set(false, forKey: DefaultsKey.notchMascotHidesWhenIdle)
        defaults.set(NotchMascotStyle.pixel.rawValue, forKey: DefaultsKey.notchMascotStyle)
        defaults.set(NotchMascotPalette.terracotta.rawValue, forKey: DefaultsKey.notchMascotPalette)
        defaults.set(version, forKey: DefaultsKey.junoSetupVersion)
        return true
    }
}
