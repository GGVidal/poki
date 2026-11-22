// Adapted from diegocp01/peter_ai (PeterAI/PeterAIWatch/WatchContentView.swift, commit be6d42b6),
// MIT License, Copyright (c) 2026 Diego Cabezas.
// Poki adapts the bottom watch action bar to Paper W02-W16 capsule proportions, colors, and
// side-by-side Mute + End layout.

import SwiftUI

enum WatchBottomActionLayout {
    case muteAndEnd
    case endOnly
    case primaryBlue(title: LocalizedStringResource, identifier: String)
    case caption(text: LocalizedStringResource, color: Color)
    case spacer
}

struct WatchVoiceControlsBar: View {
    let layout: WatchBottomActionLayout
    let disabled: Bool
    let onPrimary: () -> Void
    let onEnd: () -> Void

    var body: some View {
        switch layout {
        case .muteAndEnd:
            HStack(spacing: WatchDesignTokens.pillButtonGap) {
                Button(action: onPrimary) {
                    HStack(spacing: 4) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Mute")
                            .font(WatchDesignTokens.buttonFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: WatchDesignTokens.bottomBarHeight)
                    .background(
                        WatchDesignTokens.pillNeutralFill,
                        in: RoundedRectangle(cornerRadius: WatchDesignTokens.pillCornerRadius, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .handGestureShortcut(.primaryAction)
                .accessibilityIdentifier("watchRemote.primary")

                endButton(iconSize: 13)
            }
            .frame(height: WatchDesignTokens.bottomBarHeight)

        case .endOnly:
            endButton(iconSize: 14)
                .frame(height: WatchDesignTokens.bottomBarHeight)

        case .primaryBlue(let title, let identifier):
            Button(action: onPrimary) {
                Text(title)
                    .font(WatchDesignTokens.buttonFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: WatchDesignTokens.bottomBarHeight)
                    .background(
                        WatchDesignTokens.pillBlueFill,
                        in: RoundedRectangle(cornerRadius: WatchDesignTokens.pillCornerRadius, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .handGestureShortcut(.primaryAction)
            .accessibilityIdentifier(identifier)
            .frame(height: WatchDesignTokens.bottomBarHeight)

        case .caption(let text, let color):
            Text(text)
                .font(WatchDesignTokens.hintFont)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: WatchDesignTokens.bottomBarHeight)

        case .spacer:
            Color.clear
                .frame(height: WatchDesignTokens.endedBottomSpacerHeight)
        }
    }

    private func endButton(iconSize: CGFloat) -> some View {
        Button(role: .destructive, action: onEnd) {
            HStack(spacing: 5) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                Text("End")
                    .font(WatchDesignTokens.buttonFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(WatchDesignTokens.statusRedText)
            .frame(maxWidth: .infinity)
            .frame(height: WatchDesignTokens.bottomBarHeight)
            .background(
                WatchDesignTokens.pillRedFill,
                in: RoundedRectangle(cornerRadius: WatchDesignTokens.pillCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("watchRemote.end")
    }
}
