// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import AppKit
import Combine

/// Brings the user's other Claude Code sessions (Terminal, editors, Juno) into
/// the island through Claude Code hooks.
///
/// `install()` writes a small shell script and registers it in
/// `~/.claude/settings.json` for three hook events. The script drops each
/// event's JSON into a folder this bridge watches:
///
/// - `PermissionRequest`: Claude wants to run a tool. The island shows it with
///   Allow and Deny; the chosen decision is written next to the request and
///   the script prints it, so Claude Code never shows its own prompt. When
///   nobody answers within the script's wait, or the app is not running, the
///   script exits without a decision and the terminal prompt appears as usual.
/// - `Stop`: a reply finished; the island shows its first line.
/// - `Notification`: Claude waits for input or needs attention.
///
/// Events from the Pad's own session are skipped: the Pad already answers its
/// prompts over stdio.
final class ClaudeHookBridge: ObservableObject {
    static let shared = ClaudeHookBridge()

    struct TerminalRequest: Identifiable, Equatable {
        let id: String            // the event file's stamp
        let sessionID: String
        let toolName: String
        let summary: String
        let cwd: String
        let receivedAt: Date
    }

    struct Notice: Identifiable, Equatable {
        enum Kind: Equatable { case finished, needsAttention }
        let id: String
        let kind: Kind
        let title: String
        let body: String
        let cwd: String
        let receivedAt: Date
    }

    @Published private(set) var pendingRequests: [TerminalRequest] = []
    @Published private(set) var latestNotice: Notice?
    @Published private(set) var isInstalled = false
    @Published private(set) var lastFailure: String?

    static let requestArrived = Notification.Name("JunoHookBridgeRequestArrived")
    static let noticeArrived = Notification.Name("JunoHookBridgeNoticeArrived")

    private static let supportFolderName = "Juno Island"
    private static let scriptName = "claude-hook.sh"
    private static let eventsFolderName = "claude-hooks"
    /// Marks the hook entries this app wrote, so only those are removed.
    private static let commandTag = "/\(supportFolderName)/\(scriptName)"

    private var watcher: DispatchSourceFileSystemObject?
    private var watchedDescriptor: Int32 = -1
    private var consumed = Set<String>()
    private var padSessionID: String?

    private init() {}

    // MARK: - Paths

