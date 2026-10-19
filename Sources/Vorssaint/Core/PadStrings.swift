// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import Foundation

/// Words for the Pad, the Claude Code prompt inside the Dynamic Island.
/// German and English are written out; the other languages read the English.
struct PadStrings {
    let title: String
    /// One line for the Features page.
    let hubDescription: String
    let placeholder: String
    let send: String
    let stop: String
    let reset: String
    let attach: String
    let dictate: String
    let listening: String
    let thinking: String
    /// "%@ runs" while a tool works, with the tool's name.
    let runningTool: String
    let allow: String
    let deny: String
    let permissionTitle: String
    let questionTitle: String
    let doneTitle: String
    let answerRequestFirst: String
    let deniedMessage: String
    let toolNotFound: String
    let toolFailedToStartFormat: String
    let toolExitedFormat: String
    let genericError: String
    let attachedImageFormat: String
    let attachedFileFormat: String
    let dictationNotAllowed: String
    let microphoneNotAllowed: String
    let dictationUnavailable: String
    let microphoneUnavailable: String
    let dictationNothingHeard: String
    let attachmentsFormat: String
    let emptyHint: String
    let sessionLine: String
    // Settings
    let workingFolder: String
    let workingFolderHint: String
    let chooseFolder: String
    let resumeSession: String
    let resumeSessionHint: String
    let permissionMode: String
    let permissionDefault: String
    let permissionAcceptEdits: String
    let model: String
    let modelHint: String
    let executable: String
    let executableHint: String
    let executableFound: String
    let executableMissing: String
    let hooksTitle: String
    let hooksHint: String
    let installHooks: String
    let removeHooks: String
    let hooksInstalled: String
    let hooksNotInstalled: String
    let hooksFailedFormat: String
    let terminalNoticeTitle: String
    let terminalNoticeFinished: String
    let openTerminal: String
    let close: String
    let keywords: String

    static var current: PadStrings { FeatureStrings.pad(L10n.shared.language) }

    func toolFailedToStart(_ reason: String) -> String {
        String(format: toolFailedToStartFormat, reason)
    }

    func toolExited(_ status: Int, detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(format: toolExitedFormat, status) + (trimmed.isEmpty ? "" : "\n" + trimmed)
    }

    func attachedImage(_ name: String) -> String { String(format: attachedImageFormat, name) }
    func attachedFile(_ path: String) -> String { String(format: attachedFileFormat, path) }
    func attachments(_ count: Int) -> String { String(format: attachmentsFormat, count) }
    func running(_ tool: String) -> String { String(format: runningTool, tool) }
    func hooksFailed(_ reason: String) -> String { String(format: hooksFailedFormat, reason) }

    var searchKeywords: [String] { [hubDescription, placeholder, workingFolder, hooksTitle, keywords] }
}

