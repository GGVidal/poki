import Foundation

struct VoiceGoalID: Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String
    var description: String { rawValue }
}

enum VoiceUtteranceSource: String, Codable, Equatable, Sendable {
    case ownerMicrophone = "owner_microphone"
    case silentTest = "silent_test"
    case bystander = "bystander"
    case appAudio = "app_audio"
    case screenReader = "screen_reader"
    case quotedText = "quoted_text"

    var authorizesDeviceWork: Bool {
        switch self {
        case .ownerMicrophone, .silentTest: true
        case .bystander, .appAudio, .screenReader, .quotedText: false
        }
    }

    static func parse(_ raw: String?, fallback: Self) -> Self {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return fallback
        }
        switch raw {
        case "owner", "owner_microphone", "microphone", "user": return .ownerMicrophone
        case "silent_test", "rehearsal", "test", "test_text": return .silentTest
        case "bystander", "other_speaker": return .bystander
        case "app_audio", "playback", "media": return .appAudio
        case "screen_reader", "voiceover", "assistive": return .screenReader
        case "quoted", "quoted_text", "screen_text": return .quotedText
        default: return fallback
        }
    }
}

enum VoiceTaskRelation: String, Codable, Equatable, Sendable {
    case chitchat
    case continueTask = "continue_task"
    case supplementOrRevise = "supplement_or_revise"
    case replace
    case independentNewTask = "independent_new_task"
    case stop
}

enum VoiceReplacementScope: String, Codable, Equatable, Sendable {
    case none
    case constraintsOnly = "constraints_only"
    case contentAndConstraints = "content_and_constraints"
    case remainingSteps = "remaining_steps"
    case wholeGoal = "whole_goal"
}

enum VoiceStepOutcome: String, Codable, Equatable, Sendable {
    case running
    case succeeded
    case failedDefinitely = "failed_definitely"
    case unknown
    case blocked

    var blocksRepeat: Bool {
        switch self {
        case .running, .succeeded, .unknown: true
        case .failedDefinitely, .blocked: false
        }
    }

    static func classify(state: VoiceCall.State, output: String) -> Self {
        let lower = output.lowercased()
        let uncertain = lower.hasPrefix("unknown:")
            || lower.contains("may have run")
            || lower.contains("outcome could not be saved")
            || lower.contains("outcome is unknown")
            || lower.contains("not confirmed: no read after it")
        switch state {
        case .running:
            return .running
        case .done:
            return uncertain ? .unknown : .succeeded
        case .failed:
            return uncertain ? .unknown : .failedDefinitely
        }
    }
}

struct VoiceObservedElement: Equatable, Sendable {
    let ref: Int
    let type: String
    let text: String
}

struct VoiceObservedScreen: Equatable, Sendable {
    var app: String?
    var elements: [Int: VoiceObservedElement] = [:]

    static func parse(_ output: String) -> VoiceObservedScreen? {
        var app: String?
        var elements: [Int: VoiceObservedElement] = [:]
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("app:") {
                let value = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { app = VoiceAppIdentity.canonical(value) }
                continue
            }
            if let element = parseElementLine(line) {
                elements[element.ref] = element
            }
        }
        guard app != nil || !elements.isEmpty else { return nil }
        return VoiceObservedScreen(app: app, elements: elements)
    }

    private static func parseElementLine(_ line: String) -> VoiceObservedElement? {
        var cursor = line.startIndex
        if cursor < line.endIndex, "+-*•".contains(line[cursor]) {
            cursor = line.index(after: cursor)
        }
        while cursor < line.endIndex, line[cursor].isWhitespace {
            cursor = line.index(after: cursor)
        }
        let numStart = cursor
        while cursor < line.endIndex, line[cursor].isNumber {
            cursor = line.index(after: cursor)
        }
        guard numStart < cursor, let ref = Int(line[numStart..<cursor]) else { return nil }
        if cursor < line.endIndex, line[cursor] == "." {
            cursor = line.index(after: cursor)
        }
        guard cursor < line.endIndex, line[cursor].isWhitespace else { return nil }
        while cursor < line.endIndex, line[cursor].isWhitespace {
            cursor = line.index(after: cursor)
        }
        let typeStart = cursor
        while cursor < line.endIndex, !line[cursor].isWhitespace {
            cursor = line.index(after: cursor)
        }
        guard typeStart < cursor else { return nil }
        let type = String(line[typeStart..<cursor])
        let rest = line[cursor...].trimmingCharacters(in: .whitespaces)
        let text: String
        if let firstQuote = rest.firstIndex(of: "\"") {
            let afterFirst = rest.index(after: firstQuote)
            if let secondQuote = rest[afterFirst...].firstIndex(of: "\"") {
                text = String(rest[afterFirst..<secondQuote])
            } else {
                text = String(rest[afterFirst...])
            }
        } else if let bracket = rest.firstIndex(of: "[") {
            text = rest[..<bracket].trimmingCharacters(in: .whitespaces)
        } else {
            text = rest
        }
        return VoiceObservedElement(ref: ref, type: type, text: text)
    }
}

enum VoiceAppIdentity {
    private static let aliases: [(canonical: String, names: [String])] = [
        ("com.apple.mobilenotes", ["com.apple.mobilenotes", "备忘录", "備忘錄", "notes", "mobilenotes"]),
        ("com.tencent.xin", ["com.tencent.xin", "微信", "wechat"]),
        ("com.apple.preferences", ["com.apple.preferences", "设置", "設定", "settings", "preferences"]),
        ("com.apple.reminders", ["com.apple.reminders", "提醒事项", "提醒事項", "reminders"]),
        ("com.apple.mobilesms", ["com.apple.mobilesms", "信息", "訊息", "短信", "messages", "sms"]),
        ("com.apple.mobilemail", ["com.apple.mobilemail", "邮件", "郵件", "mail"]),
        ("com.apple.mobilecal", ["com.apple.mobilecal", "日历", "日曆", "calendar"]),
        ("com.apple.mobilesafari", ["com.apple.mobilesafari", "safari", "浏览器"]),
    ]

