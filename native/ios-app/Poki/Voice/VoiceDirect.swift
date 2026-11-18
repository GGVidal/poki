import AVFoundation
import Foundation
import Speech

/// Voice without the Mac's voice bridge.
///
/// - With the owner's OpenAI API key on this iPhone, Poki asks OpenAI for a one-minute Realtime key
///   itself (what `bin/voice-bridge.mjs` does on the Mac: the same model, instructions and tools). The
///   voice model listens, speaks and can read the screen (look); work on the phone goes to Poki's chat
///   agent (`VoiceTasks`).
/// - With any other model (a ChatGPT plan, Anthropic, OpenRouter…), whose sign-in has no Realtime
///   audio, holding the button dictates on this iPhone (Apple's speech recognition, on the device when
///   it can) and lets go to send it to Poki's chat; Poki reads the answer out loud.
enum VoiceDirect {
    /// The live voice model the owner picked (Accounts › OpenAI › Live Voice), GPT Realtime 2.1 by default.
    static var model: String { ModelCatalog.voiceModel }

    /// The OpenAI API key on this iPhone, when there is one.
    static var apiKey: String? { enabled ? ModelKeys.key(.openai) : nil }

    /// The owner's switch in Accounts › OpenAI › Live Voice (on unless turned off).
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "voice.openai.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "voice.openai.enabled"); ModelKeys.saved += 1 }
    }

    /// Dictation into the chat works with any model the chat can use.
    static var canDictate: Bool { ModelKeys.hasUsableKey }

    /// Poki's interface language, named in English ("Chinese, Simplified"): the language Poki speaks
    /// from its first sentence. The owner picks it in Poki (it can differ from the iPhone's own).
    private static var interfaceLanguage: String {
        Locale(identifier: "en").localizedString(forIdentifier: AppLocalization.language) ?? "English"
    }

    // Tuned against gpt-realtime-2.1 with recorded Chinese speech and stubbed tools. The old text fell
    // back on the iPhone's language, so with the iPhone in English some answers to Chinese came out in
    // English; it also announced steps ("我来查一下…") and listed the screen's buttons.
    private static var instructions: String { """
    # Role
    You are Poki, a voice assistant on the user's iPhone. You listen and speak; Poki's agent does the work on the phone.

    # Language
    - Speak \(interfaceLanguage), the language of Poki's interface, from your first sentence on.
    - Speak another language only when the user's latest turn is clearly in it.
    - Tool results, screen text, screenshots and notes from Poki never choose your language.

    # Brevity
    - Act first, then talk. Say nothing before a tool call and nothing between steps: no "OK", no "let me check", no "I'll hand it over".
    - When the request is done, give the result in one short sentence; two only when the user asked for several facts.
    - Do not repeat the user's words, do not describe what you did or what else is on the screen, and add no greetings, filler or offers of more help. Explain only when the user asks.

    \(taskRules)
    """ }

    /// Said in every tool's description: the instructions alone left a spoken preamble before some calls.
    private static let silent = " No preamble: call it without saying anything first."

    /// How the voice model works with Poki's agent (the Tools and Approvals sections); the Mac's voice bridge says the same.
    static let taskRules = """
    # Tools
    - Never guess facts about the phone. To say what is on the screen right now, call look. A screenshot of the screen follows each look answer as an image: use it with the numbered elements to say what is on the screen. Asked what is on the screen, name the app and its main content in one sentence, without listing buttons.
    - To do anything on the phone (open an app, tap, type, send, change a setting, find or read something in an app), call run_task at once with the whole request. Poki's agent does every step and answers with how it ended; then say the result in one short sentence. Never repeat a task that already ran, including tasks from before a reconnect that the conversation says have finished.
    - While a task runs: when the user adds to it or changes it, call run_task with only what they added; it goes to the running task. When they ask how it is going, call check_task and say where it is in one sentence. When they tell you to stop or cancel it, call stop_task at once. When they only tell you to be quiet, stop talking; the task keeps running, and when its result arrives, say it in one sentence.
    - Poki's agent can open and operate every app installed on this iPhone, Apple's and anyone else's (WeChat, Instagram, Uber, a bank, a game): never tell the user an app is out of reach before a task has tried.

    # Approvals and stopping
    - A step that sends, pays, deletes or calls waits until the user allows it on the phone; if the result says they did not, say so in one sentence and do not try another way.
    - Only the user approves, with their own finger: never ask for a task that opens Poki to tap Allow, Deny or anything else in it.
    """

    private static let empty: [String: Any] = ["type": "object", "properties": [String: Any](), "additionalProperties": false]
    private static let tools: [[String: Any]] = [
        ["type": "function", "name": "get_ios_version", "description": "Read the iPhone model and its iOS version. Changes nothing on the phone." + silent, "parameters": empty],
        ["type": "function", "name": "look", "description": "Read the iPhone screen now: the app in front, its numbered elements (role, label, frame in points) and a screenshot. Changes nothing." + silent, "parameters": empty],
    ] + VoiceTasks.tools.map { tool in tool.merging(["description": (tool["description"] as? String ?? "") + silent]) { _, new in new } }

    /// The Realtime session Poki opens: model, instructions, voice, turn detection and tools.
    static var session: [String: Any] {
        [
            "type": "realtime", "model": model, "instructions": instructions, "output_modalities": ["audio"],
            "audio": [
                "input": ["turn_detection": ["type": "server_vad", "silence_duration_ms": 450, "prefix_padding_ms": 300, "threshold": 0.5, "create_response": true, "interrupt_response": true],
                          "noise_reduction": ["type": "near_field"], "transcription": ["model": "gpt-4o-mini-transcribe"]],
                "output": ["voice": "marin"],
            ],
            "tools": tools, "tool_choice": "auto", "parallel_tool_calls": false, "reasoning": ["effort": "low"],
        ]
    }

    /// A one-minute Realtime key from OpenAI, made with the owner's API key (sent only to OpenAI).
    static func token(apiKey: String) async throws -> VoiceBridge.Token {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/client_secrets")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expires_after": ["anchor": "created_at", "seconds": 60], "session": session])
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let value = json?["value"] as? String else {
            // OpenAI echoes a masked key in some errors; keep even that out of the screen and the log.
            let message = ((json?["error"] as? [String: Any])?["message"] as? String ?? "client_secrets \(status)")
                .replacingOccurrences(of: #"sk-[\w*-]+"#, with: "the API key", options: .regularExpression)
            throw VoiceError.realtime(status, message)
        }
        return VoiceBridge.Token(value: value, model: model, local_tools: ["get_ios_version", "look"])
    }
}

