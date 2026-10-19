// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import Foundation

/// Finds the `claude` command-line tool (Claude Code) for the Pad and the
/// environment it needs, with the helpers the AI Agents section already uses
/// for its usage checks: the login shell's PATH (asked in its own session,
/// bounded), the installer's, Homebrew's and the Node version managers'
/// folders, and Claude Code's own opt-outs from `~/.claude/settings.json`.
enum ClaudeCLILocator {
    struct Resolution: Equatable {
        let executable: URL
        /// The child's environment: PATH with the tool's own folder first,
        /// so a Node launcher finds its `node`, and no self-updates.
        let environment: [String: String]
    }

    /// Cached across calls; `invalidate()` after the user changes the override.
    private static var cached: Resolution?
    private static var cachedOverride: String?
    private static let lock = NSLock()

    static func invalidate() {
        lock.lock()
        cached = nil
        cachedOverride = nil
        lock.unlock()
    }

    /// Resolves the tool, preferring `override` (a path the user typed in
    /// settings) when it points at an executable. May run the login shell
    /// once, so call it off the main thread.
    static func resolve(override: String?) -> Resolution? {
        let override = override.flatMap { $0.isEmpty ? nil : $0 }
        lock.lock()
        if let cached, cachedOverride == override {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let home = FileManager.default.homeDirectoryForCurrentUser
        let shellPath = AgentCodexServer.loginShellPath()
            ?? ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let searchPath = AgentClaudeServer.searchPath(after: shellPath, home: home)

        var executable: URL?
        if let override {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue,
               FileManager.default.isExecutableFile(atPath: url.path) {
                executable = url
            }
        }
        if executable == nil {
            executable = AgentClaudeServer.executable(home: home, searchPath: searchPath)
        }
        guard let executable else { return nil }

        var environment = AgentCodexServer.environment(for: executable, searchPath: searchPath)
        environment = AgentClaudeServer.environment(environment, home: home)
        let resolution = Resolution(executable: executable, environment: environment)
        lock.lock()
        cached = resolution
        cachedOverride = override
        lock.unlock()
        return resolution
    }
}