    static func canonical(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for entry in aliases {
            if entry.names.contains(trimmed) { return entry.canonical }
        }
        return trimmed
    }

    static func detectApp(in text: String) -> String? {
        let lower = text.lowercased()
        var best: (canonical: String, position: String.Index)?
        for entry in aliases {
            for name in entry.names {
                if let range = latestOccurrence(of: name, in: lower) {
                    if best == nil || range.lowerBound > best!.position {
                        best = (entry.canonical, range.lowerBound)
                    }
                }
            }
        }
        return best?.canonical
    }

    private static func latestOccurrence(of word: String, in text: String) -> Range<String.Index>? {
        guard !word.isEmpty else { return nil }
        let isCJK = word.unicodeScalars.contains(where: { $0.value > 0x2E80 })
        let boundary: (Character?) -> Bool = { $0.map { !$0.isLetter && !$0.isNumber } ?? true }
        var search = text.startIndex..<text.endIndex
        var latest: Range<String.Index>?
        while let range = text.range(of: word, range: search) {
            if isCJK {
                latest = range
            } else {
                let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
                let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
                if boundary(before) && boundary(after) { latest = range }
            }
            search = range.upperBound..<text.endIndex
        }
        return latest
    }

    fileprivate static func containsWholeWord(_ text: String, _ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let boundary: (Character?) -> Bool = { $0.map { !$0.isLetter && !$0.isNumber } ?? true }
        var search = text.startIndex..<text.endIndex
        while let range = text.range(of: word, range: search) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if boundary(before) && boundary(after) { return true }
            search = range.upperBound..<text.endIndex
        }
        return false
    }
}

struct VoiceProposedAction: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case launch(app: String)
        case tapRef(Int)
        case tapText(String)
        case tapPoint(Double, Double)
        case typeText(String, ref: Int?)
        case key(String)
        case navigation
        case other(String)
    }

    let kind: Kind
    let hintText: String?
}

struct VoiceToolProposal: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case controlCancel
        case readOnly
        case readScreen
        case openApp(app: String, page: String?)
        case deviceActions([VoiceProposedAction])
    }

    let callID: String
    let toolName: String
    let rawArguments: String
    let delegationID: String?
    let speechItemID: String?
    let goalID: VoiceGoalID?
    let goalRevision: Int?
    let source: VoiceUtteranceSource
    let kind: Kind

    init(call: VoiceCall, goalID: VoiceGoalID?, goalRevision: Int?, source: VoiceUtteranceSource) {
        self.callID = call.id
        self.toolName = call.name
        self.rawArguments = call.arguments
        self.delegationID = call.delegation
        self.speechItemID = call.speechItem
        self.goalID = goalID
        self.goalRevision = goalRevision
        self.source = source
        self.kind = Self.parseKind(name: call.name, arguments: call.arguments)
    }

    var isControlCancel: Bool {
        if case .controlCancel = kind { return true }
        return false
    }

    var isReadOnly: Bool {
        switch kind {
        case .readOnly, .readScreen: true
        case .controlCancel, .openApp, .deviceActions: false
        }
    }

    var isReadScreen: Bool {
        if case .readScreen = kind { return true }
        return false
    }

    var opensAppOnly: String? {
        switch kind {
        case .openApp(let app, _):
            return app
        case .deviceActions(let actions) where actions.count == 1:
            if case .launch(let app) = actions[0].kind { return app }
            return nil
        default:
            return nil
        }
    }

    var opensApp: String? {
        switch kind {
        case .openApp(let app, _):
            return app
        case .deviceActions(let actions):
            for action in actions {
                if case .launch(let app) = action.kind { return app }
            }
            return nil
        default:
            return nil
        }
    }

    var isPureNavigation: Bool {
        guard case .deviceActions(let actions) = kind, !actions.isEmpty else { return false }
        return actions.allSatisfy {
            if case .navigation = $0.kind { return true }
            return false
        }
    }

    var canonicalFingerprint: String {
        let compact = rawArguments.split(whereSeparator: \.isWhitespace).joined()
        return "\(toolName)|\(compact)"
    }

    func createsDraft(using screen: VoiceObservedScreen) -> Bool {
        guard case .deviceActions(let actions) = kind else { return false }
        return actions.contains { action in
            if let hint = action.hintText, Self.matchesDraftCreation(hint) { return true }
            switch action.kind {
            case .tapRef(let ref):
                return screen.elements[ref].map { Self.matchesDraftCreation($0.text) } ?? false
            case .tapText(let text):
                return Self.matchesDraftCreation(text)
            default:
                return false
            }
        }
    }

    func attemptsSendOrCommit(using screen: VoiceObservedScreen) -> Bool {
        guard case .deviceActions(let actions) = kind else { return false }
        return actions.contains { action in
            if let hint = action.hintText, Self.matchesSendOrCommit(hint) { return true }
            switch action.kind {
            case .tapRef(let ref):
                return screen.elements[ref].map { Self.matchesSendOrCommit($0.text) } ?? false
            case .tapText(let text):
                return Self.matchesSendOrCommit(text)
            default:
                return false
            }
        }
    }

    private static let draftCreationPhrases = [
        "新建备忘录", "新建備忘錄", "新建草稿", "写备忘录", "写新备忘录", "新建", "撰写", "撰寫",
        "new note", "create note", "new draft", "compose", "new message", "new reminder", "新建提醒事项",
    ]

    private static let sendCommitPhrases = [
        "发送", "發送", "发出去", "发送消息", "提交", "发布", "發布", "分享", "共享",
        "send", "submit", "post", "publish", "share", "send message",
    ]

    private static func matchesDraftCreation(_ text: String) -> Bool {
        matchesPhrases(text, draftCreationPhrases)
    }

    private static func matchesSendOrCommit(_ text: String) -> Bool {
        matchesPhrases(text, sendCommitPhrases)
    }

    private static func matchesPhrases(_ text: String, _ phrases: [String]) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        for phrase in phrases {
            if phrase.unicodeScalars.contains(where: { $0.value > 0x2E80 }) {
                if lower.contains(phrase) { return true }
            } else if VoiceAppIdentity.containsWholeWord(lower, phrase) {
                return true
            }
        }
        return false
    }

    private static func parseKind(name: String, arguments: String) -> Kind {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
        switch name {
        case VoiceDirect.cancelCurrentTask:
            return .controlCancel
        case "get_ios_version":
            return .readOnly
        case "look", "read_screen":
            return .readScreen
        case "open_app":
            let raw = (args["app"] as? String) ?? (args["name"] as? String) ?? ""
            return .openApp(app: VoiceAppIdentity.canonical(raw), page: args["page"] as? String)
        case "open_settings":
            return .openApp(app: "com.apple.preferences", page: args["page"] as? String)
        case "tap_text":
            let text = (args["text"] as? String) ?? ""
            return .deviceActions([VoiceProposedAction(kind: .tapText(text), hintText: text)])
        case "go_home":
            return .deviceActions([VoiceProposedAction(kind: .navigation, hintText: nil)])
        case "do":
            let rawActions = args["actions"] as? [[String: Any]] ?? []
            let parsed = rawActions.map(parseDoAction)
            return .deviceActions(parsed)
        default:
            return .deviceActions([VoiceProposedAction(kind: .other(name), hintText: nil)])
        }
    }

    private static func parseDoAction(_ raw: [String: Any]) -> VoiceProposedAction {
        let hint = (raw["label"] as? String) ?? (raw["target"] as? String) ?? (raw["action"] as? String)
        if let launch = raw["launch"] as? String {
            return VoiceProposedAction(kind: .launch(app: VoiceAppIdentity.canonical(launch)), hintText: hint)
        }
        if let launch = raw["launch"] as? [String: Any], let bundle = (launch["bundle"] as? String) ?? (launch["app"] as? String) {
            return VoiceProposedAction(kind: .launch(app: VoiceAppIdentity.canonical(bundle)), hintText: hint)
        }
        if let ref = raw["tap"] as? Int {
            return VoiceProposedAction(kind: .tapRef(ref), hintText: hint)
        }
        if let text = raw["tap"] as? String {
            return VoiceProposedAction(kind: .tapText(text), hintText: hint ?? text)
        }
        if let point = raw["tap"] as? [NSNumber], point.count >= 2 {
            return VoiceProposedAction(kind: .tapPoint(point[0].doubleValue, point[1].doubleValue), hintText: hint)
        }
        if let typed = raw["type"] as? String {
            return VoiceProposedAction(kind: .typeText(typed, ref: raw["ref"] as? Int), hintText: hint)
        }
        if let key = raw["key"] as? String {
            return VoiceProposedAction(kind: .key(key), hintText: hint)
        }
        if raw["swipe"] != nil || raw["scroll_to"] != nil || raw["back"] != nil
            || raw["button"] != nil || raw["wait"] != nil || raw["wait_until"] != nil {
            return VoiceProposedAction(kind: .navigation, hintText: hint)
        }
        return VoiceProposedAction(kind: .other(raw.keys.sorted().joined(separator: ",")), hintText: hint)
    }
}

