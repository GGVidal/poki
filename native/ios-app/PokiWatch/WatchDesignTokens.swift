import SwiftUI

/// Exact visual tokens extracted from Paper artboards W01-W16 (screen frame 204x248 pt, 46mm Watch).
enum WatchDesignTokens {
    // MARK: - Colors

    static let screenBackground = Color.black
    static let avatarBackdropNeutral = Color(hex: 0x161922)
    static let avatarBackdropPokiBlue = Color(hex: 0x0077FD, opacity: 0x38 / 255.0)
    static let avatarBackdropSkyBlue = Color(hex: 0x5AA7FF, opacity: 0x2E / 255.0)
    static let avatarBackdropActingBlue = Color(hex: 0x5AA7FF, opacity: 0x29 / 255.0)
    static let avatarBackdropWhite = Color.white.opacity(0x1A / 255.0)
    static let avatarBackdropMuted = Color(hex: 0xB8B8C0, opacity: 0x1A / 255.0)

    static let ringSkyBlue = Color(hex: 0x5AA7FF)
    static let ringPokiBlue = Color(hex: 0x0077FD)
    static let ringThinkingWhite = Color.white.opacity(0x94 / 255.0)
    static let ringMutedGray = Color(hex: 0xB8B8C0, opacity: 0x94 / 255.0)

    static let statusGreen = Color(hex: 0x30D158)
    static let statusGreenPill = Color(hex: 0x30D158, opacity: 0x38 / 255.0)
    static let statusOrange = Color(hex: 0xFF9F0A)
    static let statusRed = Color(hex: 0xFF453A)
    static let statusRedText = Color(hex: 0xFF5A50)
    static let statusPokiLabel = Color.white.opacity(0xE0 / 255.0)

    static let titleWhite = Color.white
    static let titleRed = Color(hex: 0xFF6961)
    static let titleMuted = Color(hex: 0xE5E7EB)

    static let subtitleDefault = Color(hex: 0xEBEBF5, opacity: 0xAD / 255.0)
    static let subtitleIdle = Color(hex: 0xC8D0DE)
    static let hintMuted = Color(hex: 0x8E95A6)
    static let hintSecondary = Color(hex: 0x8A8E99)

    static let pillNeutralFill = Color.white.opacity(0x29 / 255.0)
    static let pillRedFill = Color(hex: 0xFF453A, opacity: 0x3D / 255.0)
    static let pillBlueFill = Color(hex: 0x0077FD)
    static let badgeMutedFill = Color(hex: 0x2C2E36)

    static let cardFill = Color(hex: 0x1A1D26)
    static let cardBodyText = Color(hex: 0xD4D8E2)
    static let checkmarkGray = Color(hex: 0xB8B8C0)

    // MARK: - Dimensions (from 204x248 screen container)

    static let screenHorizontalPadding: CGFloat = 15
    static let screenBottomPadding: CGFloat = 12
    static let statusDotSize: CGFloat = 6
    static let statusDotGap: CGFloat = 5
    static let avatarSize: CGFloat = 84
    static let avatarRingWidth: CGFloat = 2
    static let badgeSize: CGFloat = 26
    static let badgeBorderWidth: CGFloat = 3
    static let badgeOffset: CGFloat = 2
    static let indicatorHeight: CGFloat = 20
    static let bottomBarHeight: CGFloat = 34
    static let pillCornerRadius: CGFloat = 17
    static let pillButtonGap: CGFloat = 8
    static let resultCardCornerRadius: CGFloat = 14
    static let resultCardPadding: CGFloat = 12
    static let endedBottomSpacerHeight: CGFloat = 14

    // MARK: - Typography

