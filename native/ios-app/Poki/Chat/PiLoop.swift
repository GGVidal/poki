import Foundation
import PiSwiftAgent
import PiSwiftAI
import PokiCore

/// The chat's model loop: pi's agent loop (PiSwiftAgent from xibbon/PiSwift, MIT, a Swift port of
/// pi-mono's pi-agent-core) with the providers of PiSwiftAI, on this iPhone. The prompt and the tools
/// are the chat's `Harness` (the Mac Poki Agent's); each tool call goes back to `ChatModel.perform`, so
/// look, do and status run through PokiCore with its approval rules and report_plan and finish_task
/// drive the plan bubble as before.
///
/// One loop holds one conversation, on one provider and model. Another model starts a new loop that
/// carries the messages over; pi converts them between providers.
@MainActor
final class PiLoop {
    enum Outcome: Equatable { case done, stopped, overTurns, stuck, failed(String) }

    /// This many steps in a row with the same call and the same screen end the task as stuck.
    nonisolated static let stallSteps = 6
    nonisolated static let stallPairs = 4

    let provider: ModelProvider
    let model: Model
    let inSplitView: Bool
    private let agent: Agent
    private let gate = StopGate()
    /// A custom address's HTTP client, which repairs a doubled `data:` stream and keeps what the address
    /// answered for the log.
    private let endpoint: CustomEndpointClient?
    private let stall = StallWatch()
    private let taskStart = Counter()
    private let turns = Counter()
    private let spent = Tally()

    var signature: String { "pi:\(provider.rawValue)/\(model.id)" }
    var messages: [AgentMessage] { agent.state.messages }

