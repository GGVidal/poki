// Adapted from khooeee/watchamacallit (Watchamacallit/ContentView.swift, commit df86d982),
// MIT License, Copyright (c) 2026 Chris Khoo; status badge styling adapted from
// semantic-craft/iOS-vibebuddy (VibeBuddyApp/Watch/WatchAlertCard.swift, commit 2c2972d7),
// MIT License, Copyright (c) 2026 Xianwei Zhang.
// Poki replaces the SF Symbol orb with Poki's bear artwork, ring colors, status badges,
// and Paper W02-W16 dynamic indicators.

import SwiftUI

struct WatchVoiceOrbView: View {
    let mode: WatchScreenMode
    let meterLevel: UInt8
    let title: LocalizedStringResource
    let subtitle: String?
    let isInteractive: Bool
    let isDisabled: Bool
    let accessibilityIdentifier: String?
    let onTap: () -> Void
    let onLongPress: (() -> Void)?

    @State private var suppressedNextTap = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let art = mode.bearArt
        let indicator = mode.indicator

        VStack(spacing: 6) {
            avatarControl(art: art)

            if let indicator {
                WatchDynamicIndicatorView(
                    kind: indicator,
                    meterLevel: meterLevel,
                    reduceMotion: reduceMotion
                )
                .frame(height: WatchDesignTokens.indicatorHeight)
                .accessibilityIdentifier(indicator == .listeningWave || indicator == .speakingWave ? "watchRemote.meter" : "")
            }

            VStack(spacing: indicator == nil ? 3 : 2) {
                Text(title)
                    .font(WatchDesignTokens.titleFont)
                    .foregroundStyle(mode.titleColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("watchRemote.status")

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(WatchDesignTokens.subtitleFont)
                        .foregroundStyle(mode.subtitleColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(isActing ? "watchRemote.step" : "watchRemote.subtitle")
                }
            }
            .padding(.top, indicator == nil ? 8 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var isActing: Bool {
        if case .acting = mode { return true }
        return false
    }

    @ViewBuilder
    private func avatarControl(art: WatchBearArtSpec) -> some View {
        let circle = ZStack {
            Circle()
                .fill(art.backdrop)
                .frame(width: WatchDesignTokens.avatarSize, height: WatchDesignTokens.avatarSize)
                .overlay {
                    Image(art.assetName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: art.imageSize, height: art.imageSize)
                        .offset(x: art.offsetX, y: art.offsetY)
                        .opacity(art.opacity)
                }
                .clipShape(Circle())

            if let ringColor = art.ringColor {
                Circle()
                    .strokeBorder(ringColor, lineWidth: WatchDesignTokens.avatarRingWidth)
                    .frame(width: WatchDesignTokens.avatarSize, height: WatchDesignTokens.avatarSize)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge = art.badge {
                WatchCornerBadgeView(kind: badge)
                    .offset(x: WatchDesignTokens.badgeOffset, y: WatchDesignTokens.badgeOffset)
            }
        }
        .frame(width: WatchDesignTokens.avatarSize, height: WatchDesignTokens.avatarSize)
        .contentShape(Circle())

        if isInteractive {
            let button = Button {
                if suppressedNextTap {
                    suppressedNextTap = false
                    return
                }
                onTap()
            } label: {
                circle
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .handGestureShortcut(.primaryAction)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier ?? "watchRemote.primary")

            if let onLongPress {
                button.simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55)
                        .onEnded { _ in
                            suppressedNextTap = true
                            onLongPress()
                        }
                )
            } else {
                button
            }
        } else {
            circle
                .accessibilityHidden(true)
        }
    }

    private var accessibilityLabel: LocalizedStringResource {
        switch mode {
        case .muted: "Unmute"
        default: "Start"
        }
    }
}

private struct WatchCornerBadgeView: View {
    let kind: WatchCornerBadgeKind

    var body: some View {
        let innerSize = WatchDesignTokens.badgeSize - WatchDesignTokens.badgeBorderWidth * 2
        ZStack {
            Circle()
                .fill(WatchDesignTokens.screenBackground)
                .frame(width: WatchDesignTokens.badgeSize, height: WatchDesignTokens.badgeSize)
            Circle()
                .fill(fillColor)
                .frame(width: innerSize, height: innerSize)
            Image(systemName: symbolName)
                .font(.system(size: symbolSize, weight: .bold))
                .foregroundStyle(iconColor)
        }
        .frame(width: WatchDesignTokens.badgeSize, height: WatchDesignTokens.badgeSize)
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        switch kind {
        case .error: WatchDesignTokens.statusRed
        case .setup, .locked: WatchDesignTokens.statusOrange
        case .muted: WatchDesignTokens.badgeMutedFill
        }
    }

    private var iconColor: Color {
        switch kind {
        case .error, .muted: .white
        case .setup, .locked: .black
        }
    }

    private var symbolName: String {
        switch kind {
        case .error: "exclamationmark"
        case .setup: "gearshape.fill"
        case .muted: "mic.slash.fill"
        case .locked: "lock.fill"
        }
    }

    private var symbolSize: CGFloat {
        switch kind {
        case .error: 12.5
        case .setup: 12
        case .locked: 11.5
        case .muted: 11
        }
    }
}

private struct WatchDynamicIndicatorView: View {
    let kind: WatchDynamicIndicatorKind
    let meterLevel: UInt8
    let reduceMotion: Bool

    private static let listeningHeights: [CGFloat] = [5, 11, 18, 11, 5]
    private static let speakingHeights: [CGFloat] = [7, 18, 13, 8, 4]

    var body: some View {
        switch kind {
        case .connectingDots:
            pulsingDots(count: 5, size: 4, spacing: 4, color: WatchDesignTokens.subtitleDefault)
        case .thinkingDots:
            pulsingDots(count: 3, size: 6, spacing: 6, color: .white)
        case .listeningWave:
            waveBars(baseHeights: Self.listeningHeights, color: WatchDesignTokens.ringSkyBlue)
        case .speakingWave:
            waveBars(baseHeights: Self.speakingHeights, color: WatchDesignTokens.ringPokiBlue)
        case .stepBadge(let text):
            Text(text)
                .font(WatchDesignTokens.stepBadgeFont)
                .foregroundStyle(WatchDesignTokens.ringSkyBlue)
                .accessibilityIdentifier("watchRemote.stepBadge")
        case .endedCheckmark:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WatchDesignTokens.checkmarkGray)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func pulsingDots(count: Int, size: CGFloat, spacing: CGFloat, color: Color) -> some View {
        if reduceMotion {
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(color)
                        .frame(width: size, height: size)
                }
            }
            .accessibilityHidden(true)
        } else {
            TimelineView(.periodic(from: .now, by: 0.35)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % count
                HStack(spacing: spacing) {
                    ForEach(0..<count, id: \.self) { index in
                        Circle()
                            .fill(color)
                            .frame(width: size, height: size)
                            .opacity(index == step ? 1.0 : 0.78)
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func waveBars(baseHeights: [CGFloat], color: Color) -> some View {
        let scale: Double = meterLevel == 0 ? 1.0 : (0.72 + 0.28 * (Double(meterLevel) / 255.0))
        return HStack(spacing: 3) {
            ForEach(baseHeights.indices, id: \.self) { index in
                let height = max(4, min(18, baseHeights[index] * scale))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 4, height: height)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: meterLevel)
        .accessibilityHidden(true)
    }
}