struct VoiceUtteranceAssessment: Equatable, Sendable {
    let relation: VoiceTaskRelation
    let goalID: VoiceGoalID?
    let revision: Int?
    let baseRevision: Int?
    let replacementScope: VoiceReplacementScope
    let needsFreshEvidence: Bool
    let forbidsSend: Bool
    let allowsSend: Bool
}

struct VoiceUtteranceRecord: Equatable, Sendable {
    let id: String
    let source: VoiceUtteranceSource
    let text: String
    let relation: VoiceTaskRelation
    let goalID: VoiceGoalID?
    let revision: Int?
    let baseRevision: Int?
    let replacementScope: VoiceReplacementScope
    let needsFreshEvidence: Bool
    let receivedAt: Date
}

struct VoiceGoalStep: Equatable, Sendable {
    let callID: String
    let goalID: VoiceGoalID
    let revision: Int
    let session: Int
    let toolName: String
    let fingerprint: String
    let opensApp: String?
    let createsDraft: Bool
    let isReadOnly: Bool
    let isPureNavigation: Bool
    var outcome: VoiceStepOutcome
    var summary: String
}

struct VoiceGoal: Equatable, Sendable {
    let id: VoiceGoalID
    var revision: Int
    var baseRevision: Int?
    var originalUtterance: String
    var latestUtterance: String
    var source: VoiceUtteranceSource
    var latestRelation: VoiceTaskRelation
    var replacementScope: VoiceReplacementScope
    var targetApp: String?
    var forbidsSend: Bool
    var needsFreshEvidence: Bool
    var stopped: Bool
    var observedScreen: VoiceObservedScreen
    var steps: [VoiceGoalStep]

    var hasExecutedOrUnknownWork: Bool {
        steps.contains { !$0.isReadOnly && $0.outcome.blocksRepeat }
    }

    var hasUnknownStep: Bool {
        steps.contains { $0.outcome == .unknown }
    }

    var hasRunningStep: Bool {
        steps.contains { $0.outcome == .running }
    }

    var hasActiveDraft: Bool {
        steps.contains { $0.createsDraft && $0.outcome.blocksRepeat }
    }

    func openedAppStep(for app: String) -> VoiceGoalStep? {
        steps.last { $0.opensApp == app && $0.outcome.blocksRepeat }
    }
}

