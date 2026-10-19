// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import AppKit
import SwiftUI

/// The Pad's settings inside the Dynamic Island page: where Claude works,
/// how much it may do on its own, where the tool lives, and whether the
/// island listens to Claude Code sessions in the Terminal.
struct NotchPadSettingsControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var bridge = ClaudeHookBridge.shared
    @AppStorage(DefaultsKey.notchPadEnabled) private var enabled = true
    @AppStorage(ClaudePadService.Preference.workingDirectory) private var workingDirectory = ""
    @AppStorage(ClaudePadService.Preference.resumeLastSession) private var resumes = true
    @AppStorage(ClaudePadService.Preference.permissionMode) private var permissionMode = "default"
    @AppStorage(ClaudePadService.Preference.model) private var model = ""
    @AppStorage(ClaudePadService.Preference.claudeExecutable) private var executable = ""
    @State private var executableState: Bool?
    private var text: PadStrings { FeatureStrings.pad(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(text.title, isOn: $enabled)
                .disabled(!AppFeature.notchPad.isAvailable)
            Text(text.hubDescription).font(.caption).foregroundStyle(.secondary)
            if enabled {
                folderRow
                Toggle(text.resumeSession, isOn: $resumes)
                Text(text.resumeSessionHint).font(.caption).foregroundStyle(.secondary)
                Picker(text.permissionMode, selection: $permissionMode) {
                    Text(text.permissionDefault).tag("default")
                    Text(text.permissionAcceptEdits).tag("acceptEdits")
                }
                TextField(text.model, text: $model, prompt: Text("sonnet"))
                Text(text.modelHint).font(.caption).foregroundStyle(.secondary)
                executableRow
                hooksRow
                PermissionRow(kind: .microphone)
            }
        }
        .onChange(of: enabled) { NotchService.shared.syncWithPreferences() }
        .onChange(of: executable) { _, _ in
            ClaudeCLILocator.invalidate()
            probeExecutable()
        }
        .onAppear {
            bridge.start()
            probeExecutable()
        }
    }

    private var folderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(text.workingFolder)
                Spacer()
                Text(displayedFolder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(text.chooseFolder, action: chooseFolder)
            }
            Text(text.workingFolderHint).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var displayedFolder: String {
        let path = ClaudePadService.shared.workingDirectory.path
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = ClaudePadService.shared.workingDirectory
        panel.prompt = text.chooseFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workingDirectory = url.path
    }

    private var executableRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(text.executable, text: $executable, prompt: Text("claude"))
                if let found = executableState {
                    Label(found ? text.executableFound : text.executableMissing,
                          systemImage: found ? "checkmark.circle" : "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(found ? Color.green : Color.red)
                        .labelStyle(.titleAndIcon)
                }
            }
            Text(text.executableHint).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func probeExecutable() {
        let override = executable
        DispatchQueue.global(qos: .userInitiated).async {
            let found = ClaudeCLILocator.resolve(override: override.isEmpty ? nil : override) != nil
            DispatchQueue.main.async { executableState = found }
        }
    }

    private var hooksRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(text.hooksTitle)
                Spacer()
                Text(bridge.isInstalled ? text.hooksInstalled : text.hooksNotInstalled)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(bridge.isInstalled ? text.removeHooks : text.installHooks) {
                    if bridge.isInstalled { bridge.remove() } else { bridge.install() }
                }
            }
            Text(text.hooksHint).font(.caption).foregroundStyle(.secondary)
            if let failure = bridge.lastFailure {
                Text(text.hooksFailed(failure)).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
