// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import AppKit
import Combine

/// Opens the island on the Pad whenever Claude needs the user: a permission
/// or question from the Pad's own conversation, a request forwarded from a
/// Claude Code session in the Terminal, or a notice that one has finished.
/// Started by the feature runtime while the Pad is installed; stopped when it
/// is uninstalled, which also ends the Pad's process and the hook watcher.
final class PadIslandCoordinator {
    static let shared = PadIslandCoordinator()

    private var observers: [NSObjectProtocol] = []
    private var subscriptions = Set<AnyCancellable>()
    private var running = false
    /// While a request waits, the companion hops every so often to remind.
    private var reminder: Timer?

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
        // The companion plays along: a nod as Claude gets to work, a hop
        // when it needs an answer, a cheer when it is done, a puzzled look
        // when the tool is missing.
        let pad = ClaudePadService.shared
        pad.$status
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { status in
                let notch = NotchService.shared
                switch status {
                case .working: notch.reactMascot(.ready, patience: 2)
                case .waiting: notch.reactMascot(.bounce, patience: 3)
                case .unavailable: notch.reactMascot(.confused, patience: 3)
                case .idle: if pad.lastAnswer != nil { notch.reactMascot(.celebrate, patience: 3) }
                case .starting: break
                }
            }
            .store(in: &subscriptions)
        PadDictation.shared.$isListening
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { listening in
                NotchService.shared.reactMascot(listening ? .perk : .hush, patience: 2)
            }
            .store(in: &subscriptions)
        Publishers.CombineLatest(pad.$pending.map { $0 != nil }, ClaudeHookBridge.shared.$pendingRequests.map { !$0.isEmpty })
            .map { $0 || $1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] waiting in
                self?.remind(waiting)
            }
            .store(in: &subscriptions)
    }

    /// A hop now, and another every little while, until the request is answered.
    private func remind(_ waiting: Bool) {
        reminder?.invalidate()
        reminder = nil
        guard waiting else { return }
        NotchService.shared.reactMascot(.bounce, patience: 3)
        // The island plays the same reaction at most every half minute.
        let timer = Timer(timeInterval: NotchMascotReactionGate.repeatInterval + 2, repeats: true) { _ in
            NotchService.shared.reactMascot(.bounce, patience: 4)
        }
        RunLoop.main.add(timer, forMode: .common)
        reminder = timer
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        subscriptions.removeAll()
        reminder?.invalidate()
        reminder = nil
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