enum VoiceTaskRelationClassifier {
    private static let backchannels: Set<String> = [
        "嗯", "哦", "好的", "好", "行", "明白", "知道了", "好吧", "可以",
        "uh-huh", "mm-hmm", "ok", "okay", "got it", "alright", "sure",
    ]
    private static let pleasantries: Set<String> = [
        "你好", "嗨", "哈喽", "谢谢", "谢谢你", "多谢", "不客气", "没关系", "没事", "哈哈", "哈哈哈", "早安", "晚安",
        "hello", "hi", "hey", "thanks", "thank you", "you're welcome", "nice", "cool", "good morning", "good night",
    ]
    private static let chitchatPhrases = [
        "你叫什么名字", "你是谁", "讲个笑话", "今天心情", "聊聊天",
        "how are you", "who are you", "tell me a joke", "what is your name",
    ]
    private static let stopPhrases: Set<String> = [
        "停", "停止", "停一下", "别动", "别做了", "算了", "取消", "取消任务", "不要做了", "不用做了",
        "stop", "cancel", "cancel that", "never mind", "abort", "stop doing that",
    ]
    private static let continuePhrases: Set<String> = [
        "继续", "繼續", "接着", "接著", "接着做", "继续做", "继续吧", "往下做", "恢复", "恢復",
        "continue", "resume", "keep going", "go on", "carry on", "proceed",
    ]
    private static let literalDictationPrefixes = [
        "在备忘录输入", "输入", "打字", "写上", "把", "type ", "enter ", "write ",
    ]
    private static let forbidSendCues = [
        "先别发", "先别发送", "别发", "别发送", "不要发", "不要发送", "先不发", "不发送", "先不发送",
        "先别把", "别把这条消息发", "先存草稿", "只保存草稿", "别提交", "不要提交",
        "don't send", "do not send", "hold off on sending", "don't submit", "do not submit", "save as draft",
    ]
    private static let allowSendCues = [
        "现在发", "可以发", "发出去吧", "现在发送", "可以发送",
        "send it now", "go ahead and send", "you can send",
    ]
    private static let wholeGoalReplaceCues = [
        "不用备忘录了", "别用备忘录了", "换个任务", "全部重写", "从头来", "重来", "不要写备忘录了",
        "start over", "replace the whole", "forget notes", "forget that", "instead, open", "switch to ",
    ]
    private static let remainingStepsReplaceCues = [
        "后面的步骤改成", "后面改成", "剩下的改成", "接下来改成",
        "for the remaining steps", "replace the remaining",
    ]
    private static let reviseCues = [
        "改成", "改为", "改一下", "改做", "换成", "换为", "修改", "更正", "改写", "改掉",
        "不对", "写错了", "说错了", "应该是", "其实", "不是",
        "change it to", "change to", "make it", "update to", "update it to", "actually", "instead of", "fix it to", "correction",
    ]
    private static let supplementCues = [
        "再加", "加上", "补上", "补充", "顺便加", "另外加", "也写上",
        "also add", "add to it", "and also", "append ",
    ]

    static func classify(text: String, source: VoiceUtteranceSource, activeGoal: VoiceGoal?) -> VoiceUtteranceAssessment {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.authorizesDeviceWork, !trimmed.isEmpty else {
            return VoiceUtteranceAssessment(
                relation: .chitchat, goalID: nil, revision: nil, baseRevision: nil,
                replacementScope: .none, needsFreshEvidence: false, forbidsSend: false, allowsSend: false
            )
        }

        let normalized = normalize(trimmed)
        let clauses = splitClauses(normalized)
        let forbidsSendCue = containsAny(normalized, forbidSendCues)
        let allowsSendCue = !forbidsSendCue && containsAny(normalized, allowSendCues)
        let isLiteralDictation = literalDictationPrefixes.contains(where: { normalized.hasPrefix($0) })
            && (normalized.contains("停") || normalized.contains("stop"))

        if !isLiteralDictation, isStandaloneStop(clauses: clauses, normalized: normalized) {
            return VoiceUtteranceAssessment(
                relation: .stop, goalID: activeGoal?.id, revision: activeGoal?.revision, baseRevision: activeGoal?.revision,
                replacementScope: .none, needsFreshEvidence: false, forbidsSend: activeGoal?.forbidsSend ?? false, allowsSend: false
            )
        }

        if isChitchat(clauses: clauses, normalized: normalized) {
            return VoiceUtteranceAssessment(
                relation: .chitchat, goalID: activeGoal?.id, revision: activeGoal?.revision, baseRevision: activeGoal?.revision,
                replacementScope: .none, needsFreshEvidence: false, forbidsSend: activeGoal?.forbidsSend ?? false, allowsSend: false
            )
        }

        if let active = activeGoal, !active.stopped {
            if continuePhrases.contains(normalized) {
                return VoiceUtteranceAssessment(
                    relation: .continueTask, goalID: active.id, revision: active.revision, baseRevision: active.revision,
                    replacementScope: .none, needsFreshEvidence: active.needsFreshEvidence || active.hasUnknownStep,
                    forbidsSend: active.forbidsSend, allowsSend: false
                )
            }

            if let replaceScope = replacementScopeIfReplace(normalized: normalized, active: active) {
                return VoiceUtteranceAssessment(
                    relation: .replace, goalID: active.id, revision: active.revision + 1, baseRevision: active.revision,
                    replacementScope: replaceScope, needsFreshEvidence: active.hasExecutedOrUnknownWork,
                    forbidsSend: forbidsSendCue || (allowsSendCue ? false : active.forbidsSend),
                    allowsSend: allowsSendCue
                )
            }

            let hasContentRevision = containsAny(normalized, reviseCues) || containsAny(normalized, supplementCues)
            if hasContentRevision || forbidsSendCue || allowsSendCue {
                let scope: VoiceReplacementScope = hasContentRevision ? .contentAndConstraints : .constraintsOnly
                let needsEvidence = hasContentRevision
                    ? active.hasExecutedOrUnknownWork
                    : (active.needsFreshEvidence || active.hasUnknownStep)
                return VoiceUtteranceAssessment(
                    relation: .supplementOrRevise, goalID: active.id, revision: active.revision + 1, baseRevision: active.revision,
                    replacementScope: scope, needsFreshEvidence: needsEvidence,
                    forbidsSend: forbidsSendCue || (allowsSendCue ? false : active.forbidsSend),
                    allowsSend: allowsSendCue
                )
            }
        }

        return VoiceUtteranceAssessment(
            relation: .independentNewTask, goalID: nil, revision: 1, baseRevision: nil,
            replacementScope: .none, needsFreshEvidence: false, forbidsSend: forbidsSendCue, allowsSend: allowsSendCue
        )
    }