    static let topBarFont = Font.system(size: 12.5, weight: .semibold)
    static let titleFont = Font.system(size: 16, weight: .semibold)
    static let subtitleFont = Font.system(size: 11.5, weight: .regular)
    static let hintFont = Font.system(size: 11.5, weight: .medium)
    static let buttonFont = Font.system(size: 12.5, weight: .semibold)
    static let stepBadgeFont = Font.system(size: 13.5, weight: .bold, design: .monospaced)
    static let resultHeadlineFont = Font.system(size: 14, weight: .semibold)
    static let resultBodyFont = Font.system(size: 11.5, weight: .regular)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

enum WatchTopStatusKind: Equatable {
    case connected
    case attention
    case disconnected
}

enum WatchCornerBadgeKind: Equatable {
    case error
    case setup
    case muted
    case locked
}

enum WatchDynamicIndicatorKind: Equatable {
    case connectingDots
    case thinkingDots
    case listeningWave
    case speakingWave
    case stepBadge(String)
    case endedCheckmark
}

struct WatchBearArtSpec: Equatable {
    let assetName: String
    let imageSize: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let opacity: Double
    let backdrop: Color
    let ringColor: Color?
    let badge: WatchCornerBadgeKind?
}

/// Maps live WatchVoiceModel state to Paper artboards W02-W16 without altering the wire protocol.
enum WatchScreenMode: Equatable {
    case unavailable       // W02
    case needsSetup        // W03
    case idle              // W04
    case connecting        // W05
    case listening         // W06
    case thinking          // W07
    case acting(step: String, badge: String?) // W08
    case speaking          // W09
    case muted             // W10
    case ending            // W12 (transitional ending)
    case ended             // W12 (local 3s ended state)
    case waking            // W14 (waking phone on start)
    case locked            // W15 (requiresForeground)
    case failed            // W16 (failed / phone Poki not running)

    static func resolve(
        state: WatchVoiceCallState,
        isMuted: Bool,
        currentStep: String?,
        requiresForeground: Bool,
        isStartingCall: Bool,
        showingEndedScreen: Bool,
        hasTransportError: Bool
    ) -> WatchScreenMode {
        if state == .ending {
            return .ending
        }
        if state.isActiveCall {
            if isMuted || state == .muted {
                return .muted
            }
            if state == .connecting {
                return .connecting
            }
            if state == .speaking {
                return .speaking
            }
            if let step = currentStep?.trimmingCharacters(in: .whitespacesAndNewlines), !step.isEmpty {
                let parsed = parseStep(step)
                return .acting(step: parsed.subtitle, badge: parsed.badge)
            }
            if state == .thinking {
                return .thinking
            }
            return .listening
        }
        if isStartingCall {
            return .waking
        }
        if requiresForeground {
            return .locked
        }
        if state == .needsSetup {
            return .needsSetup
        }
        if state == .failed {
            return .failed
        }
        if state == .unavailable {
            return hasTransportError ? .failed : .unavailable
        }
        if showingEndedScreen {
            return .ended
        }
        return .idle
    }

    /// Extracts an optional numeric step ratio like "3/4" ONLY when the incoming step text contains one.
    static func parseStep(_ raw: String) -> (badge: String?, subtitle: String) {
        let pattern = #"(?:^|\s)(\d{1,2}/\d{1,2})(?:\s|$)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let badgeRange = Range(match.range(at: 1), in: raw) {
            let badge = String(raw[badgeRange])
            let stripped = raw.replacingCharacters(in: badgeRange, with: "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            return (badge, stripped.isEmpty ? raw : stripped)
        }
        return (nil, raw)
    }

    var topStatus: WatchTopStatusKind {
        switch self {
        case .unavailable, .failed:
            .disconnected
        case .needsSetup, .locked:
            .attention
        case .idle, .connecting, .listening, .thinking, .acting, .speaking, .muted, .ending, .ended, .waking:
            .connected
        }
    }

