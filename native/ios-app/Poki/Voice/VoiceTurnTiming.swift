import Foundation

/// The voice entry path chosen when a talk starts, matching the priority order:
/// enabled OpenAI or compatible custom account, Mac voice bridge, then on-device dictation
/// (routed through ChatGPT Responses when ChatGPT is the active chat account).
enum VoiceEntryRoute: String, Equatable, Sendable {
    case directEphemeralCredential = "direct_ephemeral_credential"
    case voiceBridge = "voice_bridge"
    case dictationChatTTS = "dictation_chat_tts"
    case chatgptResponses = "chatgpt_responses"
    case rehearsal = "rehearsal"

    var voiceHost: VoiceHost {
        self == .voiceBridge ? .voiceBridge : .phoneDirect
    }

    static func resolve(directAccount: VoiceAccount?, hasDirectKey: Bool, hasBridge: Bool,
                        canDictate: Bool, microphone: Bool, chatProvider: ModelProvider,
                        chatGPTSignedIn: Bool, rehearsing: Bool) -> VoiceEntryRoute? {
        if rehearsing { return .rehearsal }
        if directAccount != nil, hasDirectKey { return .directEphemeralCredential }
        if hasBridge { return .voiceBridge }
        if canDictate, microphone {
            return chatProvider == .chatgpt && chatGPTSignedIn ? .chatgptResponses : .dictationChatTTS
        }
        return nil
    }
}

enum VoiceHost: String, Equatable, Sendable {
    case phoneDirect = "phone_direct"
    case voiceBridge = "voice_bridge"
}

enum VoiceActionHost: String, Equatable, Sendable {
    case none
    case phoneLocal = "phone_local"
    case macTools = "mac_tools"
    case mixed
}

enum VoiceObservationSource: String, Equatable, Sendable {
    case none
    case phoneTreeAndScreenshot = "phone_tree_and_screenshot"
    case phoneTreeAndLiveVision = "phone_tree_and_live_vision"
    case phoneAccessibilityTree = "phone_accessibility_tree"
    case phoneScreenshotOCR = "phone_screenshot_ocr"
    case phoneHostScreenshot = "phone_host_screenshot"
    case phoneStaleScreenshot = "phone_stale_screenshot"
    case phoneDeviceInfo = "phone_device_info"
    case phoneToolOutput = "phone_tool_output"
    case phoneChatLoop = "phone_chat_loop"
    case macMCPAccessibility = "mac_mcp_accessibility"
    case macMCPOCR = "mac_mcp_ocr"
    case macMCPActionReadback = "mac_mcp_action_readback"
    case macMCPAction = "mac_mcp_action"
    case macMCPDeviceInfo = "mac_mcp_device_info"
    case independentObserver = "independent_observer"
}

enum VoiceSessionTransport: String, Equatable, Sendable {
    case realtime
    case live
    case dictation
    case responses
    case rehearsal
}

enum TurnMilestone: String, CaseIterable, Sendable {
    case said
    case heard
    case call
    case firstEffectiveAction = "first_effective_action"
    case toolDone = "tool_done"
    case targetConfirmed = "target_confirmed"
    case delivered
    case spoken
}

struct TurnMoment: Equatable, Sendable {
    let date: Date
    let uptimeMS: UInt64?

    init(date: Date, uptimeMS: UInt64? = nil) {
        self.date = date
        self.uptimeMS = uptimeMS
    }
}

struct VoiceCallTiming: Sendable {
    let actionIndex: Int
    let actionHost: VoiceActionHost
    let observationSource: VoiceObservationSource
    let dispatchMoment: TurnMoment
    let endMoment: TurnMoment
    let hostDurationMS: Int
    let bridgeMS: Int?
    let effective: Bool
    let confirmed: Bool
}

enum VoiceTurnTiming {
    static let logArea = "voice-timing"

    private static let readOnlyTools: Set<String> = ["get_ios_version", "look", "read_screen", VoiceDirect.cancelCurrentTask]
    private static let directActionTools: Set<String> = ["open_app", "open_settings", "tap_text", "go_home"]
    private static let passiveDoKeys: Set<String> = ["wait", "wait_until", "handoff"]
    private static let unconfirmedMarkers = [
        "touch effect: unconfirmed",
        "screen_changed: false",
        "not confirmed",
        "could not be confirmed",
        "is not in front",
        "screen: locked",
        "read: failed",
        "not_sent:",
        "approval_required",
        "Nothing was sent",
        "Nothing was tapped",
    ]

    static func elapsedMS(from start: TurnMoment, to end: TurnMoment) -> Int {
        if let s = start.uptimeMS, let e = end.uptimeMS {
            return e >= s ? Int(e - s) : 0
        }
        return max(0, Int(end.date.timeIntervalSince(start.date) * 1000))
    }

    static func isActionCandidate(name: String, arguments: String) -> Bool {
        if readOnlyTools.contains(name) { return false }
        if directActionTools.contains(name) { return true }
        guard name == "do" else { return false }
        guard let object = parseJSONObject(arguments), let actions = object["actions"] as? [[String: Any]] else {
            return true
        }
        if actions.isEmpty { return object["finish"] as? Bool == true }
        return actions.contains { action in
            action.keys.contains { !passiveDoKeys.contains($0) }
        }
    }