    private static func replacementScopeIfReplace(normalized: String, active: VoiceGoal) -> VoiceReplacementScope? {
        if containsAny(normalized, remainingStepsReplaceCues) { return .remainingSteps }
        if containsAny(normalized, wholeGoalReplaceCues) { return .wholeGoal }
        if let namedApp = VoiceAppIdentity.detectApp(in: normalized),
           let activeApp = active.targetApp, namedApp != activeApp,
           (normalized.contains("不用") || normalized.contains("别用") || normalized.contains("不要")
            || normalized.contains("改用") || normalized.contains("换成") || normalized.contains("instead")) {
            return .wholeGoal
        }
        return nil
    }

    private static func isStandaloneStop(clauses: [String], normalized: String) -> Bool {
        if stopPhrases.contains(normalized) { return true }
        guard let first = clauses.first, stopPhrases.contains(first) else { return false }
        return clauses.dropFirst().allSatisfy { part in stopPhrases.contains(where: { $0.hasPrefix(part) }) }
    }

    private static func isChitchat(clauses: [String], normalized: String) -> Bool {
        if pleasantries.contains(normalized) || backchannels.contains(normalized) { return true }
        if !clauses.isEmpty, clauses.allSatisfy({ backchannels.contains($0) || pleasantries.contains($0) }) { return true }
        return containsAny(normalized, chitchatPhrases)
    }

    private static func normalize(_ text: String) -> String {
        var result = text.lowercased().precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let last = result.last, ".!?。！？,，;；".contains(last) {
            result.removeLast()
        }
        return result
    }

    private static func splitClauses(_ text: String) -> [String] {
        text.split { ",，。.!！?？;；".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        for phrase in phrases {
            if phrase.unicodeScalars.contains(where: { $0.value > 0x2E80 }) {
                if text.contains(phrase) { return true }
            } else if VoiceAppIdentity.containsWholeWord(text, phrase.trimmingCharacters(in: .whitespaces)) {
                return true
            }
        }
        return false
    }
}

enum VoiceExecutionDecision: Equatable, Sendable {
    enum DenialCode: String, Equatable, Sendable {
        case unauthorizedSource = "unauthorized_source"
        case staleRevision = "stale_revision"
        case forbiddenByConstraint = "forbidden_by_constraint"
        case unknownStepRepeat = "unknown_step_repeat"
        case duplicateDraftCreation = "duplicate_draft_creation"
        case duplicateStepInGoal = "duplicate_step_in_goal"
        case needsFreshEvidence = "needs_fresh_evidence"
    }

    case allow(goalID: VoiceGoalID, revision: Int)
    case deny(reason: String, code: DenialCode, goalID: VoiceGoalID?, revision: Int?)
}

enum VoiceExecutionGate {
    static func evaluate(proposal: VoiceToolProposal, goal: VoiceGoal, currentSession: Int) -> VoiceExecutionDecision {
        if !proposal.source.authorizesDeviceWork {
            return .deny(
                reason: "Blocked: source \(proposal.source.rawValue) cannot authorize phone input.",
                code: .unauthorizedSource, goalID: goal.id, revision: goal.revision
            )
        }
        if proposal.isControlCancel || proposal.isReadOnly {
            return .allow(goalID: goal.id, revision: goal.revision)
        }
        if let proposedRevision = proposal.goalRevision, proposedRevision < goal.revision,
           goal.replacementScope != .constraintsOnly {
            return .deny(
                reason: "Blocked: goal \(goal.id) moved to r\(goal.revision). Do not run steps from r\(proposedRevision).",
                code: .staleRevision, goalID: goal.id, revision: goal.revision
            )
        }
        if goal.forbidsSend, proposal.attemptsSendOrCommit(using: goal.observedScreen) {
            return .deny(
                reason: "Blocked: goal \(goal.id) r\(goal.revision) forbids sending or submitting. Keep the draft unsent.",
                code: .forbiddenByConstraint, goalID: goal.id, revision: goal.revision
            )
        }

        let createsDraft = proposal.createsDraft(using: goal.observedScreen)

        if let unknownPrior = matchingUnknownStep(proposal: proposal, createsDraft: createsDraft, in: goal) {
            return .deny(
                reason: "Blocked: step \(unknownPrior.callID) in goal \(goal.id) has an unknown outcome and may already have run. Call look first to verify the screen instead of repeating it.",
                code: .unknownStepRepeat, goalID: goal.id, revision: goal.revision
            )
        }

        if createsDraft, goal.hasActiveDraft, goal.replacementScope != .wholeGoal {
            let priorID = goal.steps.last(where: { $0.createsDraft && $0.outcome.blocksRepeat })?.callID ?? "previous"
            return .deny(
                reason: "Blocked: goal \(goal.id) already has an active draft from \(priorID). Update the existing draft instead of creating another.",
                code: .duplicateDraftCreation, goalID: goal.id, revision: goal.revision
            )
        }

        if let app = proposal.opensAppOnly, goal.replacementScope != .wholeGoal,
           let priorOpen = goal.openedAppStep(for: app) {
            let stillInSameApp = goal.observedScreen.app == nil || goal.observedScreen.app == app
            if stillInSameApp && (goal.revision > priorOpen.revision || currentSession != priorOpen.session) {
                return .deny(
                    reason: "Blocked: goal \(goal.id) already opened \(app) in \(priorOpen.callID). Do not reopen it; continue on the current screen.",
                    code: .duplicateStepInGoal, goalID: goal.id, revision: goal.revision
                )
            }
        }

        if !proposal.isPureNavigation,
           let duplicate = goal.steps.last(where: {
               !$0.isReadOnly && !$0.isPureNavigation && $0.outcome.blocksRepeat
                   && $0.fingerprint == proposal.canonicalFingerprint
                   && ($0.revision < goal.revision || $0.session != currentSession)
           }) {
            return .deny(
                reason: "Blocked: step \(duplicate.callID) in goal \(goal.id) already ran with the same action. Do not repeat it.",
                code: .duplicateStepInGoal, goalID: goal.id, revision: goal.revision
            )
        }

        if goal.needsFreshEvidence {
            return .deny(
                reason: "Blocked: goal \(goal.id) r\(goal.revision) needs fresh screen evidence before further input. Call look first.",
                code: .needsFreshEvidence, goalID: goal.id, revision: goal.revision
            )
        }

        return .allow(goalID: goal.id, revision: goal.revision)
    }