    /// `session` is the chat's id: the provider's prompt cache is keyed by it, so a step reads the
    /// prompt, the tools and the conversation so far from the cache instead of paying for them again.
    /// `thinking` is `.off` for a one-line job that needs no reasoning.
    init(provider: ModelProvider, model: Model, tools: [ToolSpec], inSplitView: Bool = false, carrying messages: [AgentMessage] = [],
         session: String? = nil, thinking: ThinkingLevel = .low,
         perform: @escaping @MainActor (ToolCall) async -> PokiCore.ToolAnswer) {
        self.provider = provider
        self.model = model
        self.inSplitView = inSplitView
        let gate = self.gate
        let endpoint = provider == .custom ? CustomEndpointClient() : nil
        self.endpoint = endpoint
        let stall = self.stall
        let turns = self.turns
        let agentTools = tools.map { spec in
            AgentTool(label: spec.name, name: spec.name, description: spec.description, parameters: spec.schema.mapValues { AnyCodable($0) }) { id, params, signal, _ in
                if gate.stopped { return Self.result(PokiCore.ToolAnswer(text: "Task stopped. Action not executed.", jpeg: nil, isError: true)) }
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                let arguments = (try? encoder.encode(params)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                // pi runs its loop in tasks of its own, so stop() reaches the call under way only through
                // `signal`: cancelling the call stops a `do` before its next action.
                let call = Task { @MainActor in await perform(ToolCall(id: id, name: spec.name, arguments: arguments)) }
                let forget = signal?.onCancel { call.cancel() }
                defer { forget?() }
                let answer = await call.value
                // The call and what it left on the screen, so a task that keeps working is told from a
                // loop: the arguments have sorted keys, and the screen has no clock or read time in it.
                if answer.waitingForOwner {
                    stall.reset()
                    // A step spent waiting for the owner is not the model running away: it does not
                    // count towards the ceiling.
                    turns.back()
                } else if stall.record(call: "\(spec.name)\n\(arguments)", screen: answer.screen ?? answer.text) {
                    gate.end(.stuck)
                }
                return Self.result(answer)
            }
        }
        let taskStart = self.taskStart
        // agent/pi-session.mjs: low thinking, one tool call at a time.
        agent = Agent(AgentOptions(
            initialState: AgentState(model: model, thinkingLevel: thinking, tools: agentTools, messages: messages),
            streamFn: endpoint.map { client -> StreamFn in
                { model, context, options in
                    var options = options
                    options.httpClient = client
                    return try streamSimple(model: model, context: context, options: options)
                }
            },
            // Old screen reads go out without their element lists and screenshots (HistoryTrim).
            transformContext: { messages, _ in HistoryTrim.trimmed(messages, taskStart: taskStart.value) },
            sessionId: session,
            getApiKey: { _ in await ModelCredential.apiKey(for: provider) },
            onPayload: Self.withoutReasoningSummary,
            toolExecution: .sequential
        ))
    }

    /// The owner's message (with the JPEGs of its photos and PDFs) under this task's instructions, then
    /// pi's loop until the model answers without tools, `stop()`, a repeated call or pair on the same
    /// screen, or `maxTurns` model turns (a ceiling for a model that runs away). Owner waits reset the
    /// stall history. `onText` gets each finished text block.
    /// `notes` are what Poki adds for this one task (the saved notes and routines that fit it, the
    /// apps it names). They ride with the owner's message, so the instructions at the head of the
    /// conversation stay the same from task to task and the provider's cache keeps matching them.
    func run(_ text: String, images: [Data] = [], instructions: String, notes: String? = nil, maxTurns: Int, onText: @escaping @MainActor (String) -> Void) async -> Outcome {
        gate.reset()
        stall.reset()
        use(instructions)
        // Reads from before this message belong to finished tasks.
        taskStart.set(agent.messages.count)
        spent.reset()
        let spent = self.spent
        let label = signature
        turns.set(0)
        let turns = self.turns
        let failure = Box()
        let agent = self.agent
        let gate = self.gate
        let unsubscribe = agent.subscribe { event, _ in
            switch event {
            case .turnStart:
                if turns.increment() > maxTurns { gate.end(.overTurns) }
                if gate.stopped { agent.abort() }
            case .messageEnd(.assistant(let reply)):
                if reply.stopReason == .error { failure.set(reply.errorMessage ?? "") }
                // What each step cost, so a build's log shows where a plan's allowance goes.
                let usage = reply.usage
                let step = spent.add(input: usage.input, cached: usage.cacheRead, output: usage.output)
                await MainActor.run {
                    AppLog.shared.add("chat", "tokens \(label) step \(step): input \(usage.input) new + \(usage.cacheRead) cached, output \(usage.output) (reasoning \(usage.reasoning ?? 0))")
                }
                let texts = reply.content.compactMap { block -> String? in
                    guard case .text(let content) = block else { return nil }
                    let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : text
                }
                if !texts.isEmpty { await MainActor.run { texts.forEach(onText) } }
            default: break
            }
        }
        defer { unsubscribe() }
        do {
            let message = notes.map { text + "\n\n[Task notes added by Poki, not written by the owner]\n" + $0 } ?? text
            try await agent.prompt(message, images: images.map { ImageContent(data: $0.base64EncodedString(), mimeType: "image/jpeg") })
        } catch {
            failure.set(error.localizedDescription)
        }
        let total = spent.total
        if total.steps > 0 {
            AppLog.shared.add("chat", "tokens \(label) total over \(total.steps) steps: input \(total.input) new + \(total.cached) cached, output \(total.output)")
        }
        if gate.stopped {
            switch gate.ending {
            case .overTurns: return .overTurns
            case .stuck: return .stuck
            default: return .stopped
            }
        }
        if let message = failure.value {
            if let seen = endpoint?.seen {
                let key = ModelKeys.key(provider)
                AppLog.shared.add("model", seen.summary(key: key) + ", failed: " + CustomEndpointClient.redacted(message, key: key))
            }
            // The owner's message goes again with the next one, as with the direct clients.
            _ = agent.dropTrailingErroredAssistant()
            return .failed(Self.words(message, provider: provider))
        }
        return .done
    }

    /// Ends the task after the step under way: nothing more is sent to the phone or the model.
    func stop() {
        gate.end(.stopped)
        agent.abort()
    }

    /// The leading system message holds the instructions and declares the tools. pi keeps it when a loop
    /// carries messages over, so each task puts its own text in it and leaves the tools as they are.
    private func use(_ instructions: String) {
        var messages = agent.messages
        if case .system(var system)? = messages.first {
            // Unchanged instructions leave the message as it is.
            if case .text(let current) = system.content, current == instructions { return }
            system.content = .text(instructions)
            messages[0] = .system(system)
        } else if let system = createInitialSystemMessage(instructions, nil) {
            messages.insert(.system(system), at: 0)
        }
        agent.messages = messages
    }

    /// The Responses API writes a summary of the model's reasoning when asked (pi asks by default).
    /// The chat never shows it and the reasoning itself goes back encrypted, so it is output paid for
    /// and thrown away. Other providers' requests have no such field and pass unchanged.
    private nonisolated static let withoutReasoningSummary: OnPayloadFn = { payload in
        guard payload.json.contains("\"summary\""),
              var body = (try? JSONSerialization.jsonObject(with: Data(payload.json.utf8))) as? [String: Any],
              var reasoning = body["reasoning"] as? [String: Any], reasoning["summary"] != nil else { return nil }
        reasoning.removeValue(forKey: "summary")
        body["reasoning"] = reasoning
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        return PayloadSnapshot(json: String(decoding: data, as: UTF8.self))
    }

    private nonisolated static func result(_ answer: PokiCore.ToolAnswer) -> AgentToolResult {
        var content: [ContentBlock] = [.text(TextContent(text: answer.text))]
        if let jpeg = answer.jpeg { content.append(.image(ImageContent(data: jpeg.base64EncodedString(), mimeType: "image/jpeg"))) }
        return AgentToolResult(content: content, isError: answer.isError)
    }

    /// The provider's message for the owner. pi never puts the key in it; a sign-in that ran out says so.
    private static func words(_ message: String, provider: ModelProvider) -> String {
        if message.contains("No API key") || message.contains("missingApiKey") || message.isEmpty && !ModelKeys.hasKey(provider) {
            return provider.signsIn ? AppLocalization.text(LocalizedStringResource("Sign in to ChatGPT again. Open Settings, then Models."))
                                    : AppLocalization.text(LocalizedStringResource("Add your \(provider.name) key. Open Settings, then Models."))
        }
        // The provider's stream ended on an error event with nothing in it (the library prints the
        // missing fields as "undefined"): said plainly, with what is left of it when there is any.
        if message.contains("Error Code undefined") || message.hasSuffix(": undefined") {
            let rest = message.replacingOccurrences(of: "Error Code undefined:", with: "").replacingOccurrences(of: "undefined", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            let said = AppLocalization.text(LocalizedStringResource("\(provider.name) ended the answer with an error and gave no reason. This is usually brief on their side. Tap Try Again."))
            return rest.isEmpty ? said : said + " (" + rest + ")"
        }
        return AppLocalization.text(LocalizedStringResource("\(provider.name), \(message.isEmpty ? AppLocalization.text("the request failed.") : message)"))
    }
}

/// Set by stop(), the turn limit or the stall watch, read by the tools on pi's tasks.
private final class StopGate: @unchecked Sendable {
    enum Ending { case stopped, overTurns, stuck }
    private let lock = NSLock()
    private var first: Ending?
    func reset() { lock.withLock { first = nil } }
    /// The owner's stop wins over the ending that was already there.
    func end(_ ending: Ending) { lock.withLock { if first == nil || ending == .stopped { first = ending } } }
    var stopped: Bool { lock.withLock { first != nil } }
    var ending: Ending? { lock.withLock { first } }
}

private final class StallWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [(call: String, screen: String)] = []
    func reset() { lock.withLock { steps.removeAll() } }
    func record(call: String, screen: String) -> Bool {
        lock.withLock {
            steps.append((call, screen))
            let pairSteps = PiLoop.stallPairs * 2
            let capacity = max(PiLoop.stallSteps, pairSteps)
            if steps.count > capacity { steps.removeFirst(steps.count - capacity) }
            let repeated = steps.suffix(PiLoop.stallSteps)
            if repeated.count == PiLoop.stallSteps,
               repeated.allSatisfy({ $0.call == call && $0.screen == screen }) { return true }
            let alternating = steps.suffix(pairSteps)
            return alternating.count == pairSteps && alternating.allSatisfy { $0.screen == screen }
                && zip(alternating.dropFirst(2), alternating).allSatisfy { $0.0.call == $0.1.call }
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() -> Int { lock.withLock { n += 1; return n } }
    func set(_ value: Int) { lock.withLock { n = value } }
    func back() { lock.withLock { n = max(0, n - 1) } }
    var value: Int { lock.withLock { n } }
}

/// The tokens of the task under way, counted on pi's tasks.
private final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var sum = (steps: 0, input: 0, cached: 0, output: 0)
    func reset() { lock.withLock { sum = (0, 0, 0, 0) } }
    func add(input: Int, cached: Int, output: Int) -> Int {
        lock.withLock {
            sum = (sum.steps + 1, sum.input + input, sum.cached + cached, sum.output + output)
            return sum.steps
        }
    }
    var total: (steps: Int, input: Int, cached: Int, output: Int) { lock.withLock { sum } }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?
    func set(_ value: String) { lock.withLock { if text == nil { text = value } } }
    var value: String? { lock.withLock { text } }
}
