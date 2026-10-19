// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import AppKit
import Combine
import Foundation

/// The Dock's own preferences, the ones System Settings shows and the ones
/// it leaves out, read from the `com.apple.dock` domain and written back
/// through `defaults`, then shown by restarting the Dock. Nothing is kept
/// anywhere else: the Dock stays the owner of its settings, and a value
/// taken away here falls back to what macOS does on its own.
final class DockTuningService: ObservableObject {
    static let shared = DockTuningService()

    enum Position: String, CaseIterable, Identifiable {
        case left, bottom, right
        var id: String { rawValue }
    }

    enum MinimizeEffect: String, CaseIterable, Identifiable {
        case genie, scale
        /// Hidden in System Settings: the window is sucked into the Dock.
        case suck
        var id: String { rawValue }
    }

    /// What the Dock is set to. Defaults are what macOS uses with no value
    /// of its own saved.
    struct Settings: Equatable {
        var tileSize = 48
        var magnification = false
        var magnifiedSize = 128
        var position = Position.bottom
        var autohide = false
        /// Seconds the pointer waits at the edge before the Dock comes out.
        var autohideDelay = 0.5
        /// Seconds the Dock takes to slide in or out.
        var autohideDuration = 0.5
        var minimizeEffect = MinimizeEffect.genie
        var minimizeIntoApp = false
        var showRecents = true
        /// Only running apps, nothing pinned.
        var runningOnly = false
        /// Hidden apps drawn translucent.
        var dimHidden = false
        var launchAnimation = true
        var scrollToOpen = false
        var processIndicators = true
        /// Clicking an app hides every other one.
        var singleApp = false
        var stackHighlight = false

        static let tileSizes = 16...128
        static let delays = 0.0...2.0
        static let durations = 0.0...1.5
    }

    /// An app pinned to the Dock, for the icon page.
    struct PinnedApp: Identifiable, Equatable {
        let url: URL
        let name: String
        var id: String { url.path }
    }

    @Published private(set) var settings = Settings()
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published var failure: String?
    @Published private(set) var pinnedApps: [PinnedApp] = []

    private let queue = DispatchQueue(label: "junoisland.dock-tuning", qos: .userInitiated)
    private var applyWork: DispatchWorkItem?
    /// What the Dock has, as last read, so only changed keys are written.
    private var applied = Settings()

    private init() {}

    // MARK: Reading

    /// Reads the Dock's domain, off the main thread, and publishes it.
    func reload() {
        queue.async { [weak self] in
            let (settings, apps, failure) = Self.read()
            DispatchQueue.main.async {
                guard let self else { return }
                if let settings {
                    self.settings = settings
                    self.applied = settings
                    self.loaded = true
                }
                self.pinnedApps = apps
                if let failure { self.failure = failure }
            }
        }
    }

    private static func read() -> (Settings?, [PinnedApp], String?) {
        let result = BoundedProcessRunner.run("/usr/bin/defaults", ["export", "com.apple.dock", "-"],
                                              timeout: 8, maxOutputBytes: 4_000_000)
        guard result.status == 0, !result.timedOut,
              let plist = try? PropertyListSerialization.propertyList(from: result.output, format: nil),
              let dict = plist as? [String: Any] else {
            let text = String(data: result.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (nil, [], text.isEmpty ? "defaults export failed" : text)
        }
        var s = Settings()
        func number(_ key: String) -> Double? {
            if let n = dict[key] as? NSNumber { return n.doubleValue }
            return nil
        }
        func flag(_ key: String) -> Bool? {
            if let n = dict[key] as? NSNumber { return n.boolValue }
            return nil
        }
        if let n = number("tilesize") { s.tileSize = Int(n.rounded()) }
        if let b = flag("magnification") { s.magnification = b }
        if let n = number("largesize") { s.magnifiedSize = Int(n.rounded()) }
        if let raw = dict["orientation"] as? String, let p = Position(rawValue: raw) { s.position = p }
        if let b = flag("autohide") { s.autohide = b }
        if let n = number("autohide-delay") { s.autohideDelay = n }
        if let n = number("autohide-time-modifier") { s.autohideDuration = n }
        if let raw = dict["mineffect"] as? String, let e = MinimizeEffect(rawValue: raw) { s.minimizeEffect = e }
        if let b = flag("minimize-to-application") { s.minimizeIntoApp = b }
        if let b = flag("show-recents") { s.showRecents = b }
        if let b = flag("static-only") { s.runningOnly = b }
        if let b = flag("showhidden") { s.dimHidden = b }
        if let b = flag("launchanim") { s.launchAnimation = b }
        if let b = flag("scroll-to-open") { s.scrollToOpen = b }
        if let b = flag("show-process-indicators") { s.processIndicators = b }
        if let b = flag("single-app") { s.singleApp = b }
        if let b = flag("mouse-over-hilite-stack") { s.stackHighlight = b }

        var apps: [PinnedApp] = []
        for item in dict["persistent-apps"] as? [[String: Any]] ?? [] {
            guard let tile = item["tile-data"] as? [String: Any],
                  let file = tile["file-data"] as? [String: Any],
                  let raw = file["_CFURLString"] as? String else { continue }
            let kind = (file["_CFURLStringType"] as? NSNumber)?.intValue ?? 15
            let url: URL? = kind == 0 ? URL(fileURLWithPath: raw) : URL(string: raw)
            guard let url, url.isFileURL else { continue }
            let name = tile["file-label"] as? String ?? url.deletingPathExtension().lastPathComponent
            apps.append(PinnedApp(url: url.standardizedFileURL, name: name))
        }
        return (s, apps, nil)
    }

    // MARK: Writing

    /// Takes new settings and, a moment later, writes what changed and
    /// restarts the Dock, so a slider on its way does not restart it at
    /// every step.
    func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        applyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.apply() }
        applyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func apply() {
        let wanted = settings, had = applied
        var commands: [[String]] = []
        func int(_ key: String, _ a: Int, _ b: Int) { if a != b { commands.append(["write", "com.apple.dock", key, "-int", String(a)]) } }
        func bool(_ key: String, _ a: Bool, _ b: Bool) { if a != b { commands.append(["write", "com.apple.dock", key, "-bool", a ? "true" : "false"]) } }
        func float(_ key: String, _ a: Double, _ b: Double) { if a != b { commands.append(["write", "com.apple.dock", key, "-float", String(format: "%.3f", a)]) } }
        func string(_ key: String, _ a: String, _ b: String) { if a != b { commands.append(["write", "com.apple.dock", key, "-string", a]) } }
        int("tilesize", wanted.tileSize, had.tileSize)
        bool("magnification", wanted.magnification, had.magnification)
        int("largesize", wanted.magnifiedSize, had.magnifiedSize)
        string("orientation", wanted.position.rawValue, had.position.rawValue)
        bool("autohide", wanted.autohide, had.autohide)
        float("autohide-delay", wanted.autohideDelay, had.autohideDelay)
        float("autohide-time-modifier", wanted.autohideDuration, had.autohideDuration)
        string("mineffect", wanted.minimizeEffect.rawValue, had.minimizeEffect.rawValue)
        bool("minimize-to-application", wanted.minimizeIntoApp, had.minimizeIntoApp)
        bool("show-recents", wanted.showRecents, had.showRecents)
        bool("static-only", wanted.runningOnly, had.runningOnly)
        bool("showhidden", wanted.dimHidden, had.dimHidden)
        bool("launchanim", wanted.launchAnimation, had.launchAnimation)
        bool("scroll-to-open", wanted.scrollToOpen, had.scrollToOpen)
        bool("show-process-indicators", wanted.processIndicators, had.processIndicators)
        bool("single-app", wanted.singleApp, had.singleApp)
        bool("mouse-over-hilite-stack", wanted.stackHighlight, had.stackHighlight)
        guard !commands.isEmpty else { return }
        applied = wanted
        run(commands, restart: true)
    }

