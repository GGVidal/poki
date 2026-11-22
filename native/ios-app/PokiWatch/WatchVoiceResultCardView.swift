// Adapted from semantic-craft/iOS-vibebuddy (VibeBuddyApp/Watch/WatchAlertCard.swift and
// WatchRootView.swift, commit 2c2972d7), MIT License, Copyright (c) 2026 Xianwei Zhang.
// Poki adapts the watch card presentation and secondary paging structure to Paper W13A
// while preserving one-shot Voice Task, task history, and multi-chunk result loading.

import SwiftUI

struct WatchVoiceResultView: View {
    let model: WatchVoiceModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var retry = 0
    @State private var loadFailed = false

    private var update: WatchVoiceUpdate? {
        model.results.first(where: { $0.id == id })
    }

    var body: some View {
        ZStack {
            WatchDesignTokens.screenBackground
                .ignoresSafeArea()

            VStack(spacing: 8) {
                HStack {
                    resultTopStatus
                    Spacer()
                }
                .frame(height: 18)
                .padding(.horizontal, 2)

                if let update {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 7) {
                            if update.fullTextBytes != nil {
                                if loadFailed {
                                    Text("Couldn’t load the full result.")
                                        .font(WatchDesignTokens.resultBodyFont)
                                        .foregroundStyle(WatchDesignTokens.titleRed)
                                    Button("Try again") { retry += 1 }
                                        .font(WatchDesignTokens.buttonFont)
                                        .buttonStyle(.bordered)
                                } else {
                                    ProgressView("Loading full result…")
                                        .font(WatchDesignTokens.resultBodyFont)
                                }
                                Text("Preview")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(WatchDesignTokens.hintSecondary)
                            }

                            if let text = update.text {
                                let parts = Self.splitHeadlineAndBody(text)
                                Text(parts.headline)
                                    .font(WatchDesignTokens.resultHeadlineFont)
                                    .foregroundStyle(WatchDesignTokens.titleWhite)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let detail = parts.body {
                                    Text(detail)
                                        .font(WatchDesignTokens.resultBodyFont)
                                        .foregroundStyle(WatchDesignTokens.cardBodyText)
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(WatchDesignTokens.resultCardPadding)
                        .padding(.bottom, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        WatchDesignTokens.cardFill,
                        in: RoundedRectangle(cornerRadius: WatchDesignTokens.resultCardCornerRadius, style: .continuous)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: WatchDesignTokens.resultCardCornerRadius, style: .continuous))
                } else {
                    Text("Result")
                        .font(WatchDesignTokens.resultBodyFont)
                        .foregroundStyle(WatchDesignTokens.subtitleDefault)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Text("Turn Crown for details")
                        .font(WatchDesignTokens.subtitleFont)
                        .foregroundStyle(WatchDesignTokens.hintSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text("Saved to history")
                        .font(WatchDesignTokens.hintFont)
                        .foregroundStyle(WatchDesignTokens.hintMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 3)

                Button {
                    model.clearSelectedResult()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(WatchDesignTokens.buttonFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: WatchDesignTokens.bottomBarHeight)
                        .background(
                            WatchDesignTokens.pillNeutralFill,
                            in: RoundedRectangle(cornerRadius: WatchDesignTokens.pillCornerRadius, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watchResult.done")
            }
            .padding(.top, 17)
            .padding(.horizontal, WatchDesignTokens.screenHorizontalPadding)
            .padding(.bottom, WatchDesignTokens.screenBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: retry) {
            loadFailed = false
            let loaded = await model.loadFullResult(id)
            if !Task.isCancelled { loadFailed = !loaded }
        }
    }

    private var resultTopStatus: some View {
        let isBlocked = update?.phase == .blocked
        let accent = isBlocked ? WatchDesignTokens.statusOrange : WatchDesignTokens.statusGreen
        let pillFill = isBlocked ? WatchDesignTokens.statusOrange.opacity(0.22) : WatchDesignTokens.statusGreenPill
        let title: LocalizedStringResource = update?.phase.title ?? "Task finished"
        let symbol = isBlocked ? "exclamationmark" : "checkmark"

        return HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(pillFill)
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 15, height: 15)

            Text(title)
                .font(WatchDesignTokens.topBarFont)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityIdentifier("watchResult.status")
    }

    static func splitHeadlineAndBody(_ text: String) -> (headline: String, body: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(maxSplits: 1, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count == 2 {
            return (lines[0], lines[1])
        }
        return (trimmed, nil)
    }
}

struct WatchVoiceSecondaryHubView: View {
    let model: WatchVoiceModel

    var body: some View {
        ZStack {
            WatchDesignTokens.screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 8) {
                    if let latest = model.results.first {
                        NavigationLink {
                            WatchVoiceResultView(model: model, id: latest.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 5) {
                                    Image(systemName: latest.phase.symbol)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(latest.phase == .finished ? WatchDesignTokens.statusGreen : WatchDesignTokens.statusOrange)
                                    Text(latest.phase.title)
                                        .font(WatchDesignTokens.buttonFont)
                                        .foregroundStyle(WatchDesignTokens.titleWhite)
                                        .lineLimit(1)
                                }
                                if let text = latest.text {
                                    Text(text)
                                        .font(WatchDesignTokens.resultBodyFont)
                                        .foregroundStyle(WatchDesignTokens.cardBodyText)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(11)
                            .background(
                                WatchDesignTokens.cardFill,
                                in: RoundedRectangle(cornerRadius: WatchDesignTokens.resultCardCornerRadius, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("watchRemote.latestResult")
                    }

                    if !model.results.isEmpty {
                        NavigationLink {
                            WatchVoiceHistoryView(model: model)
                        } label: {
                            hubRow(title: "Task history", symbol: "clock.arrow.circlepath", showBadge: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("watchRemote.history")
                    }

                    NavigationLink {
                        WatchVoiceTaskView(model: model)
                    } label: {
                        hubRow(title: "Voice Task", symbol: "mic.fill", showBadge: model.hasPending)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchRemote.voiceTask")
                }
                .padding(.horizontal, WatchDesignTokens.screenHorizontalPadding)
                .padding(.top, 6)
                .padding(.bottom, WatchDesignTokens.screenBottomPadding)
            }
        }
    }

    private func hubRow(title: LocalizedStringResource, symbol: String, showBadge: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WatchDesignTokens.ringSkyBlue)
                .frame(width: 18)
            Text(title)
                .font(WatchDesignTokens.buttonFont)
                .foregroundStyle(WatchDesignTokens.titleWhite)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showBadge {
                Circle()
                    .fill(WatchDesignTokens.pillBlueFill)
                    .frame(width: 7, height: 7)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchDesignTokens.hintSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            WatchDesignTokens.cardFill,
            in: RoundedRectangle(cornerRadius: WatchDesignTokens.resultCardCornerRadius, style: .continuous)
        )
    }
}

struct WatchVoiceHistoryView: View {
    let model: WatchVoiceModel

    var body: some View {
        List(model.results) { update in
            NavigationLink {
                WatchVoiceResultView(model: model, id: update.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(update.phase.title, systemImage: update.phase.symbol)
                        .font(WatchDesignTokens.buttonFont)
                    if let text = update.text {
                        Text(text)
                            .font(WatchDesignTokens.resultBodyFont)
                            .foregroundStyle(WatchDesignTokens.subtitleDefault)
                            .lineLimit(2)
                    }
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: WatchDesignTokens.resultCardCornerRadius, style: .continuous)
                    .fill(WatchDesignTokens.cardFill)
            )
        }
        .scrollContentBackground(.hidden)
        .background(WatchDesignTokens.screenBackground.ignoresSafeArea())
        .navigationTitle("Task history")
    }
}

struct WatchVoiceTaskView: View {
    let model: WatchVoiceModel

    var body: some View {
        ZStack {
            WatchDesignTokens.screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if model.microphone == .undetermined {
                        Button("Enable microphone", systemImage: "mic") {
                            Task { await model.requestMicrophone() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WatchDesignTokens.pillBlueFill)
                    } else if model.microphone == .denied {
                        Label("Allow Poki’s microphone in Watch Settings.", systemImage: "mic.slash")
                            .font(.footnote)
                            .foregroundStyle(WatchDesignTokens.subtitleDefault)
                    } else if !model.hasPending {
                        recordControl
                    }
                    if let update = model.update {
                        Label(update.phase.title, systemImage: update.phase.symbol)
                            .font(.headline)
                    } else if model.hasPending {
                        Label("Sending recording…", systemImage: "arrow.up.circle")
                            .font(.headline)
                    }
                    if let problem = model.problem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(WatchDesignTokens.subtitleDefault)
                            .multilineTextAlignment(.center)
                    }
                    if model.hasPending, !model.sending {
                        Button(model.update == nil ? "Retry delivery" : "Check iPhone") { model.sync() }
                            .buttonStyle(.borderedProminent)
                            .tint(WatchDesignTokens.pillBlueFill)
                    }
                    if let latest = model.results.first, !model.hasPending, !model.recording {
                        NavigationLink {
                            WatchVoiceResultView(model: model, id: latest.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(latest.phase.title, systemImage: latest.phase.symbol)
                                    .font(.footnote.weight(.semibold))
                                if let text = latest.text {
                                    Text(text).font(.caption2).lineLimit(2)
                                }
                            }
                        }
                    }
                    if !model.results.isEmpty, !model.recording {
                        NavigationLink("Task history") {
                            WatchVoiceHistoryView(model: model)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Voice Task")
        .task {
            if model.microphone == .granted { await model.requestNotifications() }
        }
    }

    private var recordControl: some View {
        VStack(spacing: 7) {
            Image(systemName: model.recording ? "waveform" : "mic.fill")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(model.recording ? .white : WatchDesignTokens.ringSkyBlue)
                .frame(width: 64, height: 64)
                .background(model.recording ? WatchDesignTokens.statusRed : WatchDesignTokens.avatarBackdropPokiBlue, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(model.recording ? WatchDesignTokens.statusRed : WatchDesignTokens.ringSkyBlue, lineWidth: 2)
                }
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: 15, maximumDistance: 45, perform: {}) { pressing in
                    if pressing { model.startRecording() } else { model.stopRecording() }
                }
                .accessibilityLabel(model.recording ? "Send recording" : "Record a task")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    if model.recording { model.stopRecording() } else { model.startRecording() }
                }
                .accessibilityIdentifier("watchVoice.record")
            Text(model.recording ? "Listening… Release to send" : "Hold to speak")
                .font(.footnote)
                .foregroundStyle(WatchDesignTokens.subtitleDefault)
                .multilineTextAlignment(.center)
        }
    }
}

extension WatchVoiceUpdate.Phase {
    var title: LocalizedStringResource {
        switch self {
        case .received: "iPhone received it"
        case .running: "Poki is working"
        case .finished: "Task finished"
        case .blocked: "Task needs attention"
        }
    }

    var symbol: String {
        switch self {
        case .received: "iphone"
        case .running: "ellipsis.circle"
        case .finished: "checkmark.circle"
        case .blocked: "exclamationmark.circle"
        }
    }
}
