// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Pad inside the island: the conversation with Claude Code above a
/// prompt field. The island's top row holds the microphone, the attachment
/// button and the conversation menu. A permission or question Claude sends
/// takes the top of the page with its buttons until it is answered; requests
/// from Claude Code sessions in the Terminal show the same way.
struct NotchPadView: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    @ObservedObject private var pad = ClaudePadService.shared
    @ObservedObject private var bridge = ClaudeHookBridge.shared
    @ObservedObject private var dictation = PadDictation.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = ""
    @State private var attachments: [URL] = []
    @State private var answers: [String: String] = [:]
    @State private var editor = EditorHandle()
    @Environment(\.notchSettingsPreview) private var preview
    private var text: PadStrings { FeatureStrings.pad(l10n.language) }

    private final class EditorHandle {
        weak var view: NSTextView?
    }

    var body: some View {
        VStack(spacing: 6) {
            if let request = pad.pending {
                requestCard(request)
            } else if let request = bridge.pendingRequests.first {
                terminalRequestCard(request)
            }
            transcript
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !attachments.isEmpty {
                attachmentRow
            }
            inputRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .notchBand(leading: { statusLabel }, trailing: { actions })
        .onAppear {
            if !preview { DispatchQueue.main.async { focusInput() } }
        }
        .onDisappear {
            if dictation.isListening { dictation.stop() }
        }
        .onChange(of: dictation.transcript) { _, transcript in
            guard dictation.isListening || !transcript.isEmpty else { return }
            draft = transcript
        }
        .onChange(of: dictation.isListening) { _, listening in
            if !listening {
                let spoken = dictation.takeTranscript()
                if !spoken.isEmpty { draft = spoken }
                DispatchQueue.main.async { focusInput() }
            }
        }
        .onChange(of: pad.pending) { _, pending in
            answers.removeAll()
            if pending == nil { DispatchQueue.main.async { focusInput() } }
        }
    }

    // MARK: - Top row

    private var statusLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(.white.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if dictation.isListening { return text.listening }
        switch pad.status {
        case .idle: return "Juno"
        case .starting: return text.thinking
        case .working(let detail): return detail.map { text.running($0) } ?? text.thinking
        case .waiting: return text.questionTitle
        case .unavailable: return text.executableMissing
        }
    }

    private var isWorking: Bool {
        if case .working = pad.status { return true }
        return false
    }

    private var statusColor: Color {
        if dictation.isListening { return .red }
        switch pad.status {
        case .idle: return pad.isRunning ? .green : .white.opacity(0.4)
        case .starting, .working: return .yellow
        case .waiting: return .orange
        case .unavailable: return .red
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            NotchIconButton(symbol: dictation.isListening ? "mic.fill" : "mic",
                            title: text.dictate,
                            selected: dictation.isListening) {
                dictation.toggle()
            }
            NotchIconButton(symbol: "plus", title: text.attach, action: chooseAttachment)
            if isWorking {
                NotchIconButton(symbol: "stop.fill", title: text.stop) { pad.interrupt() }
            }
            NotchMenuButton(title: text.title, items: menuItems, cornerRadius: 9) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .help(text.title)
        }
    }

    private var menuItems: [NotchMenuItem] {
        [
            NotchMenuItem(title: text.reset, enabled: !pad.entries.isEmpty || pad.isRunning) { pad.reset() },
            NotchMenuItem(title: text.stop, enabled: pad.isRunning) { pad.stop() },
            .separator,
            NotchMenuItem(title: l10n.s.menuSettings) { service.openSettings(showing: .pad) },
        ]
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if pad.entries.isEmpty, pad.pending == nil, bridge.pendingRequests.isEmpty {
                        Text(text.emptyHint)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                    }
                    ForEach(pad.entries) { entry in
                        entryView(entry).id(entry.id)
                    }
                    if let notice = bridge.latestNotice {
                        noticeView(notice)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.automatic)
            .onChange(of: pad.entries.last?.text) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: pad.entries.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    @ViewBuilder private func entryView(_ entry: ClaudePadService.Entry) -> some View {
        switch entry.role {
        case .user:
            HStack {
                Spacer(minLength: 24)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                    if !entry.attachments.isEmpty {
                        Text(entry.attachments.joined(separator: ", "))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 0) {
                Text(entry.text.isEmpty ? "…" : entry.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(entry.isStreaming ? 0.85 : 0.95))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                Spacer(minLength: 24)
            }
        case .activity:
            HStack(spacing: 5) {
                Image(systemName: "gearshape")
                    .font(.system(size: 9, weight: .medium))
                Text(entry.text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 4)
        case .error:
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .medium))
                Text(entry.text)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .foregroundStyle(.orange.opacity(0.9))
            .padding(.horizontal, 4)
        }
    }

    private func noticeView(_ notice: ClaudeHookBridge.Notice) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: notice.kind == .finished ? "checkmark.circle" : "bell")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                if !notice.body.isEmpty {
                    Text(notice.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            NotchPillButton(title: text.openTerminal) {
                bridge.revealTerminal()
                bridge.clearNotice()
            }
            NotchIconButton(symbol: "xmark", title: text.close) { bridge.clearNotice() }
        }
        .padding(8)
        .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
    }

    // MARK: - Requests

    private func requestCard(_ request: ClaudePadService.PendingRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch request.kind {
            case .permission(let toolName, let summary):
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(text.permissionTitle) \(toolName)")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 8)
                    NotchPillButton(title: text.deny) { pad.answer(request, allow: false) }
                    NotchPillButton(title: text.allow, prominent: true) { pad.answer(request, allow: true) }
                }
                .foregroundStyle(.white.opacity(0.9))
                Text(summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
                    .textSelection(.enabled)
            case .questions(let questions):
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.bubble")
                        .font(.system(size: 11, weight: .medium))
                    Text(text.questionTitle)
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 8)
                    if questions.count > 1 {
                        NotchPillButton(title: text.send, prominent: answers.count == questions.count) {
                            pad.answer(request, answers: answers)
                        }
                        .disabled(answers.count < questions.count)
                    }
                }
                .foregroundStyle(.white.opacity(0.9))
                ForEach(questions) { question in
                    questionView(question, request: request, single: questions.count == 1)
                }
            }
        }
        .padding(8)
        .modifier(NotchControlSurface(cornerRadius: 12, selected: true, interactive: false))
    }

    private func questionView(_ question: ClaudePadService.Question,
                              request: ClaudePadService.PendingRequest, single: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question.question)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(question.options) { option in
                        let chosen = answers[question.question] == option.label
                        Button {
                            answers[question.question] = option.label
                            if single { pad.answer(request, answers: [question.question: option.label]) }
                        } label: {
                            Text(option.label)
                                .font(.system(size: 11, weight: chosen ? .semibold : .medium))
                                .foregroundStyle(chosen ? .white : .white.opacity(0.75))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(.white.opacity(chosen ? 0.22 : 0.08), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(NotchButtonStyle(cornerRadius: 12))
                        .help(option.description)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func terminalRequestCard(_ request: ClaudeHookBridge.TerminalRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .medium))
                Text("\(text.terminalNoticeTitle): \(request.toolName)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                NotchPillButton(title: text.deny) { bridge.answer(request, allow: false) }
                NotchPillButton(title: text.allow, prominent: true) { bridge.answer(request, allow: true) }
            }
            .foregroundStyle(.white.opacity(0.9))
            Text(request.summary)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(3)
                .textSelection(.enabled)
            if !request.cwd.isEmpty {
                Text(request.cwd)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(8)
        .modifier(NotchControlSurface(cornerRadius: 12, selected: true, interactive: false))
    }

    // MARK: - Input

    private var attachmentRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(attachments, id: \.self) { url in
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 9, weight: .medium))
                        Text(url.lastPathComponent)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                        Button {
                            attachments.removeAll { $0 == url }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .frame(width: 14, height: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .frame(height: 22)
                    .background(.white.opacity(0.08), in: Capsule())
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 24)
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ZStack(alignment: .topLeading) {
                PadInputField(text: $draft,
                              onSend: send,
                              onEscape: { service.collapse() },
                              onDropFiles: { attachments += $0.filter { url in !attachments.contains(url) } }) { view in
                    editor.view = view
                }
                if draft.isEmpty {
                    Text(text.placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.leading, PadInputField.inset.width + PadInputField.lineFragmentPadding)
                        .padding(.top, PadInputField.inset.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 30, maxHeight: 72)
            .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
            NotchIconButton(symbol: "arrow.up.circle.fill", title: text.send, selected: canSend, action: send)
                .disabled(!canSend)
        }
    }

    private var canSend: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
            && pad.pending == nil
    }

    private func send() {
        guard canSend else { return }
        if dictation.isListening { dictation.stop() }
        let message = draft
        let files = attachments
        draft = ""
        attachments.removeAll()
        pad.send(message, attachments: files)
        DispatchQueue.main.async { focusInput() }
    }

    private func chooseAttachment() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = text.attach
        panel.allowedContentTypes = [UTType.item]
        pad.modalInteractionActive = true
        let response = panel.runAboveIsland()
        pad.modalInteractionActive = false
        guard response == .OK else { return }
        attachments += panel.urls.filter { !attachments.contains($0) }
        DispatchQueue.main.async { focusInput() }
    }

    private func focusInput() {
        guard let view = editor.view, let window = view.window, window.isKeyWindow else { return }
        window.makeFirstResponder(view)
    }
}