    /// Adds a gap between icons: a full tile or a half one.
    func addSpacer(small: Bool) {
        let tile = small ? "small-spacer-tile" : "spacer-tile"
        run([["write", "com.apple.dock", "persistent-apps", "-array-add", "{\"tile-type\"=\"\(tile)\";}"]], restart: true)
    }

    /// Takes every value set here away, so the Dock is as macOS has it.
    func resetToSystem() {
        let keys = ["tilesize", "magnification", "largesize", "orientation", "autohide", "autohide-delay",
                    "autohide-time-modifier", "mineffect", "minimize-to-application", "show-recents", "static-only",
                    "showhidden", "launchanim", "scroll-to-open", "show-process-indicators", "single-app",
                    "mouse-over-hilite-stack"]
        applyWork?.cancel()
        run(keys.map { ["delete", "com.apple.dock", $0] }, restart: true, tolerant: true)
    }

    /// Restarts the Dock, so a changed icon or value shows.
    func restartDock() {
        run([], restart: true)
    }

    private func run(_ commands: [[String]], restart: Bool, tolerant: Bool = false) {
        busy = true
        queue.async { [weak self] in
            var failure: String?
            for arguments in commands {
                let result = BoundedProcessRunner.run("/usr/bin/defaults", arguments, timeout: 8, maxOutputBytes: 64_000)
                if result.status != 0, !tolerant {
                    let text = String(data: result.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    failure = text.isEmpty ? "defaults \(arguments.joined(separator: " ")) failed" : text
                    break
                }
            }
            if restart, failure == nil {
                _ = BoundedProcessRunner.run("/usr/bin/killall", ["Dock"], timeout: 5, maxOutputBytes: 4_000)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.failure = failure
                // The Dock writes its own view of things back as it starts.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.reload() }
            }
        }
    }

    // MARK: Icons

    /// Gives `app` a custom icon from `image`, as Get Info's icon well does,
    /// and restarts the Dock to show it. The app's own folder has to be
    /// writable: apps an installer placed as an administrator are not.
    func setIcon(_ image: NSImage?, for app: PinnedApp) -> Bool {
        guard FileManager.default.isWritableFile(atPath: app.url.path) else {
            failure = DockTuningStrings.current.iconNotWritable(app.name)
            return false
        }
        guard NSWorkspace.shared.setIcon(image, forFile: app.url.path, options: []) else {
            failure = DockTuningStrings.current.iconFailed(app.name)
            return false
        }
        failure = nil
        restartDock()
        return true
    }

    /// Whether `app` wears a custom icon just now: the Finder keeps one in
    /// an `Icon\r` file at the top of the bundle.
    func hasCustomIcon(_ app: PinnedApp) -> Bool {
        FileManager.default.fileExists(atPath: app.url.appendingPathComponent("Icon\r").path)
    }

    /// The icon the Dock shows for `app`, custom or its own.
    func icon(for app: PinnedApp) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.url.path)
    }
}