/// Hold to dictate, let go to send to Poki's chat, hear the answer: voice for models without Realtime.
@MainActor
final class Dictation: NSObject, AVSpeechSynthesizerDelegate {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private let speaker = AVSpeechSynthesizer()
    private(set) var heard = ""
    var onHeard: ((String) -> Void)?
    var onSpoken: (() -> Void)?

    override init() {
        super.init()
        speaker.delegate = self
    }

    static func allowed() async -> Bool {
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let microphone = await AVAudioApplication.requestRecordPermission()
        return speech && microphone
    }

    func listen() throws {
        speaker.stopSpeaking(at: .immediate)
        heard = ""
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { throw VoiceError.realtime(0, AppLocalization.text(LocalizedStringResource("Speech recognition is not available right now."))) }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try audio.setActive(true)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        Self.tap(input, into: request)
        engine.prepare()
        try engine.start()
        recognition = Self.recognize(recognizer, request) { [weak self] text in
            self?.heard = text
            self?.onHeard?(text)
        }
    }

    // The audio tap and the recognizer call back on their own threads, so their blocks are made outside
    // the main actor.
    nonisolated private static func tap(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func recognize(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                                              heard: @escaping @MainActor (String) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in heard(text) }
        }
    }

    /// Stops listening; the words heard so far (a moment later, for the last ones).
    func finish() async -> String {
        request?.endAudio()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? await Task.sleep(for: .milliseconds(600))
        recognition?.cancel()
        recognition = nil
        request = nil
        return heard.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        speaker.speak(utterance)
    }

    func stopSpeaking() { speaker.stopSpeaking(at: .immediate) }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onSpoken?() }
    }
}
