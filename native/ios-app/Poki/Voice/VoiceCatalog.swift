import Foundation

/// The live voice backend protocol that determines which official voices are accepted at handshake.
enum LiveVoiceRoute: String, CaseIterable, Hashable, Sendable {
    /// OpenAI Realtime API and GPT-Live (`/v1/live/sessions`, `/v1/realtime/client_secrets`),
    /// used by an OpenAI API key or an OpenAI-compatible custom endpoint.
    case realtimeAPI
    /// ChatGPT account direct live voice via `CodexVoice` (`codex-rs` realtime v3).
    case chatgpt

    var defaultVoice: LiveVoiceOption {
        switch self {
        case .realtimeAPI: .marin
        case .chatgpt: .cove
        }
    }

    var options: [LiveVoiceOption] {
        LiveVoiceOption.allCases.filter { $0.route == self }
    }

    var supportedIDs: Set<String> {
        Set(options.map(\.rawValue))
    }

    /// Stored under the `voice.` prefix so `SettingsVault` automatically backs it up in Keychain.
    var storageKey: String {
        switch self {
        case .realtimeAPI: "voice.speaker"
        case .chatgpt: "voice.speaker.chatgpt"
        }
    }
}

/// Official GPT live voice options, partitioned by the backend route that supports each voice.
enum LiveVoiceOption: String, CaseIterable, Identifiable, Hashable, Sendable {
    // OpenAI Realtime API / GPT-Live (10 official voices; marin and cedar recommended).
    case marin
    case cedar
    case alloy
    case ash
    case ballad
    case coral
    case echo
    case sage
    case shimmer
    case verse

    // ChatGPT account direct live voice (`codex-rs` v3 core catalog: 9 official ChatGPT voices).
    case cove
    case juniper
    case maple
    case spruce
    case ember
    case vale
    case breeze
    case arbor
    case sol

    var id: String { rawValue }

    var route: LiveVoiceRoute {
        switch self {
        case .marin, .cedar, .alloy, .ash, .ballad, .coral, .echo, .sage, .shimmer, .verse:
            .realtimeAPI
        case .cove, .juniper, .maple, .spruce, .ember, .vale, .breeze, .arbor, .sol:
            .chatgpt
        }
    }

    /// Localized display name (English official name; Chinese name with official English name in parentheses).
    var displayName: String {
        switch self {
        case .marin: AppLocalization.text("Marin")
        case .cedar: AppLocalization.text("Cedar")
        case .alloy: AppLocalization.text("Alloy")
        case .ash: AppLocalization.text("Ash")
        case .ballad: AppLocalization.text("Ballad")
        case .coral: AppLocalization.text("Coral")
        case .echo: AppLocalization.text("Echo")
        case .sage: AppLocalization.text("Sage")
        case .shimmer: AppLocalization.text("Shimmer")
        case .verse: AppLocalization.text("Verse")
        case .cove: AppLocalization.text("Cove")
        case .juniper: AppLocalization.text("Juniper")
        case .maple: AppLocalization.text("Maple")
        case .spruce: AppLocalization.text("Spruce")
        case .ember: AppLocalization.text("Ember")
        case .vale: AppLocalization.text("Vale")
        case .breeze: AppLocalization.text("Breeze")
        case .arbor: AppLocalization.text("Arbor")
        case .sol: AppLocalization.text("Sol")
        }
    }

    /// Localized short personality label for settings rows.
    var personality: String {
        switch self {
        case .marin: AppLocalization.text("Natural and clear")
        case .cedar: AppLocalization.text("Warm and steady")
        case .alloy: AppLocalization.text("Neutral and balanced")
        case .ash: AppLocalization.text("Calm and measured")
        case .ballad: AppLocalization.text("Melodic and expressive")
        case .coral: AppLocalization.text("Bright and energetic")
        case .echo: AppLocalization.text("Smooth and conversational")
        case .sage: AppLocalization.text("Thoughtful and composed")
        case .shimmer: AppLocalization.text("Clear and gentle")
        case .verse: AppLocalization.text("Articulate and rhythmic")
        case .cove: AppLocalization.text("Composed and direct")
        case .juniper: AppLocalization.text("Open and upbeat")
        case .maple: AppLocalization.text("Cheerful and candid")
        case .spruce: AppLocalization.text("Calm and affirming")
        case .ember: AppLocalization.text("Confident and optimistic")
        case .vale: AppLocalization.text("Bright and inquisitive")
        case .breeze: AppLocalization.text("Animated and earnest")
        case .arbor: AppLocalization.text("Easygoing and versatile")
        case .sol: AppLocalization.text("Savvy and relaxed")
        }
    }
}

/// Persists and resolves live voice selections per route, guaranteeing every handshake receives a
/// voice supported by its backend even after switching authentication methods or reading stale data.
enum VoiceCatalog {
    static func options(for route: LiveVoiceRoute) -> [LiveVoiceOption] {
        route.options
    }

    static func defaultVoice(for route: LiveVoiceRoute) -> LiveVoiceOption {
        route.defaultVoice
    }

    static func route(for account: VoiceAccount) -> LiveVoiceRoute {
        switch account {
        case .openai, .custom: .realtimeAPI
        }
    }

    static func activeRoute(in storage: PokiStorage = .live) -> LiveVoiceRoute {
        if ModelKeys.selectedProvider(in: storage) == .chatgpt, ChatGPTAccount.isSignedIn(storage: storage) {
            return .chatgpt
        }
        return .realtimeAPI
    }

    /// Parses a stored or caller-provided voice identifier for `route`, falling back to the route's
    /// default voice whenever the value is missing, unknown, or belongs to a different route.
    static func resolve(_ rawValue: String?, for route: LiveVoiceRoute) -> LiveVoiceOption {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let option = LiveVoiceOption(rawValue: trimmed),
              option.route == route else {
            return route.defaultVoice
        }
        return option
    }

    static func voice(for route: LiveVoiceRoute, in storage: PokiStorage = .live) -> LiveVoiceOption {
        resolve(storage.defaults.string(forKey: route.storageKey), for: route)
    }

    static func voice(for account: VoiceAccount, in storage: PokiStorage = .live) -> LiveVoiceOption {
        voice(for: route(for: account), in: storage)
    }

    static func activeVoice(in storage: PokiStorage = .live) -> LiveVoiceOption {
        voice(for: activeRoute(in: storage), in: storage)
    }

    static func setVoice(_ option: LiveVoiceOption, for route: LiveVoiceRoute, in storage: PokiStorage = .live) {
        let resolved = resolve(option.rawValue, for: route)
        storage.defaults.set(resolved.rawValue, forKey: route.storageKey)
        ModelKeys.saved += 1
    }

    static func setVoice(_ option: LiveVoiceOption, for account: VoiceAccount, in storage: PokiStorage = .live) {
        setVoice(option, for: route(for: account), in: storage)
    }
}