    var bearArt: WatchBearArtSpec {
        switch self {
        case .unavailable, .failed:
            WatchBearArtSpec(
                assetName: "WatchBear-tripped",
                imageSize: 86,
                offsetX: 5,
                offsetY: -1,
                opacity: 1.0,
                backdrop: WatchDesignTokens.avatarBackdropNeutral,
                ringColor: nil,
                badge: .error
            )
        case .needsSetup:
            WatchBearArtSpec(
                assetName: "WatchBear-needs",
                imageSize: 86,
                offsetX: 3,
                offsetY: -1,
                opacity: 1.0,
                backdrop: WatchDesignTokens.avatarBackdropNeutral,
                ringColor: nil,
                badge: .setup
            )
        case .idle:
            WatchBearArtSpec(
                assetName: "WatchBear-ready",
                imageSize: 78,
                offsetX: 1,
                offsetY: 3,
                opacity: 1.0,
                backdrop: WatchDesignTokens.avatarBackdropPokiBlue,
                ringColor: WatchDesignTokens.ringSkyBlue,
                badge: nil
            )
        case .connecting, .waking:
            WatchBearArtSpec(
                assetName: "WatchBear-needs",
                imageSize: 86,
                offsetX: 3,
                offsetY: -1,
                opacity: 1.0,
                backdrop: WatchDesignTokens.avatarBackdropNeutral,
                ringColor: nil,
                badge: nil
            )
        case .listening:
            WatchBearArtSpec(
                assetName: "WatchBear-listening",
                imageSize: 78,
                offsetX: 2,
                offsetY: 3,
                opacity: 1.0,
                backdrop: WatchDesignTokens.avatarBackdropSkyBlue,
                ringColor: WatchDesignTokens.ringSkyBlue,
                badge: nil
            )
        case .thinking:
            WatchBearArtSpec(
                assetName: "WatchBear-thinking",
                imageSize: 78,
                offsetX: 1,
                offsetY: 3,
                opacity: 1.0,
                backdrop: WatchDesignTokens.avatarBackdropWhite,
                ringColor: WatchDesignTokens.ringThinkingWhite,
                badge: nil
            )
        case .acting:
            WatchBearArtSpec(
                assetName: "WatchBear-phone",
                imageSize: 78,
                offsetX: 2,
                offsetY: 3,
                opacity: 1.0,
                backdrop: WatchDesignTokens.avatarBackdropActingBlue,
                ringColor: WatchDesignTokens.ringSkyBlue,
                badge: nil
            )
        case .speaking:
            WatchBearArtSpec(
                assetName: "WatchBear-speaking",
                imageSize: 78,
                offsetX: 0,
                offsetY: 3,
                opacity: 1.0,
                backdrop: WatchDesignTokens.avatarBackdropPokiBlue,
                ringColor: WatchDesignTokens.ringPokiBlue,
                badge: nil
            )
        case .muted:
            WatchBearArtSpec(
                assetName: "WatchBear-ready",
                imageSize: 78,
                offsetX: 1,
                offsetY: 3,
                opacity: 0.58,
                backdrop: WatchDesignTokens.avatarBackdropMuted,
                ringColor: WatchDesignTokens.ringMutedGray,
                badge: .muted
            )
        case .ending, .ended:
            WatchBearArtSpec(
                assetName: "WatchBear-done",
                imageSize: 86,
                offsetX: 3,
                offsetY: -1,
                opacity: 1.0,
                backdrop: WatchDesignTokens.avatarBackdropNeutral,
                ringColor: nil,
                badge: nil
            )
        case .locked:
            WatchBearArtSpec(
                assetName: "WatchBear-needs",
                imageSize: 86,
                offsetX: 3,
                offsetY: -1,
                opacity: 1.0,
                backdrop: WatchDesignTokens.avatarBackdropNeutral,
                ringColor: nil,
                badge: .locked
            )
        }
    }

    var indicator: WatchDynamicIndicatorKind? {
        switch self {
        case .connecting, .waking, .ending:
            .connectingDots
        case .listening:
            .listeningWave
        case .thinking:
            .thinkingDots
        case .acting(_, let badge):
            badge.map { .stepBadge($0) }
        case .speaking:
            .speakingWave
        case .ended:
            .endedCheckmark
        case .unavailable, .needsSetup, .idle, .muted, .locked, .failed:
            nil
        }
    }

    var titleColor: Color {
        switch self {
        case .unavailable, .failed:
            WatchDesignTokens.titleRed
        case .muted:
            WatchDesignTokens.titleMuted
        default:
            WatchDesignTokens.titleWhite
        }
    }

    var subtitleColor: Color {
        switch self {
        case .idle:
            WatchDesignTokens.subtitleIdle
        default:
            WatchDesignTokens.subtitleDefault
        }
    }
}
