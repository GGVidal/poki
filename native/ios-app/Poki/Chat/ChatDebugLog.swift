import Foundation
import PokiCore

/// The chat's latest tasks for the maintainers' debug file (Advanced, the run log's share button).
/// That file held only routines and their runs, so a tester's failed chat tasks left it empty (Nov 13
/// 2026: "没能打开淘宝" with `"runs": []`). Each task keeps the model, the tools that ran, the kind of
/// each do action (with a launch's bundle id and a button, key or swipe direction), how long each took,
/// and what kind of failure a failed call had. Only these structured fields are kept: never a tool's
/// answer text, a typed or entered value, a routine's name, the request or a screenshot.
enum ChatDebugLog {
    static let limit = 20

    struct Entry: Codable, Equatable {
        var at: Date
        var model: String
        var seconds: Double
        /// The bundle ids of the apps the request named (KnownApps), what the model was told to launch.
        var named: [String]
        var calls: [Call]
        /// finish_task's success; nil when the model never called it.
        var finished: Bool?
    }

    struct Call: Codable, Equatable {
        var tool: String
        var actions: [String]
        var ok: Bool
        var ms: Int
        /// A failed call's kind of failure (`Failure`), never its text.
        var error: String?
    }

    /// What went wrong in a failed call, read from the answer but kept as a category only.
    enum Failure: String {
        case notInstalled = "launch_not_installed"
        case approval = "approval_required"
        case busy = "runner_busy"
        case sessionOff = "session_off"
        case stopped
        case timeout
        case invalidArguments = "invalid_arguments"
        case notSentTunnelDisconnected = "not_sent_tunnel_disconnected"
        case notSentPairingRequired = "not_sent_pairing_required"
        case notSentAppPreflight = "not_sent_app_preflight"
        case notSentScreenEvidence = "not_sent_screen_evidence"
        case notSentSessionNotReady = "not_sent_session_not_ready"
        case notSentLocked = "not_sent_locked"
        case notSentHandoff = "not_sent_handoff"
        case notSentOwnApp = "not_sent_own_app"
        case notSentApprovalDeclined = "not_sent_approval_declined"
        case notSentSplitView = "not_sent_split_view"
        case notSentTargetRefused = "not_sent_target_refused"
        case notSent = "not_sent"
        case failed

        init(answer: String) {
            let a = answer.lowercased()
            let notSent = a.hasPrefix("not_sent") || a.contains("\nnot_sent")
                || a.contains("nothing was sent") || a.contains("no requested action was sent")
                || a.hasPrefix("runner:") || a.contains("\nrunner:")
                || a.contains("not_hittable") || a.contains("is known on this phone")
            if a.contains("no app with that bundle id is installed") { self = .notInstalled }
            else if a.contains("approval_required") { self = .approval }
            else if a.contains("busy") || (notSent && a.contains("still finishing")) { self = .busy }
            else if a.contains("task stopped") { self = .stopped }
            else if a.contains("timed out") || a.contains("timeout") || a.contains("did not answer in time") { self = .timeout }
            else if notSent, Self.isTunnelDisconnected(a) { self = .notSentTunnelDisconnected }
            else if notSent, Self.isPairingRequired(a) { self = .notSentPairingRequired }
            else if a.contains("could not turn on") { self = .sessionOff }
            else if notSent, Self.isAppPreflight(a) { self = .notSentAppPreflight }
            else if notSent, Self.isScreenEvidence(a) { self = .notSentScreenEvidence }
            else if notSent, Self.isSessionNotReady(a) { self = .notSentSessionNotReady }
            else if notSent, Self.isLocked(a) { self = .notSentLocked }
            else if notSent, a.contains("step is handed to the owner") { self = .notSentHandoff }
            else if notSent, a.contains("leave poki first") { self = .notSentOwnApp }
            else if notSent, Self.isApprovalDeclined(a) { self = .notSentApprovalDeclined }
            else if notSent, Self.isSplitView(a) { self = .notSentSplitView }
            else if notSent, Self.isTargetRefused(a) { self = .notSentTargetRefused }
            else if a.contains("not json") || a.contains("must be an array") || a.contains("needs a ") || a.contains("takes ") { self = .invalidArguments }
            else if notSent { self = .notSent }
            else { self = .failed }
        }

        private static func isTunnelDisconnected(_ a: String) -> Bool {
            a.contains("waiting for the loopback")
                || a.contains("waiting for the local developer connection")
                || a.contains("local connection is off")
                || a.contains("choose and enable a local connection")
                || a.contains("remote pairing")
                || a.contains("loopback")
                || a.contains("10.7.0.1")
        }

        private static func isPairingRequired(_ a: String) -> Bool {
            a.contains("refused the pairing")
                || a.contains("pair this iphone first")
                || a.contains("pair again in poki's setup")
                || a.contains("cannot read the pairing file")
                || a.contains("pairing file is neither")
        }

        private static func isAppPreflight(_ a: String) -> Bool {
            a.contains("is known on this phone")
                || a.contains("apps by name")
                || a.contains("does not know an app called")
                || a.contains("could be any of")
                || a.contains("is not installed on this iphone")
        }

        private static func isScreenEvidence(_ a: String) -> Bool {
            a.contains("call look to read the current screen")
                || a.contains("is not in the latest read")
                || a.contains("needs a fresh read")
                || a.contains("the iphone unlocked. no requested action was sent")
                || a.contains("look at the selected pane")
        }