extension FeatureStrings {
    static func pad(_ language: AppLanguage) -> PadStrings {
        switch language {
        case .de: return PadStrings(
            title: "Pad",
            hubDescription: "Ein Eingabefeld für Claude Code direkt in der Dynamic Island. Fragen, Berechtigungen und Antworten erscheinen rund um die Notch.",
            placeholder: "Frag Juno…",
            send: "Senden",
            stop: "Stopp",
            reset: "Neues Gespräch",
            attach: "Datei anhängen",
            dictate: "Diktieren",
            listening: "Ich höre zu…",
            thinking: "Denkt nach…",
            runningTool: "%@ läuft…",
            allow: "Erlauben",
            deny: "Ablehnen",
            permissionTitle: "Claude möchte",
            questionTitle: "Claude fragt",
            doneTitle: "Fertig",
            answerRequestFirst: "Beantworte zuerst die offene Anfrage oben.",
            deniedMessage: "Der Benutzer hat das im Pad abgelehnt.",
            toolNotFound: "Claude Code wurde nicht gefunden. Installiere es und melde dich im Terminal mit «claude» an, oder trage den Pfad in den Pad-Einstellungen ein.",
            toolFailedToStartFormat: "Claude Code konnte nicht gestartet werden: %@",
            toolExitedFormat: "Claude Code hat sich beendet (Code %d). Bist du im Terminal mit «claude» angemeldet?",
            genericError: "Da ist etwas schiefgelaufen. Versuch es noch einmal.",
            attachedImageFormat: "[Bild angehängt: %@]",
            attachedFileFormat: "Angehängte Datei (bitte lesen): %@",
            dictationNotAllowed: "Spracherkennung ist in den Systemeinstellungen nicht erlaubt.",
            microphoneNotAllowed: "Mikrofon ist in den Systemeinstellungen nicht erlaubt.",
            dictationUnavailable: "Spracherkennung ist gerade nicht verfügbar.",
            microphoneUnavailable: "Kein Mikrofon gefunden.",
            dictationNothingHeard: "Ich habe nichts verstanden.",
            attachmentsFormat: "%d Anhänge",
            emptyHint: "Schreib eine Frage, diktiere sie oder häng eine Datei an. Claude Code antwortet hier.",
            sessionLine: "Sitzung",
            workingFolder: "Arbeitsordner",
            workingFolderHint: "Der Ordner, den Claude mit seinen Werkzeugen sieht. Standard ist dein Benutzerordner.",
            chooseFolder: "Ordner wählen…",
            resumeSession: "Gespräch fortsetzen",
            resumeSessionHint: "Beim nächsten Start am letzten Gespräch weitermachen statt neu zu beginnen.",
            permissionMode: "Berechtigungen",
            permissionDefault: "Vor Änderungen fragen",
            permissionAcceptEdits: "Dateiänderungen im Arbeitsordner erlauben",
            model: "Modell",
            modelHint: "Leer lassen für den Standard von Claude Code. Sonst zum Beispiel «sonnet» oder «opus».",
            executable: "Pfad zu claude",
            executableHint: "Nur nötig, wenn das Pad Claude Code nicht selbst findet.",
            executableFound: "Gefunden",
            executableMissing: "Nicht gefunden",
            hooksTitle: "Meldungen aus dem Terminal",
            hooksHint: "Zeigt in der Island, wenn eine Claude-Code-Sitzung im Terminal eine Antwort braucht oder fertig ist. Trägt dafür Hooks in ~/.claude/settings.json ein.",
            installHooks: "Einschalten",
            removeHooks: "Ausschalten",
            hooksInstalled: "Eingeschaltet",
            hooksNotInstalled: "Ausgeschaltet",
            hooksFailedFormat: "Hooks konnten nicht geschrieben werden: %@",
            terminalNoticeTitle: "Claude Code im Terminal",
            terminalNoticeFinished: "Aufgabe fertig",
            openTerminal: "Zum Terminal",
            close: "Schliessen",
            keywords: "Claude, KI, Chat, Juno, Assistent, Prompt"
        )
        default: return PadStrings(
            title: "Pad",
            hubDescription: "A prompt field for Claude Code right inside the Dynamic Island. Questions, permissions and answers show up around the notch.",
            placeholder: "Ask Juno…",
            send: "Send",
            stop: "Stop",
            reset: "New conversation",
            attach: "Attach a file",
            dictate: "Dictate",
            listening: "Listening…",
            thinking: "Thinking…",
            runningTool: "%@ is running…",
            allow: "Allow",
            deny: "Deny",
            permissionTitle: "Claude wants to",
            questionTitle: "Claude asks",
            doneTitle: "Done",
            answerRequestFirst: "Answer the open request above first.",
            deniedMessage: "The user declined this in the Pad.",
            toolNotFound: "Claude Code was not found. Install it and sign in with “claude” in Terminal, or set its path in the Pad settings.",
            toolFailedToStartFormat: "Claude Code could not start: %@",
            toolExitedFormat: "Claude Code quit (code %d). Are you signed in with “claude” in Terminal?",
            genericError: "Something went wrong. Please try again.",
            attachedImageFormat: "[Image attached: %@]",
            attachedFileFormat: "Attached file (please read it): %@",
            dictationNotAllowed: "Speech recognition is not allowed in System Settings.",
            microphoneNotAllowed: "The microphone is not allowed in System Settings.",
            dictationUnavailable: "Speech recognition is not available right now.",
            microphoneUnavailable: "No microphone found.",
            dictationNothingHeard: "Nothing was recognized.",
            attachmentsFormat: "%d attachments",
            emptyHint: "Type a question, dictate it or attach a file. Claude Code answers here.",
            sessionLine: "Session",
            workingFolder: "Working folder",
            workingFolderHint: "The folder Claude sees with its tools. Your home folder by default.",
            chooseFolder: "Choose Folder…",
            resumeSession: "Resume conversation",
            resumeSessionHint: "Continue the last conversation at the next launch instead of starting over.",
            permissionMode: "Permissions",
            permissionDefault: "Ask before changes",
            permissionAcceptEdits: "Allow file edits in the working folder",
            model: "Model",
            modelHint: "Leave empty for Claude Code's default, or e.g. “sonnet” or “opus”.",
            executable: "Path to claude",
            executableHint: "Only needed when the Pad cannot find Claude Code by itself.",
            executableFound: "Found",
            executableMissing: "Not found",
            hooksTitle: "Terminal notices",
            hooksHint: "Shows in the island when a Claude Code session in Terminal needs an answer or has finished. Adds hooks to ~/.claude/settings.json for that.",
            installHooks: "Turn On",
            removeHooks: "Turn Off",
            hooksInstalled: "On",
            hooksNotInstalled: "Off",
            hooksFailedFormat: "The hooks could not be written: %@",
            terminalNoticeTitle: "Claude Code in Terminal",
            terminalNoticeFinished: "Task finished",
            openTerminal: "Open Terminal",
            close: "Close",
            keywords: "Claude, AI, chat, Juno, assistant, prompt"
        )
        }
    }
}
