// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import AppKit
import Combine

/// The Pad: a conversation with the local Claude Code command-line tool
/// (`claude -p` in stream-json mode), shown inside the Dynamic Island.
///
/// One long-lived `claude` process carries a conversation. The Pad writes user
/// messages to its stdin as JSON lines and reads JSON lines from stdout: the
/// assistant's text arrives as streaming deltas, tool activity as `assistant`
/// messages, and whenever Claude needs a decision (a permission or a question
/// asked with AskUserQuestion) a `control_request` arrives that the island
/// answers with a `control_response`. The process ends the conversation only
/// when the Pad closes its stdin or the user resets it.
///
/// Everything published here changes on the main thread; the pipe readers hop
/// there before touching state.
final class ClaudePadService: ObservableObject {
    static let shared = ClaudePadService()

    // MARK: - Published state

    enum Status: Equatable {
        case idle
        case starting
        /// Claude is producing a reply (`detail` names a tool when one runs).
        case working(detail: String?)
        /// A `control_request` waits for the user.
        case waiting
        case unavailable(reason: String)
    }

    struct Entry: Identifiable, Equatable {
        enum Role: Equatable { case user, assistant, activity, error }
        let id: UUID
        let role: Role
        var text: String
        /// Names of files the user attached with the message.
        var attachments: [String] = []
        var isStreaming = false

        init(role: Role, text: String, attachments: [String] = [], isStreaming: Bool = false) {
            id = UUID()
            self.role = role
            self.text = text
            self.attachments = attachments
            self.isStreaming = isStreaming
        }
    }

    struct Question: Equatable, Identifiable {
        struct Option: Equatable, Identifiable {
            var id: String { label }
            let label: String
            let description: String
        }
        var id: String { question }
        let question: String
        let header: String
        let options: [Option]
        let multiSelect: Bool
    }

    struct PendingRequest: Equatable, Identifiable {
        enum Kind: Equatable {
            /// Claude wants to run a tool; `summary` describes the call.
            case permission(toolName: String, summary: String)
            /// Claude asked the user something with AskUserQuestion.
            case questions([Question])
        }
        let id: String
        let toolUseID: String?
        let kind: Kind
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var pending: PendingRequest?
    @Published private(set) var sessionID: String?
    @Published private(set) var modelName: String?
    /// The last text Claude finished, for the compact island summary.
    @Published private(set) var lastAnswer: String?
    /// Set when the tool could not be found; cleared on the next successful start.
    @Published private(set) var lastError: String?

    var isRunning: Bool { process?.isRunning == true }

    // MARK: - Preferences

    enum Preference {
        static let workingDirectory = "junoPad.workingDirectory"
        static let resumeLastSession = "junoPad.resumeLastSession"
        static let lastSessionID = "junoPad.lastSessionID"
        static let claudeExecutable = "junoPad.claudeExecutable"
        static let permissionMode = "junoPad.permissionMode"
        static let model = "junoPad.model"
    }

    /// Where Claude works: the folder its file tools see. Defaults to the home
    /// folder, where Claude Code's own memory and settings live.
    var workingDirectory: URL {
        get {
            let stored = UserDefaults.standard.string(forKey: Preference.workingDirectory) ?? ""
            let path = (stored as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }
        set { UserDefaults.standard.set(newValue.path, forKey: Preference.workingDirectory) }
    }

    var resumesLastSession: Bool {
        get { UserDefaults.standard.object(forKey: Preference.resumeLastSession) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Preference.resumeLastSession) }
    }

    /// A path typed by the user when the tool is not found automatically.
    var executableOverride: String {
        get { UserDefaults.standard.string(forKey: Preference.claudeExecutable) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: Preference.claudeExecutable)
            ClaudeCLILocator.invalidate()
        }
    }