    private static func matchingUnknownStep(proposal: VoiceToolProposal, createsDraft: Bool, in goal: VoiceGoal) -> VoiceGoalStep? {
        for step in goal.steps.reversed() where step.outcome == .unknown {
            if createsDraft && step.createsDraft { return step }
            if let app = proposal.opensAppOnly, step.opensApp == app { return step }
            if !proposal.isPureNavigation, step.fingerprint == proposal.canonicalFingerprint { return step }
        }
        return nil
    }
}

struct VoiceGoalTracker: Equatable, Sendable {
    private var nextGoalNumber = 1
    private var nextUtteranceNumber = 1
    private(set) var activeGoal: VoiceGoal?
    private(set) var history: [VoiceGoal] = []
    private(set) var utterances: [VoiceUtteranceRecord] = []

    private struct UtteranceBinding: Equatable, Sendable {
        let goalID: VoiceGoalID?
        let revision: Int?
        let source: VoiceUtteranceSource
    }

    private struct RecoveryReceipt: Equatable, Sendable {
        let goalID: VoiceGoalID
        let revision: Int
        let session: Int
    }

    private var bindingByItem: [String: UtteranceBinding] = [:]
    private var bindingByDelegation: [String: UtteranceBinding] = [:]
    private var bindingByResponse: [String: UtteranceBinding] = [:]
    private var goalIDByCall: [String: VoiceGoalID] = [:]
    private var provisionalGoalByItem: [String: VoiceGoalID] = [:]
    private var latestBinding: UtteranceBinding?
    private var recoverySent: RecoveryReceipt?

    mutating func ingestCompleteUtterance(
        text: String,
        itemID: String?,
        delegationID: String?,
        source: VoiceUtteranceSource,
        at date: Date
    ) -> VoiceUtteranceRecord {
        let utteranceID = itemID ?? delegationID ?? nextUtteranceID()

        if let itemID, let provisionalID = provisionalGoalByItem.removeValue(forKey: itemID),
           var active = activeGoal, active.id == provisionalID {
            let assessment = VoiceTaskRelationClassifier.classify(text: text, source: source, activeGoal: nil)
            active.originalUtterance = text
            active.latestUtterance = text
            active.source = source
            active.targetApp = active.targetApp ?? VoiceAppIdentity.detectApp(in: text)
            active.forbidsSend = active.forbidsSend || assessment.forbidsSend
            activeGoal = active
            let binding = UtteranceBinding(goalID: active.id, revision: active.revision, source: source)
            recordBinding(binding, itemID: itemID, delegationID: delegationID)
            let record = VoiceUtteranceRecord(
                id: utteranceID, source: source, text: text, relation: assessment.relation,
                goalID: active.id, revision: active.revision, baseRevision: nil,
                replacementScope: .none, needsFreshEvidence: active.needsFreshEvidence, receivedAt: date
            )
            utterances.append(record)
            return record
        }

        let assessment = VoiceTaskRelationClassifier.classify(text: text, source: source, activeGoal: activeGoal)
        let record: VoiceUtteranceRecord

        switch assessment.relation {
        case .chitchat:
            if !source.authorizesDeviceWork {
                let binding = UtteranceBinding(goalID: nil, revision: nil, source: source)
                recordBinding(binding, itemID: itemID, delegationID: delegationID)
            }
            record = VoiceUtteranceRecord(
                id: utteranceID, source: source, text: text, relation: .chitchat,
                goalID: assessment.goalID, revision: assessment.revision, baseRevision: assessment.baseRevision,
                replacementScope: .none, needsFreshEvidence: false, receivedAt: date
            )

        case .stop:
            if var active = activeGoal {
                active.stopped = true
                active.latestRelation = .stop
                activeGoal = active
            }
            record = VoiceUtteranceRecord(
                id: utteranceID, source: source, text: text, relation: .stop,
                goalID: activeGoal?.id, revision: activeGoal?.revision, baseRevision: activeGoal?.revision,
                replacementScope: .none, needsFreshEvidence: false, receivedAt: date
            )

        case .continueTask:
            if var active = activeGoal {
                active.latestRelation = .continueTask
                active.needsFreshEvidence = active.needsFreshEvidence || assessment.needsFreshEvidence
                activeGoal = active
                let binding = UtteranceBinding(goalID: active.id, revision: active.revision, source: source)
                recordBinding(binding, itemID: itemID, delegationID: delegationID)
            }
            record = VoiceUtteranceRecord(
                id: utteranceID, source: source, text: text, relation: .continueTask,
                goalID: activeGoal?.id, revision: activeGoal?.revision, baseRevision: activeGoal?.revision,
                replacementScope: .none, needsFreshEvidence: activeGoal?.needsFreshEvidence ?? false, receivedAt: date
            )

        case .supplementOrRevise, .replace:
            if var active = activeGoal {
                let previous = active.revision
                active.baseRevision = previous
                active.revision = previous + 1
                active.latestUtterance = text
                active.latestRelation = assessment.relation
                active.replacementScope = assessment.replacementScope
                active.forbidsSend = assessment.forbidsSend
                active.needsFreshEvidence = active.needsFreshEvidence || assessment.needsFreshEvidence
                if let detected = VoiceAppIdentity.detectApp(in: text),
                   assessment.replacementScope == .wholeGoal || active.targetApp == nil {
                    active.targetApp = detected
                }
                activeGoal = active
                let binding = UtteranceBinding(goalID: active.id, revision: active.revision, source: source)
                recordBinding(binding, itemID: itemID, delegationID: delegationID)
                record = VoiceUtteranceRecord(
                    id: utteranceID, source: source, text: text, relation: assessment.relation,
                    goalID: active.id, revision: active.revision, baseRevision: previous,
                    replacementScope: assessment.replacementScope, needsFreshEvidence: active.needsFreshEvidence, receivedAt: date
                )
            } else {
                record = createNewGoal(
                    utteranceID: utteranceID, text: text, source: source,
                    forbidsSend: assessment.forbidsSend, itemID: itemID, delegationID: delegationID, at: date
                )
            }

        case .independentNewTask:
            record = createNewGoal(
                utteranceID: utteranceID, text: text, source: source,
                forbidsSend: assessment.forbidsSend, itemID: itemID, delegationID: delegationID, at: date
            )
        }

        utterances.append(record)
        return record
    }