        private static func isSessionNotReady(_ a: String) -> Bool {
            let passcode = AppLocalization.text(AppModel.passcodeConfirmationMessage).lowercased()
            return a.contains(passcode)
                || a.contains("open settings › connection")
                || a.contains("设置 › 连接")
                || a.contains("設定 › 連線")
                || a.contains("waiting for automation to be ready")
                || a.hasPrefix("runner:")
                || a.contains("\nrunner:")
        }

        private static func isLocked(_ a: String) -> Bool {
            a.contains("screen: locked")
                || a.contains("automatic unlock could not be confirmed")
        }

        private static func isApprovalDeclined(_ a: String) -> Bool {
            a.contains("declined on the phone")
                || a.contains("approval request ended unanswered")
                || a.contains("did not allow it on the phone in time")
        }

        private static func isSplitView(_ a: String) -> Bool {
            a.contains("split view")
                || a.contains("two visible apps")
                || a.contains("already dropped")
        }

        private static func isTargetRefused(_ a: String) -> Bool {
            a.contains("not_hittable")
                || (a.hasPrefix("path:") && a.contains("nothing was sent"))
        }
    }

    private static let lock = NSLock()
    /// Where the tasks are kept (Application Support/chat-debug.json).
    static var file: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("chat-debug.json")
    }

    /// Saves a finished task, keeping the newest `limit`.
    static func add(_ entry: Entry) {
        lock.withLock {
            var all = readLocked()
            all.append(entry)
            if all.count > limit { all.removeFirst(all.count - limit) }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? encoder.encode(all) { try? data.write(to: file, options: .atomic) }
        }
    }

    static func entries() -> [Entry] { lock.withLock { readLocked() } }

    private static func readLocked() -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    /// A task's entry from its tool calls.
    static func entry(model: String, named: [String], calls: [CallRecord], finished: Bool?, seconds: Double, at: Date = Date()) -> Entry {
        Entry(at: at, model: model, seconds: (seconds * 10).rounded() / 10, named: named, calls: calls.map(call), finished: finished)
    }

    static func call(_ record: CallRecord) -> Call {
        Call(tool: record.name, actions: record.name == "do" ? actions(record.arguments) : [], ok: record.ok, ms: record.ms,
             error: record.ok ? nil : Failure(answer: record.answer).rawValue)
    }

    /// Each do action's kind. Only values that cannot hold the owner's text are added: a launch's bundle
    /// id when it is an app Poki knows or one installed on this iPhone, and the direction of a button,
    /// key or swipe from their fixed lists. A launch that names anything else (a made-up id, a sentence
    /// with dots) is kept as "launch" alone; a run keeps no routine name and a type no text.
    static func actions(_ arguments: String) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let actions = object["actions"] as? [[String: Any]] else { return [] }
        return actions.compactMap { action in
            // An action is named by its verb, whatever else it carries: {type, ref} is a type. A
            // dictionary has no order, so the verb is looked for, not taken as the first key.
            guard let kind = verbs.first(where: { action[$0] != nil }) else { return action.keys.contains { $0 != "finish" } ? "other" : nil }
            let value = action[kind]
            let word = (value as? String) ?? ((value as? [String: Any])?["direction"] as? String)
            switch kind {
            case "launch":
                if let given = value as? String {
                    return isKnownApp(given) ? "launch \(given)" : "launch"
                }
                if let spec = value as? [String: Any] {
                    if let bundle = spec["bundle"] as? String {
                        return isKnownApp(bundle) ? "launch bundle \(bundle)" : "launch bundle"
                    }
                    if spec["name"] as? String != nil {
                        return "launch name"
                    }
                    if let app = spec["app"] as? String {
                        return isKnownApp(app) ? "launch \(app)" : "launch"
                    }
                }
                return "launch"
            case "button", "key", "swipe":
                return word.flatMap { directions[kind]?.contains($0) == true ? "\(kind) \($0)" : nil } ?? kind
            default:
                return kind
            }
        }
    }

    private static let directions: [String: Set<String>] = [
        "button": ["home", "lock", "volume_up", "volume_down"],
        "key": ["return", "delete", "tab", "space", "escape"],
        "swipe": ["up", "down", "left", "right"],
    ]
    /// The verbs of a do action, the ones that say most first.
    private static let verbs = ["launch", "run", "type", "tap", "long_press", "drag", "pinch", "swipe", "scroll_to", "key", "button", "back", "handoff", "wait_until", "wait"]

    /// A bundle id Poki lists (KnownApps) or the phone's own app list holds: nothing the model or the
    /// owner could have made up.
    static func isKnownApp(_ id: String) -> Bool {
        KnownApps.byID[id.lowercased()] != nil || DynamicApps.name(forID: id) != nil
    }

    /// The maintainers' debug file: PokiCore's routines and runs, then these tasks as `chat_tasks`.
    static func exportBundle() -> Data {
        RoutineStore.shared.debugBundle(extra: ["chat_tasks": json()])
    }

    /// The tasks as the debug file's `chat_tasks`.
    static func json() -> JSON {
        let iso = ISO8601DateFormatter()
        return .array(entries().map { e -> JSON in
            JSON.object([
                "at": .string(iso.string(from: e.at)),
                "model": .string(e.model),
                "seconds": .number(e.seconds),
                "named": .array(e.named.map(JSON.string)),
                "finished": e.finished.map(JSON.bool) ?? .null,
                "calls": .array(e.calls.map { c -> JSON in
                    JSON.object([
                        "tool": .string(c.tool),
                        "actions": .array(c.actions.map(JSON.string)),
                        "ok": .bool(c.ok),
                        "ms": .number(Double(c.ms)),
                        "error": c.error.map(JSON.string) ?? .null,
                    ])
                }),
            ])
        })
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