    /// Claude Code permission mode for the Pad's session: "default" asks the
    /// island before risky tools, "acceptEdits" also lets Claude edit files
    /// in the working folder without asking.
    var permissionMode: String {
        get { UserDefaults.standard.string(forKey: Preference.permissionMode) ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: Preference.permissionMode) }
    }

    /// Model alias passed with `--model`; empty keeps Claude Code's default.
    var preferredModel: String {
        get { UserDefaults.standard.string(forKey: Preference.model) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Preference.model) }
    }

    // MARK: - Process

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrTail: [String] = []
    private var pendingRequests: [String: [String: Any]] = [:]
    private var streamingEntryID: UUID?
    private var startedAt: Date?
    /// Whether the running process was started with `--resume`.
    private var launchResumed = false
    /// The last message written, resent once when a resume fails at launch.
    private var lastMessage: [String: Any]?
    private var retriedWithoutResume = false

    private init() {}

    /// Sends a message. Starts the tool when no conversation is running.
    func send(_ text: String, attachments: [URL] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        if pending != nil {
            // A reply typed while a request waits answers nothing; the request
            // keeps its buttons and the message queues behind it.
            appendEntry(Entry(role: .error, text: PadStrings.current.answerRequestFirst))
            return
        }
        entries.append(Entry(role: .user, text: trimmed,
                             attachments: attachments.map { $0.lastPathComponent }))
        lastError = nil
        let message = userMessage(text: trimmed, attachments: attachments)
        lastMessage = message
        retriedWithoutResume = false
        if isRunning {
            status = .working(detail: nil)
            write(message)
            return
        }
        status = .starting
        startProcess { [weak self] started in
            guard let self, started else { return }
            self.status = .working(detail: nil)
            self.write(message)
        }
    }

    /// Answers a permission request.
    func answer(_ request: PendingRequest, allow: Bool) {
        guard let raw = pendingRequests[request.id] else { return }
        let input = (raw["request"] as? [String: Any])?["input"] as? [String: Any] ?? [:]
        let response: [String: Any] = allow
            ? ["behavior": "allow", "updatedInput": input]
            : ["behavior": "deny", "message": PadStrings.current.deniedMessage]
        complete(request, with: response)
    }

    /// Answers AskUserQuestion with one label per question.
    func answer(_ request: PendingRequest, answers: [String: String]) {
        guard let raw = pendingRequests[request.id] else { return }
        var input = (raw["request"] as? [String: Any])?["input"] as? [String: Any] ?? [:]
        input["answers"] = answers
        complete(request, with: ["behavior": "allow", "updatedInput": input])
    }

    private func complete(_ request: PendingRequest, with response: [String: Any]) {
        pendingRequests[request.id] = nil
        if pending?.id == request.id { pending = nil }
        status = .working(detail: nil)
        write(["type": "control_response",
               "response": ["subtype": "success", "request_id": request.id, "response": response]])
    }

    /// Stops the current reply; the conversation stays open.
    func interrupt() {
        guard isRunning else { return }
        write(["type": "control_request", "request_id": UUID().uuidString,
               "request": ["subtype": "interrupt"]])
    }

    /// Ends the process and forgets the transcript. The next message starts a
    /// new conversation.
    func reset() {
        terminate()
        entries.removeAll()
        pending = nil
        pendingRequests.removeAll()
        lastAnswer = nil
        sessionID = nil
        UserDefaults.standard.removeObject(forKey: Preference.lastSessionID)
        status = .idle
    }

    /// Ends the process but keeps the transcript; a later message resumes the
    /// same session when resuming is on.
    func stop() {
        terminate()
        status = .idle
    }

    private func terminate() {
        guard let process else { return }
        stdinHandle?.closeFile()
        stdinHandle = nil
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
    }

    // MARK: - Launch

    /// Finds the tool off the main thread (the login shell can take a few
    /// seconds the first time), then launches it and reports whether it runs.
    private func startProcess(completion: @escaping (Bool) -> Void) {
        let override = executableOverride
        DispatchQueue.global(qos: .userInitiated).async {
            let resolution = ClaudeCLILocator.resolve(override: override.isEmpty ? nil : override)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let resolution else {
                    let reason = PadStrings.current.toolNotFound
                    self.lastError = reason
                    self.status = .unavailable(reason: reason)
                    self.appendEntry(Entry(role: .error, text: reason))
                    completion(false)
                    return
                }
                completion(self.launch(resolution))
            }
        }
    }

    private func launch(_ resolution: ClaudeCLILocator.Resolution) -> Bool {
        if isRunning { return true }
        status = .starting
        startedAt = Date()
        let process = Process()
        process.executableURL = resolution.executable
        var arguments = ["-p",
                         "--input-format", "stream-json",
                         "--output-format", "stream-json",
                         "--verbose",
                         "--include-partial-messages",
                         "--permission-prompt-tool", "stdio",
                         "--permission-mode", permissionMode,
                         "--name", AppInfo.name]
        if !preferredModel.isEmpty {
            arguments += ["--model", preferredModel]
        }
        let previous = UserDefaults.standard.string(forKey: Preference.lastSessionID)
        launchResumed = false
        if resumesLastSession, let previous, !previous.isEmpty, sessionID == nil || sessionID == previous {
            arguments += ["--resume", previous]
            launchResumed = true
        }
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = resolution.path
        environment["TERM"] = "dumb"
        process.environment = environment

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdoutBuffer.removeAll()
        stderrTail.removeAll()

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // Empty data is the end of the pipe; stop reading it.
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                for line in text.split(separator: "\n") where !line.isEmpty {
                    self.stderrTail.append(String(line))
                }
                if self.stderrTail.count > 20 { self.stderrTail.removeFirst(self.stderrTail.count - 20) }
            }
        }
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async { self?.processEnded(finished) }
        }

        do {
            try process.run()
        } catch {
            let reason = PadStrings.current.toolFailedToStart(error.localizedDescription)
            lastError = reason
            status = .unavailable(reason: reason)
            appendEntry(Entry(role: .error, text: reason))
            return false
        }
        self.process = process
        stdinHandle = stdin.fileHandleForWriting
        return true
    }

    private func processEnded(_ finished: Process) {
        guard finished === process || process == nil else { return }
        // Flush whatever the last read left without a newline.
        if !stdoutBuffer.isEmpty {
            let rest = stdoutBuffer
            stdoutBuffer.removeAll()
            handle(line: rest)
        }
        (finished.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (finished.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        stdinHandle = nil
        finishStreaming()
        if let pending {
            pendingRequests[pending.id] = nil
            self.pending = nil
        }
        let diedEarly = finished.terminationStatus != 0 && finished.terminationReason == .exit
            && startedAt.map { Date().timeIntervalSince($0) < 15 } == true
        if diedEarly, launchResumed, !retriedWithoutResume, let message = lastMessage {
            // The stored session is gone (deleted, or from another folder):
            // start fresh once with the same message.
            retriedWithoutResume = true
            UserDefaults.standard.removeObject(forKey: Preference.lastSessionID)
            sessionID = nil
            status = .starting
            startProcess { [weak self] started in
                guard let self, started else { return }
                self.status = .working(detail: nil)
                self.write(message)
            }
            return
        }
        if diedEarly {
            // Died right after launch: usually not logged in, or a Node
            // launcher without node. Show the tool's own last words.
            let detail = stderrTail.suffix(3).joined(separator: "\n")
            let reason = PadStrings.current.toolExited(Int(finished.terminationStatus), detail: detail)
            lastError = reason
            appendEntry(Entry(role: .error, text: reason))
            status = .unavailable(reason: reason)
        } else {
            status = .idle
        }
    }

    // MARK: - Output

    private func consume(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newline)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
            handle(line: line)
        }
    }

    private func handle(line: Data) {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String else { return }
        switch type {
        case "system":
            handleSystem(object)
        case "stream_event":
            handleStreamEvent(object["event"] as? [String: Any] ?? [:])
        case "assistant":
            handleAssistant(object["message"] as? [String: Any] ?? [:])
        case "user":
            handleToolResults(object["message"] as? [String: Any] ?? [:])
        case "control_request":
            handleControlRequest(object)
        case "result":
            handleResult(object)
        default:
            break
        }
    }

    private func handleSystem(_ object: [String: Any]) {
        guard let subtype = object["subtype"] as? String else { return }
        switch subtype {
        case "init":
            if let id = object["session_id"] as? String {
                sessionID = id
                UserDefaults.standard.set(id, forKey: Preference.lastSessionID)
                ClaudeHookBridge.shared.setPadSession(id)
            }
            if let model = object["model"] as? String { modelName = model }
            lastError = nil
            retriedWithoutResume = false
        case "permission_denied":
            // Our `--permission-prompt-tool` answers prompts; this arrives only
            // when the tool was denied by policy. Nothing to do.
            break
        default:
            break
        }
    }

    private func handleStreamEvent(_ event: [String: Any]) {
        guard let kind = event["type"] as? String else { return }
        switch kind {
        case "content_block_start":
            if let block = event["content_block"] as? [String: Any],
               block["type"] as? String == "text" {
                beginStreaming(initialText: block["text"] as? String ?? "")
            }
        case "content_block_delta":
            if let delta = event["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                appendStreaming(text)
            }
        case "content_block_stop":
            finishStreaming()
        default:
            break
        }
    }

    private func handleAssistant(_ message: [String: Any]) {
        guard let content = message["content"] as? [[String: Any]] else { return }
        for block in content {
            switch block["type"] as? String {
            case "text":
                // Authoritative text for the block that just streamed.
                let text = block["text"] as? String ?? ""
                if let id = streamingEntryID, let index = entries.firstIndex(where: { $0.id == id }) {
                    entries[index].text = text
                    finishStreaming()
                } else if let last = entries.last, last.role == .assistant, last.text == text {
                    continue
                } else if !text.isEmpty {
                    appendEntry(Entry(role: .assistant, text: text))
                }
                if !text.isEmpty { lastAnswer = text }
            case "tool_use":
                let name = block["name"] as? String ?? "Tool"
                let input = block["input"] as? [String: Any] ?? [:]
                let summary = Self.summary(toolName: name, input: input)
                status = .working(detail: name)
                appendEntry(Entry(role: .activity, text: summary))
            default:
                break
            }
        }
    }

    private func handleToolResults(_ message: [String: Any]) {
        guard let content = message["content"] as? [[String: Any]] else { return }
        for block in content where block["type"] as? String == "tool_result" {
            if block["is_error"] as? Bool == true {
                let text = Self.flatten(block["content"]).split(separator: "\n").first.map(String.init) ?? ""
                if !text.isEmpty { appendEntry(Entry(role: .error, text: text)) }
            }
        }
        if case .working = status { status = .working(detail: nil) }
    }

    private func handleControlRequest(_ object: [String: Any]) {
        guard let id = object["request_id"] as? String,
              let request = object["request"] as? [String: Any],
              let subtype = request["subtype"] as? String else { return }
        guard subtype == "can_use_tool" else {
            // Anything else is unsupported here; answer so the tool never waits.
            write(["type": "control_response",
                   "response": ["subtype": "error", "request_id": id,
                                "error": "unsupported control request"]])
            return
        }
        let toolName = request["tool_name"] as? String ?? "Tool"
        let input = request["input"] as? [String: Any] ?? [:]
        let toolUseID = request["tool_use_id"] as? String
        pendingRequests[id] = object
        let kind: PendingRequest.Kind
        if toolName == "AskUserQuestion", let questions = Self.questions(from: input), !questions.isEmpty {
            kind = .questions(questions)
        } else {
            let summary = (request["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.summary(toolName: toolName, input: input)
            kind = .permission(toolName: toolName, summary: summary)
        }
        let pendingRequest = PendingRequest(id: id, toolUseID: toolUseID, kind: kind)
        if pending == nil {
            pending = pendingRequest
            status = .waiting
            NotificationCenter.default.post(name: Self.requestArrived, object: self)
        } else {
            queuedRequests.append(pendingRequest)
        }
    }

    /// Requests that arrived while another one was showing.
    private var queuedRequests: [PendingRequest] = []

    private func handleResult(_ object: [String: Any]) {
        finishStreaming()
        if object["is_error"] as? Bool == true {
            let text = (object["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            appendEntry(Entry(role: .error, text: text.isEmpty ? PadStrings.current.genericError : text))
        } else if let text = object["result"] as? String, !text.isEmpty {
            lastAnswer = text
            if entries.last?.role != .assistant || entries.last?.text != text {
                // No streamed block carried the final text (e.g. after a tool
                // run with partial messages suppressed); show it once.
                if !(entries.contains { $0.role == .assistant && $0.text == text }) {
                    appendEntry(Entry(role: .assistant, text: text))
                }
            }
        }
        if let id = object["session_id"] as? String {
            sessionID = id
            UserDefaults.standard.set(id, forKey: Preference.lastSessionID)
        }
        if let next = queuedRequests.first {
            queuedRequests.removeFirst()
            pending = next
            status = .waiting
        } else if pending == nil {
            status = .idle
        }
        NotificationCenter.default.post(name: Self.replyFinished, object: self)
    }

    // MARK: - Streaming entries

    private func beginStreaming(initialText: String) {
        finishStreaming()
        let entry = Entry(role: .assistant, text: initialText, isStreaming: true)
        entries.append(entry)
        streamingEntryID = entry.id
        trimEntries()
    }

    private func appendStreaming(_ text: String) {
        guard let id = streamingEntryID, let index = entries.firstIndex(where: { $0.id == id }) else {
            beginStreaming(initialText: text)
            return
        }
        entries[index].text += text
    }

    private func finishStreaming() {
        guard let id = streamingEntryID else { return }
        streamingEntryID = nil
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].isStreaming = false
            if entries[index].text.isEmpty {
                entries.remove(at: index)
            } else {
                lastAnswer = entries[index].text
            }
        }
    }

    private func appendEntry(_ entry: Entry) {
        entries.append(entry)
        trimEntries()
    }

    /// The island shows the tail of the conversation; older lines go.
    private func trimEntries() {
        let limit = 200
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    // MARK: - Input

    private func userMessage(text: String, attachments: [URL]) -> [String: Any] {
        var content: [[String: Any]] = []
        var textParts: [String] = []
        if !text.isEmpty { textParts.append(text) }
        for url in attachments {
            if let image = Self.imageBlock(for: url) {
                content.append(image)
                textParts.append(PadStrings.current.attachedImage(url.lastPathComponent))
            } else {
                textParts.append(PadStrings.current.attachedFile(url.path))
            }
        }
        content.insert(["type": "text", "text": textParts.joined(separator: "\n")], at: 0)
        return ["type": "user", "message": ["role": "user", "content": content]]
    }

    /// Images small enough to send inline go as base64 blocks, which lets
    /// Claude see them without a file permission; the rest go by path.
    private static func imageBlock(for url: URL) -> [String: Any]? {
        let mediaTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                          "gif": "image/gif", "webp": "image/webp"]
        guard let mediaType = mediaTypes[url.pathExtension.lowercased()],
              let data = try? Data(contentsOf: url), data.count <= 4_000_000 else { return nil }
        return ["type": "image",
                "source": ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()]]
    }

    private func write(_ object: [String: Any]) {
        guard let handle = stdinHandle,
              var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
        } catch {
            appendEntry(Entry(role: .error, text: PadStrings.current.genericError))
        }
    }

    // MARK: - Helpers

    static let requestArrived = Notification.Name("JunoPadRequestArrived")
    static let replyFinished = Notification.Name("JunoPadReplyFinished")

    private static func questions(from input: [String: Any]) -> [Question]? {
        guard let raw = input["questions"] as? [[String: Any]] else { return nil }
        return raw.compactMap { item in
            guard let question = item["question"] as? String else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> Question.Option? in
                guard let label = option["label"] as? String else { return nil }
                return Question.Option(label: label, description: option["description"] as? String ?? "")
            }
            return Question(question: question,
                            header: item["header"] as? String ?? "",
                            options: options,
                            multiSelect: item["multiSelect"] as? Bool ?? false)
        }
    }

    /// One line describing a tool call, for the activity log and prompts.
    static func summary(toolName: String, input: [String: Any]) -> String {
        func short(_ value: Any?) -> String {
            guard let text = value as? String else { return "" }
            let line = text.split(separator: "\n").first.map(String.init) ?? text
            return line.count > 90 ? String(line.prefix(90)) + "…" : line
        }
        switch toolName {
        case "Bash":
            return "Bash: " + short(input["command"])
        case "Read", "Write", "Edit", "NotebookEdit":
            return "\(toolName): " + short(input["file_path"] ?? input["notebook_path"])
        case "Glob", "Grep":
            return "\(toolName): " + short(input["pattern"])
        case "WebFetch":
            return "WebFetch: " + short(input["url"])
        case "WebSearch":
            return "WebSearch: " + short(input["query"])
        case "Task", "Agent":
            return "\(toolName): " + short(input["description"])
        default:
            let first = input.sorted { $0.key < $1.key }.first { $0.value is String }
            return first.map { "\(toolName): " + short($0.value) } ?? toolName
        }
    }

    private static func flatten(_ content: Any?) -> String {
        if let text = content as? String { return text }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }
}
