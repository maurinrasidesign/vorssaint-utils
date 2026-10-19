// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import AppKit

/// Opens the island on the Pad whenever Claude needs the user: a permission
/// or question from the Pad's own conversation, a request forwarded from a
/// Claude Code session in the Terminal, or a notice that one has finished.
/// Started by the feature runtime while the Pad is installed; stopped when it
/// is uninstalled, which also ends the Pad's process and the hook watcher.
final class PadIslandCoordinator {
    static let shared = PadIslandCoordinator()

    private var observers: [NSObjectProtocol] = []
    private var running = false

    private init() {}

    func start() {
        ClaudeHookBridge.shared.start()
        guard !running else { return }
        running = true
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: ClaudePadService.requestArrived, object: nil, queue: .main) { [weak self] _ in
                self?.reveal(pinned: true)
            },
            center.addObserver(forName: ClaudeHookBridge.requestArrived, object: nil, queue: .main) { [weak self] _ in
                self?.reveal(pinned: true)
            },
            center.addObserver(forName: ClaudeHookBridge.noticeArrived, object: nil, queue: .main) { [weak self] _ in
                self?.reveal(pinned: false)
            },
        ]
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        running = false
        ClaudeHookBridge.shared.stop()
        ClaudePadService.shared.stop()
    }

    /// A request keeps the island open until it is answered or dismissed; a
    /// notice opens it the way a hover does, and it collapses on its own.
    private func reveal(pinned: Bool) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.notchPadEnabled),
              AppFeature.notch.isAvailable, AppFeature.notchPad.isAvailable else { return }
        let notch = NotchService.shared
        guard notch.modules.contains(.pad) else { return }
        notch.open(.pad, pinned: pinned, takeFocus: pinned, feedback: pinned)
    }
}