    static func didTakeEffect(name: String, arguments: String, state: VoiceCall.State, output: String,
                              checkedTap: Bool = true, bridgeEffective: Bool? = nil) -> Bool {
        if let bridgeEffective { return bridgeEffective }
        guard isActionCandidate(name: name, arguments: arguments) else { return false }
        if name == "tap_text", !checkedTap { return false }
        if output.contains("(sent,") { return true }
        if state == .failed { return false }
        if output.hasPrefix("not_sent:") || output.hasPrefix("cancelled:") || output.hasPrefix("error:") || output.hasPrefix("unknown:") {
            return false
        }
        if output.contains("Nothing was sent.") || output.contains("Nothing was tapped.") { return false }
        return true
    }

    static func observationSource(name: String, actionHost: VoiceActionHost, state: VoiceCall.State,
                                  output: String, hasScreen: Bool, usedLiveVision: Bool,
                                  bridgeSource: String? = nil) -> VoiceObservationSource {
        if let bridgeSource, let parsed = VoiceObservationSource(rawValue: bridgeSource) {
            return parsed
        }
        switch actionHost {
        case .none:
            return .none
        case .macTools:
            guard state == .done else { return .none }
            if let json = parseJSONObject(output) {
                let source = (json["post_action_observation"] as? [String: Any])?["source"] as? String ?? json["source"] as? String
                if source == "ocr" { return .macMCPOCR }
                if source == "accessibility" { return .macMCPAccessibility }
                if json["screen_change_verified"] as? Bool == true || json["foreground_verified"] as? Bool == true {
                    return .macMCPActionReadback
                }
            }
            if name == "read_screen" { return .macMCPAccessibility }
            if name == "get_ios_version" { return .macMCPDeviceInfo }
            return .macMCPAction
        case .phoneLocal, .mixed:
            if name == "get_ios_version" { return state == .done ? .phoneDeviceInfo : .none }
            if output.contains("the screenshot is the one of the read before") { return .phoneStaleScreenshot }
            if output.contains("read: failed") || output.hasPrefix("not_sent:") || output.hasPrefix("error:") {
                return .none
            }
            if usedLiveVision || output.contains("Current screen description:") { return .phoneTreeAndLiveVision }
            if output.contains("taken apart from the runner") { return .phoneHostScreenshot }
            if output.contains("read from the picture") { return .phoneScreenshotOCR }
            if hasScreen { return .phoneTreeAndScreenshot }
            if output.contains("app:") || output.contains("elements") || output.contains("screen_changed:") {
                return .phoneAccessibilityTree
            }
            if state == .done, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .phoneToolOutput
            }
            return .none
        }
    }

    static func isTargetIndependentlyConfirmed(name: String, actionHost: VoiceActionHost, state: VoiceCall.State,
                                               output: String, observationSource: VoiceObservationSource,
                                               bridgeConfirmed: Bool? = nil) -> Bool {
        if let bridgeConfirmed { return bridgeConfirmed }
        guard state == .done, observationSource != .none, observationSource != .phoneStaleScreenshot else { return false }
        if unconfirmedMarkers.contains(where: output.contains) { return false }
        if actionHost == .macTools {
            if let json = parseJSONObject(output) {
                if let change = json["screen_change"] as? String { return change == "changed" }
                if let verified = json["foreground_verified"] as? Bool { return verified }
                if name == "read_screen" { return json["elements"] is [Any] }
                if json["launched"] as? Bool == true || json["opened"] != nil { return true }
                if json["sent"] as? Bool == true { return false }
            }
            return name == "read_screen" || name == "get_ios_version"
        }
        return true
    }

    static func line(session: Int, turn: Int, at moment: TurnMoment, event: String, fields: [(String, String)]) -> String {
        let base = "session=\(session) flow=voice turn=\(turn) t_ms=\(moment.uptimeMS ?? 0) event=\(event)"
        guard !fields.isEmpty else { return base }
        return base + " " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
    }

    static func summaryFields(for clock: TurnClock) -> [(String, String)] {
        var fields: [(String, String)] = [
            ("entry_route", clock.entryRoute?.rawValue ?? "none"),
            ("voice_host", clock.voiceHost?.rawValue ?? "none"),
            ("action_host", clock.actionHost.rawValue),
            ("observation_source", clock.observationSource.rawValue),
        ]
        for milestone in TurnMilestone.allCases {
            fields.append(("\(milestone.rawValue)_ms", clock.ms(milestone).map(String.init) ?? "none"))
        }
        fields.append(("phone_local_ms", "\(clock.phoneLocalMS)"))
        fields.append(("mac_tools_ms", "\(clock.macToolsMS)"))
        fields.append(("calls", clock.callNames.isEmpty ? "none" : clock.callNames.joined(separator: ",")))
        return fields
    }

    private static func parseJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
