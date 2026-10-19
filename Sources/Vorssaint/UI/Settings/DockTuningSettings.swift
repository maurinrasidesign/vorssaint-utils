// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Dock's own settings, hidden ones included, applied as they change.
struct DockTuningCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var dock = DockTuningService.shared

    private var text: DockTuningStrings { FeatureStrings.dockTuning(l10n.language) }

    var body: some View {
        SettingsCard(title: text.title) {
            if !dock.loaded {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(text.loading).foregroundStyle(.secondary)
                }
            }
            if let failure = dock.failure {
                Text(failure).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sizeSection
            hidingSection
            behaviorSection
            spacersSection
            resetSection
        }
        .disabled(!dock.loaded)
        .onAppear { dock.reload() }
    }

    // MARK: Sections

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.sizeSection).font(.subheadline.weight(.semibold))
            SettingsRow(symbol: "square.resize", title: text.iconSize) {
                sizeSlider(value: binding(\.tileSize), range: DockTuningService.Settings.tileSizes)
            }
            SettingsRow(symbol: "plus.magnifyingglass", title: text.magnification) {
                Toggle(text.magnification, isOn: binding(\.magnification)).labelsHidden()
            }
            if dock.settings.magnification {
                SettingsRow(symbol: "arrow.up.left.and.arrow.down.right", title: text.magnifiedSize) {
                    sizeSlider(value: binding(\.magnifiedSize), range: DockTuningService.Settings.tileSizes)
                }
            }
            SettingsRow(symbol: "dock.rectangle", title: text.position) {
                Picker(text.position, selection: binding(\.position)) {
                    Text(text.positionLeft).tag(DockTuningService.Position.left)
                    Text(text.positionBottom).tag(DockTuningService.Position.bottom)
                    Text(text.positionRight).tag(DockTuningService.Position.right)
                }
                .labelsHidden()
                .frame(width: 130)
            }
        }
    }

    private var hidingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(text.hidingSection).font(.subheadline.weight(.semibold))
            SettingsRow(symbol: "eye.slash", title: text.autohide, caption: text.autohideCaption) {
                Toggle(text.autohide, isOn: binding(\.autohide)).labelsHidden()
            }
            SettingsRow(symbol: "timer", title: text.delay, caption: text.delayCaption) {
                secondsSlider(value: binding(\.autohideDelay), range: DockTuningService.Settings.delays)
            }
            SettingsRow(symbol: "speedometer", title: text.duration, caption: text.durationCaption) {
                secondsSlider(value: binding(\.autohideDuration), range: DockTuningService.Settings.durations)
            }
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(text.behaviorSection).font(.subheadline.weight(.semibold))
            SettingsRow(symbol: "arrow.down.right.and.arrow.up.left", title: text.minimizeEffect) {
                Picker(text.minimizeEffect, selection: binding(\.minimizeEffect)) {
                    Text(text.effectGenie).tag(DockTuningService.MinimizeEffect.genie)
                    Text(text.effectScale).tag(DockTuningService.MinimizeEffect.scale)
                    Text(text.effectSuck).tag(DockTuningService.MinimizeEffect.suck)
                }
                .labelsHidden()
                .frame(width: 170)
            }
            Group {
                switchRow("arrow.down.to.line", text.minimizeIntoApp, caption: text.minimizeIntoAppCaption, isOn: binding(\.minimizeIntoApp))
                switchRow("clock.arrow.circlepath", text.showRecents, isOn: binding(\.showRecents))
                switchRow("play.circle", text.runningOnly, caption: text.runningOnlyCaption, isOn: binding(\.runningOnly))
                switchRow("circle.dotted", text.dimHidden, caption: text.dimHiddenCaption, isOn: binding(\.dimHidden))
            }
            Group {
                switchRow("arrow.up.and.down", text.launchAnimation, isOn: binding(\.launchAnimation))
                switchRow("scroll", text.scrollToOpen, caption: text.scrollToOpenCaption, isOn: binding(\.scrollToOpen))
                switchRow("circle.fill", text.processIndicators, isOn: binding(\.processIndicators))
                switchRow("square.on.square.dashed", text.singleApp, caption: text.singleAppCaption, isOn: binding(\.singleApp))
                switchRow("square.stack", text.stackHighlight, isOn: binding(\.stackHighlight))
            }
        }
    }

    private var spacersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(text.spacersSection).font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Button(text.addSpacer) { dock.addSpacer(small: false) }
                Button(text.addSmallSpacer) { dock.addSpacer(small: true) }
            }
            .padding(.leading, settingsRowTextInset)
            Text(text.spacersCaption).font(.caption).foregroundStyle(.secondary)
                .padding(.leading, settingsRowTextInset)
        }
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(text.resetSection).font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Button(text.reset) { dock.resetToSystem() }
                Button(text.restartDock) { dock.restartDock() }
                if dock.busy { ProgressView().controlSize(.small) }
            }
            .padding(.leading, settingsRowTextInset)
            Text(text.resetCaption).font(.caption).foregroundStyle(.secondary)
                .padding(.leading, settingsRowTextInset)
        }
    }

    // MARK: Controls

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<DockTuningService.Settings, Value>) -> Binding<Value> {
        Binding(get: { dock.settings[keyPath: keyPath] },
                set: { value in dock.update { $0[keyPath: keyPath] = value } })
    }

    private func switchRow(_ symbol: String, _ title: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    private func sizeSlider(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        let doubles = Binding<Double>(get: { Double(value.wrappedValue) },
                                      set: { value.wrappedValue = Int($0.rounded()) })
        return HStack(spacing: 8) {
            Slider(value: doubles, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .frame(width: 150)
            Text("\(value.wrappedValue) px")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }

    private func secondsSlider(value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: range, step: 0.05)
                .frame(width: 150)
            Text(value.wrappedValue < 0.001 ? text.instant : String(format: "%.2f s", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

/// Custom icons for the apps pinned to the Dock.
struct DockIconsCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var dock = DockTuningService.shared
    /// Bumped after an icon changes, so the rows draw it again.
    @State private var revision = 0

    private var text: DockTuningStrings { FeatureStrings.dockTuning(l10n.language) }

    var body: some View {
        SettingsCard(title: text.iconsTitle) {
            Text(text.iconsCaption).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if dock.pinnedApps.isEmpty {
                Text(text.noPinnedApps).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(dock.pinnedApps) { app in
                        row(app)
                    }
                }
                .id(revision)
            }
        }
    }

    private func row(_ app: DockTuningService.PinnedApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: dock.icon(for: app))
                .resizable()
                .frame(width: 28, height: 28)
            Text(app.name)
            if dock.hasCustomIcon(app) {
                Text(text.customBadge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
            }
            Spacer()
            if dock.hasCustomIcon(app) {
                Button(text.resetIcon) {
                    if dock.setIcon(nil, for: app) { revision += 1 }
                }
            }
            Button(text.changeIcon) { choose(app) }
        }
        .padding(.vertical, 2)
    }

    private func choose(_ app: DockTuningService.PinnedApp) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.image, UTType.icns]
        panel.message = app.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else {
            dock.failure = text.iconUnreadable
            return
        }
        if dock.setIcon(image, for: app) { revision += 1 }
    }
}
