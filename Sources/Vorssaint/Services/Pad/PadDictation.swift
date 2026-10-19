// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Maurin Rasi

import AVFoundation
import Speech

/// Speech-to-text for the Pad's microphone button, with Apple's Speech
/// framework. Partial results stream into `transcript` while listening; the
/// Pad puts the text into its field and the user sends it as usual. Audio is
/// recognized on the Mac when the language supports it, otherwise through
/// Apple's servers, exactly like the system's own dictation.
final class PadDictation: NSObject, ObservableObject {
    static let shared = PadDictation()

    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var failure: String?

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    /// The recognizer follows the Mac's language; German-speaking Switzerland
    /// falls back to Standard German when the regional variant is missing.
    private func makeRecognizer() -> SFSpeechRecognizer? {
        var candidates = [Locale.current]
        if let language = Locale.current.language.languageCode?.identifier {
            candidates.append(Locale(identifier: language))
        }
        candidates.append(Locale(identifier: "de-CH"))
        candidates.append(Locale(identifier: "de-DE"))
        candidates.append(Locale(identifier: "en-US"))
        let supported = SFSpeechRecognizer.supportedLocales()
        for locale in candidates where supported.contains(locale) {
            if let recognizer = SFSpeechRecognizer(locale: locale) { return recognizer }
        }
        return SFSpeechRecognizer()
    }

    func toggle() {
        if isListening { stop() } else { start() }
    }

    func start() {
        guard !isListening else { return }
        failure = nil
        transcript = ""
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else {
                    self.failure = PadStrings.current.dictationNotAllowed
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.failure = PadStrings.current.microphoneNotAllowed
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        let recognizer = makeRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            failure = PadStrings.current.dictationUnavailable
            return
        }
        self.recognizer = recognizer
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            failure = PadStrings.current.microphoneUnavailable
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            failure = PadStrings.current.microphoneUnavailable
            return
        }
        self.engine = engine
        self.request = request
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.stop() }
                }
                if error != nil, self.isListening {
                    // Silence after a result ends the task; a transcript that
                    // never came is reported, an interrupted one is kept.
                    if self.transcript.isEmpty {
                        self.failure = PadStrings.current.dictationNothingHeard
                    }
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isListening || engine != nil else { return }
        isListening = false
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        engine = nil
        request = nil
        task = nil
    }

    /// Hands the recognized text over and clears it.
    func takeTranscript() -> String {
        let text = transcript
        transcript = ""
        return text
    }
}