    mutating func bindResponse(_ responseID: String, itemID: String?) {
        if let itemID, let binding = bindingByItem[itemID] {
            bindingByResponse[responseID] = binding
        } else if let latestBinding {
            bindingByResponse[responseID] = latestBinding
        }
    }

    mutating func resolveBinding(
        delegationID: String?,
        responseID: String?,
        speechItemID: String?,
        defaultSource: VoiceUtteranceSource
    ) -> (goalID: VoiceGoalID, revision: Int, source: VoiceUtteranceSource) {
        let found = delegationID.flatMap({ bindingByDelegation[$0] })
            ?? responseID.flatMap({ bindingByResponse[$0] })
            ?? speechItemID.flatMap({ bindingByItem[$0] })
            ?? latestBinding
        if let found, !found.source.authorizesDeviceWork {
            let goal = activeGoal ?? makeProvisionalGoal(itemID: speechItemID, source: found.source)
            return (goal.id, found.revision ?? goal.revision, found.source)
        }
        if let found, let goalID = found.goalID {
            return (goalID, found.revision ?? goal(for: goalID)?.revision ?? 1, found.source)
        }
        if let active = activeGoal, !active.stopped {
            return (active.id, active.revision, active.source)
        }
        let provisional = makeProvisionalGoal(itemID: speechItemID, source: defaultSource)
        return (provisional.id, provisional.revision, provisional.source)
    }

    mutating func admit(_ proposal: VoiceToolProposal, session: Int) -> VoiceExecutionDecision {
        let targetGoal: VoiceGoal
        if let goalID = proposal.goalID, let existing = goal(for: goalID) {
            targetGoal = existing
        } else if let active = activeGoal {
            targetGoal = active
        } else {
            targetGoal = makeProvisionalGoal(itemID: proposal.speechItemID, source: proposal.source)
        }

        let decision = VoiceExecutionGate.evaluate(proposal: proposal, goal: targetGoal, currentSession: session)
        guard case .allow(let goalID, let revision) = decision else { return decision }

        let createsDraft = proposal.createsDraft(using: targetGoal.observedScreen)
        let step = VoiceGoalStep(
            callID: proposal.callID,
            goalID: goalID,
            revision: revision,
            session: session,
            toolName: proposal.toolName,
            fingerprint: proposal.canonicalFingerprint,
            opensApp: proposal.opensApp,
            createsDraft: createsDraft,
            isReadOnly: proposal.isReadOnly,
            isPureNavigation: proposal.isPureNavigation,
            outcome: .running,
            summary: ""
        )
        mutateGoal(id: goalID) { goal in
            if goal.targetApp == nil, let opened = proposal.opensApp {
                goal.targetApp = opened
            }
            goal.steps.append(step)
        }
        goalIDByCall[proposal.callID] = goalID
        return decision
    }

    @discardableResult
    mutating func recordStepFinished(callID: String, state: VoiceCall.State, output: String) -> VoiceStepOutcome {
        let outcome = VoiceStepOutcome.classify(state: state, output: output)
        guard let goalID = goalIDByCall[callID] else { return outcome }
        let parsedScreen = VoiceObservedScreen.parse(output)
        mutateGoal(id: goalID) { goal in
            guard let index = goal.steps.firstIndex(where: { $0.callID == callID }) else { return }
            goal.steps[index].outcome = outcome
            goal.steps[index].summary = Self.compactSummary(output)
            if let parsedScreen {
                if let app = parsedScreen.app { goal.observedScreen.app = app }
                if !parsedScreen.elements.isEmpty { goal.observedScreen.elements = parsedScreen.elements }
            }
            if outcome == .unknown {
                goal.needsFreshEvidence = true
            } else if outcome == .succeeded, goal.steps[index].isReadOnly,
                      (goal.steps[index].toolName == "look" || goal.steps[index].toolName == "read_screen") {
                goal.needsFreshEvidence = false
            }
        }
        return outcome
    }

    mutating func recordStepCancelled(callID: String) {
        guard let goalID = goalIDByCall[callID] else { return }
        mutateGoal(id: goalID) { goal in
            guard let index = goal.steps.firstIndex(where: { $0.callID == callID }),
                  goal.steps[index].outcome == .running else { return }
            goal.steps[index].outcome = .blocked
        }
    }