    static var supportFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(supportFolderName, isDirectory: true)
    }

    static var scriptURL: URL { supportFolder.appendingPathComponent(scriptName) }
    static var eventsFolder: URL { supportFolder.appendingPathComponent(eventsFolderName, isDirectory: true) }
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    // MARK: - Lifecycle

    /// Starts watching when the hooks are registered. Safe to call repeatedly.
    func start() {
        isInstalled = Self.hooksRegistered()
        guard isInstalled else { return }
        try? FileManager.default.createDirectory(at: Self.eventsFolder, withIntermediateDirectories: true)
        startWatching()
        sweep()
    }

    func stop() {
        // The cancel handler closes the descriptor.
        watcher?.cancel()
        watcher = nil
        watchedDescriptor = -1
    }

    /// The Pad tells the bridge its session so its own events are skipped.
    func setPadSession(_ id: String?) {
        padSessionID = id
    }

    // MARK: - Install / remove

    /// Writes the script and registers it in ~/.claude/settings.json.
    func install() {
        lastFailure = nil
        do {
            try FileManager.default.createDirectory(at: Self.eventsFolder, withIntermediateDirectories: true)
            try Self.script(executable: Self.executableName).write(to: Self.scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.scriptURL.path)
            var settings = try Self.readSettings()
            var hooks = settings["hooks"] as? [String: Any] ?? [:]
            let quotedScript = "\"\(Self.scriptURL.path)\""
            let entries: [(event: String, argument: String, timeout: Int)] = [
                ("PermissionRequest", "permission", 40),
                ("Stop", "stop", 10),
                ("Notification", "notification", 10),
            ]
            for entry in entries {
                var groups = (hooks[entry.event] as? [[String: Any]] ?? []).filter { !Self.isOurs($0) }
                groups.append([
                    "hooks": [[
                        "type": "command",
                        "command": "\(quotedScript) \(entry.argument)",
                        "timeout": entry.timeout,
                    ]],
                ])
                hooks[entry.event] = groups
            }
            settings["hooks"] = hooks
            try Self.writeSettings(settings)
            isInstalled = true
            startWatching()
        } catch {
            lastFailure = error.localizedDescription
            isInstalled = Self.hooksRegistered()
        }
    }

    /// Removes only the entries this app added; other hooks stay.
    func remove() {
        lastFailure = nil
        do {
            var settings = try Self.readSettings()
            if var hooks = settings["hooks"] as? [String: Any] {
                for (event, value) in hooks {
                    guard let groups = value as? [[String: Any]] else { continue }
                    let kept = groups.filter { !Self.isOurs($0) }
                    if kept.isEmpty { hooks[event] = nil } else { hooks[event] = kept }
                }
                if hooks.isEmpty { settings["hooks"] = nil } else { settings["hooks"] = hooks }
                try Self.writeSettings(settings)
            }
            try? FileManager.default.removeItem(at: Self.scriptURL)
            stop()
            isInstalled = false
        } catch {
            lastFailure = error.localizedDescription
        }
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String)?.contains(commandTag) == true }
    }

    static func hooksRegistered() -> Bool {
        guard let settings = try? readSettings(),
              let hooks = settings["hooks"] as? [String: Any],
              let groups = hooks["PermissionRequest"] as? [[String: Any]] else { return false }
        return groups.contains(where: isOurs) && FileManager.default.isExecutableFile(atPath: scriptURL.path)
    }

    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "JunoHookBridge", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "~/.claude/settings.json is not a JSON object"])
        }
        return object
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let folder = settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            // One backup from before our first edit, kept untouched afterwards.
            let backup = folder.appendingPathComponent("settings.json.juno-island-backup")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.copyItem(at: settingsURL, to: backup)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    /// The running app's process name, which the script checks before waiting.
    private static var executableName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "JunoIsland"
    }

    private static func script(executable: String) -> String {
        """
        #!/bin/sh
        # Written by Juno Island. Forwards Claude Code hook events to the app.
        # Usage: claude-hook.sh permission|stop|notification   (event JSON on stdin)
        DIR="$HOME/Library/Application Support/Juno Island/claude-hooks"
        EVENT="${1:-event}"
        mkdir -p "$DIR" 2>/dev/null || exit 0
        STAMP="$(date +%s)-$$-$RANDOM"
        FILE="$DIR/$STAMP.$EVENT.json"
        cat > "$FILE.tmp" 2>/dev/null || exit 0
        mv "$FILE.tmp" "$FILE" 2>/dev/null || exit 0
        if [ "$EVENT" != "permission" ]; then
            exit 0
        fi
        # Only wait for an answer while the app can give one.
        if ! /usr/bin/pgrep -x "\(executable)" >/dev/null 2>&1; then
            rm -f "$FILE"
            exit 0
        fi
        DECISION="$DIR/$STAMP.decision.json"
        i=0
        while [ "$i" -lt 60 ]; do
            if [ -f "$DECISION" ]; then
                cat "$DECISION"
                rm -f "$DECISION" "$FILE"
                exit 0
            fi
            i=$((i + 1))
            sleep 0.5
        done
        # No answer in the island within 30 s: let the terminal ask as usual.
        rm -f "$FILE"
        exit 0
        """
    }

    // MARK: - Watching

    private func startWatching() {
        guard watcher == nil else { return }
        let folder = Self.eventsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        watchedDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .extend, .attrib],
                                                               queue: .main)
        source.setEventHandler { [weak self] in self?.sweep() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Reads every new event file in the folder.
    private func sweep() {
        let folder = Self.eventsFolder
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names.sorted() where name.hasSuffix(".json") && !name.hasSuffix(".decision.json") && !consumed.contains(name) {
            let url = folder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            consumed.insert(name)
            let parts = name.split(separator: ".")
            let stamp = parts.first.map(String.init) ?? name
            let event = parts.count > 2 ? String(parts[parts.count - 2]) : ""
            handle(event: event, stamp: stamp, object: object, file: url)
        }
        // Forget stamps whose files are gone, so the set stays small.
        let present = Set(names)
        consumed = consumed.filter { present.contains($0) }
        pruneExpired()
    }

    private func handle(event: String, stamp: String, object: [String: Any], file: URL) {
        let sessionID = object["session_id"] as? String ?? ""
        let cwd = object["cwd"] as? String ?? ""
        if !sessionID.isEmpty, sessionID == padSessionID {
            // The Pad answers its own prompts; a blank decision lets the
            // script return without one.
            if event == "permission" {
                writeDecision(stamp: stamp, json: "")
            }
            try? FileManager.default.removeItem(at: file)
            return
        }
        switch event {
        case "permission":
            let toolName = object["tool_name"] as? String ?? "Tool"
            let input = object["tool_input"] as? [String: Any] ?? [:]
            let request = TerminalRequest(id: stamp, sessionID: sessionID, toolName: toolName,
                                          summary: ClaudePadService.summary(toolName: toolName, input: input),
                                          cwd: cwd, receivedAt: Date())
            pendingRequests.append(request)
            NotificationCenter.default.post(name: Self.requestArrived, object: self)
        case "stop":
            try? FileManager.default.removeItem(at: file)
            let message = (object["last_assistant_message"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = message.split(separator: "\n").first.map(String.init) ?? ""
            let notice = Notice(id: stamp, kind: .finished,
                                title: PadStrings.current.terminalNoticeFinished,
                                body: firstLine, cwd: cwd, receivedAt: Date())
            latestNotice = notice
            NotificationCenter.default.post(name: Self.noticeArrived, object: self)
        case "notification":
            try? FileManager.default.removeItem(at: file)
            let message = object["message"] as? String ?? ""
            let title = object["title"] as? String ?? PadStrings.current.terminalNoticeTitle
            let notice = Notice(id: stamp, kind: .needsAttention, title: title, body: message,
                                cwd: cwd, receivedAt: Date())
            latestNotice = notice
            NotificationCenter.default.post(name: Self.noticeArrived, object: self)
        default:
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Requests older than the script's wait are answered in the terminal now.
    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-35)
        pendingRequests.removeAll { $0.receivedAt < cutoff }
    }

    // MARK: - Answering

    func answer(_ request: TerminalRequest, allow: Bool) {
        let decision: [String: Any] = allow
            ? ["behavior": "allow"]
            : ["behavior": "deny", "message": PadStrings.current.deniedMessage]
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                                            "decision": decision]]
        if let data = try? JSONSerialization.data(withJSONObject: output),
           let json = String(data: data, encoding: .utf8) {
            writeDecision(stamp: request.id, json: json)
        }
        pendingRequests.removeAll { $0.id == request.id }
    }

    func dismiss(_ request: TerminalRequest) {
        pendingRequests.removeAll { $0.id == request.id }
    }

    func clearNotice() {
        latestNotice = nil
    }

    private func writeDecision(stamp: String, json: String) {
        let url = Self.eventsFolder.appendingPathComponent("\(stamp).decision.json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Brings the app that hosts the session forward, best effort: the hook
    /// cannot say which terminal asked, so the frontmost terminal-like app wins.
    func revealTerminal() {
        let terminals = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
                         "com.github.wez.wezterm", "io.alacritty", "net.kovidgoyal.kitty",
                         "com.mitchellh.ghostty", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92"]
        for identifier in terminals {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
                app.activate(options: [])
                return
            }
        }
    }
}
