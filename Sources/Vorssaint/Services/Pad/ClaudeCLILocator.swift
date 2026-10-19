// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import Foundation

/// Finds the `claude` command-line tool (Claude Code) and the PATH it needs.
///
/// Claude Code is installed in different ways: the native installer symlinks
/// `~/.local/bin/claude`, Homebrew puts it in `/opt/homebrew/bin`, and an npm
/// install under nvm lands in `~/.nvm/versions/node/<version>/bin`, where the
/// launcher is a Node script that needs `node` from the same directory. The
/// locator asks the user's login shell first, so whatever the Terminal sees
/// is what the Pad uses, and falls back to the usual locations.
enum ClaudeCLILocator {
    struct Resolution: Equatable {
        let executable: URL
        /// PATH for the child process: the tool's own directory first, then the
        /// login shell's PATH, then the defaults macOS gives every process.
        let path: String
    }

    private static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Cached across calls; `invalidate()` after the user changes the override.
    private static var cached: Resolution?
    private static let lock = NSLock()

    static func invalidate() {
        lock.lock(); cached = nil; lock.unlock()
    }

    /// Resolves the tool, preferring `override` (a path the user typed in
    /// settings) when it points at an executable. Runs the login shell once,
    /// so call it off the main thread.
    static func resolve(override: String?) -> Resolution? {
        lock.lock()
        if let cached, override == nil || cached.executable.path == override {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let shellPath = loginShellPath()
        var candidates: [URL] = []
        if let override, !override.isEmpty {
            candidates.append(URL(fileURLWithPath: (override as NSString).expandingTildeInPath))
        }
        if let fromShell = commandLocation(named: "claude", path: shellPath) {
            candidates.append(fromShell)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates += [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            home.appendingPathComponent(".npm-global/bin/claude"),
        ]
        candidates += nvmCandidates(home: home)

        for candidate in candidates where isExecutable(candidate) {
            let resolved = candidate.resolvingSymlinksInPath()
            var directories = [candidate.deletingLastPathComponent().path,
                               resolved.deletingLastPathComponent().path]
            directories += shellPath.split(separator: ":").map(String.init)
            directories += defaultPath.split(separator: ":").map(String.init)
            var seen = Set<String>()
            let path = directories.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
            let resolution = Resolution(executable: candidate, path: path)
            lock.lock(); cached = resolution; lock.unlock()
            return resolution
        }
        return nil
    }

    private static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// Versions installed by nvm, newest first, so a fresh install wins.
    private static func nvmCandidates(home: URL) -> [URL] {
        let versions = home.appendingPathComponent(".nvm/versions/node")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: versions.path) else { return [] }
        return names.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { versions.appendingPathComponent("\($0)/bin/claude") }
    }

    /// The PATH of the user's login shell (`.zprofile`, `.zshrc`, nvm, Homebrew
    /// shellenv…). Empty when the shell cannot be run within a few seconds.
    static func loginShellPath() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let marker = "__JUNO_ISLAND_PATH__"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l reads the profile, -i the rc file (where nvm usually lives).
        process.arguments = ["-ilc", "printf '%s%s\\n' '\(marker)' \"$PATH\""]
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return "" }

        let deadline = DispatchTime.now() + .seconds(6)
        let group = DispatchGroup()
        group.enter()
        var output = Data()
        DispatchQueue.global(qos: .userInitiated).async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            return ""
        }
        process.waitUntilExit()
        guard let text = String(data: output, encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n").reversed() {
            if let range = line.range(of: marker) {
                return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func commandLocation(named name: String, path: String) -> URL? {
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }
}