    mutating func markActiveGoalStopped() {
        activeGoal?.stopped = true
        activeGoal?.latestRelation = .stop
    }

    func revisionNote(for record: VoiceUtteranceRecord) -> String? {
        guard record.relation == .supplementOrRevise || record.relation == .replace,
              let goalID = record.goalID, let goal = goal(for: goalID),
              goal.hasExecutedOrUnknownWork || goal.forbidsSend else { return nil }
        return formatGoalNote(prefix: "Goal update", goal: goal)
    }

    mutating func recoveryNote(forSession session: Int) -> String? {
        guard let goal = activeGoal, !goal.stopped,
              goal.revision > 1 || goal.hasUnknownStep || goal.forbidsSend else { return nil }
        if let sent = recoverySent, sent.goalID == goal.id, sent.revision == goal.revision, sent.session == session {
            return nil
        }
        recoverySent = RecoveryReceipt(goalID: goal.id, revision: goal.revision, session: session)
        return formatGoalNote(prefix: "Reconnect goal recovery", goal: goal)
    }

    mutating func sessionEnded() {
        bindingByDelegation.removeAll()
        bindingByResponse.removeAll()
        latestBinding = nil
    }

    mutating func conversationStopped() {
        sessionEnded()
        bindingByItem.removeAll()
        provisionalGoalByItem.removeAll()
        if let active = activeGoal, !active.hasRunningStep, !active.hasUnknownStep {
            history.append(active)
            activeGoal = nil
        }
    }

    func goal(for id: VoiceGoalID) -> VoiceGoal? {
        if activeGoal?.id == id { return activeGoal }
        return history.last { $0.id == id }
    }

    private mutating func createNewGoal(
        utteranceID: String,
        text: String,
        source: VoiceUtteranceSource,
        forbidsSend: Bool,
        itemID: String?,
        delegationID: String?,
        at date: Date
    ) -> VoiceUtteranceRecord {
        if let active = activeGoal { history.append(active) }
        let id = nextGoalID()
        let goal = VoiceGoal(
            id: id,
            revision: 1,
            baseRevision: nil,
            originalUtterance: text,
            latestUtterance: text,
            source: source,
            latestRelation: .independentNewTask,
            replacementScope: .none,
            targetApp: VoiceAppIdentity.detectApp(in: text),
            forbidsSend: forbidsSend,
            needsFreshEvidence: false,
            stopped: false,
            observedScreen: VoiceObservedScreen(),
            steps: []
        )
        activeGoal = goal
        let binding = UtteranceBinding(goalID: id, revision: 1, source: source)
        recordBinding(binding, itemID: itemID, delegationID: delegationID)
        return VoiceUtteranceRecord(
            id: utteranceID, source: source, text: text, relation: .independentNewTask,
            goalID: id, revision: 1, baseRevision: nil, replacementScope: .none,
            needsFreshEvidence: false, receivedAt: date
        )
    }

    private mutating func makeProvisionalGoal(itemID: String?, source: VoiceUtteranceSource) -> VoiceGoal {
        if let active = activeGoal { history.append(active) }
        let id = nextGoalID()
        let goal = VoiceGoal(
            id: id,
            revision: 1,
            baseRevision: nil,
            originalUtterance: "",
            latestUtterance: "",
            source: source,
            latestRelation: .independentNewTask,
            replacementScope: .none,
            targetApp: nil,
            forbidsSend: false,
            needsFreshEvidence: false,
            stopped: false,
            observedScreen: VoiceObservedScreen(),
            steps: []
        )
        activeGoal = goal
        if let itemID { provisionalGoalByItem[itemID] = id }
        return goal
    }

    private mutating func recordBinding(_ binding: UtteranceBinding, itemID: String?, delegationID: String?) {
        if let itemID { bindingByItem[itemID] = binding }
        if let delegationID { bindingByDelegation[delegationID] = binding }
        latestBinding = binding
    }

    private mutating func mutateGoal(id: VoiceGoalID, _ body: (inout VoiceGoal) -> Void) {
        if var active = activeGoal, active.id == id {
            body(&active)
            activeGoal = active
            return
        }
        if let index = history.lastIndex(where: { $0.id == id }) {
            body(&history[index])
        }
    }

    private mutating func nextGoalID() -> VoiceGoalID {
        let id = VoiceGoalID(rawValue: "g\(nextGoalNumber)")
        nextGoalNumber += 1
        return id
    }

    private mutating func nextUtteranceID() -> String {
        let id = "u\(nextUtteranceNumber)"
        nextUtteranceNumber += 1
        return id
    }

    private func formatGoalNote(prefix: String, goal: VoiceGoal) -> String {
        let kept = goal.steps.filter { !$0.isReadOnly && $0.outcome.blocksRepeat }
            .suffix(4)
            .map { "\($0.callID):\($0.toolName):\($0.outcome.rawValue)" }
            .joined(separator: ",")
        var parts = [
            "\(prefix) \(goal.id) r\(goal.revision) (\(goal.latestRelation.rawValue), scope=\(goal.replacementScope.rawValue))",
        ]
        if !goal.latestUtterance.isEmpty {
            parts.append("latest=\"\(String(goal.latestUtterance.prefix(48)))\"")
        }
        if !kept.isEmpty { parts.append("keep[\(kept)]") }
        if goal.needsFreshEvidence { parts.append("call look first") }
        if goal.forbidsSend { parts.append("do not send") }
        if goal.hasActiveDraft && goal.replacementScope != .wholeGoal { parts.append("edit existing draft") }
        return parts.joined(separator: "; ") + ". Do not repeat succeeded or unknown steps."
    }

    private static func compactSummary(_ output: String) -> String {
        let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(firstLine.prefix(120))
    }
}
