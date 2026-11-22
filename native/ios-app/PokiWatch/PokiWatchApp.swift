import SwiftUI
import UserNotifications
import WatchKit
import WidgetKit

@main
struct PokiWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchVoiceDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchVoiceRemoteView(model: .shared)
                .onOpenURL { url in
                    guard url.scheme == "pokiwatch" else { return }
                    if url.host == "start" || url.path == "/start" {
                        WatchVoiceModel.shared.handleStartDeepLink()
                    }
                }
        }
    }
}

final class WatchVoiceDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask {
                WatchVoiceModel.shared.handle(connectivity)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let id = UUID(uuidString: response.notification.request.identifier) {
            Task { @MainActor in
                WatchVoiceModel.shared.openResult(id)
            }
        }
        completionHandler()
    }
}

private struct WatchVoiceRemoteView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: WatchVoiceModel
    @State private var selectedPage: Int? = 0
    @State private var showingVoiceTask = false

    private var mode: WatchScreenMode {
        WatchScreenMode.resolve(
            state: model.remoteState,
            isMuted: model.remoteIsMuted,
            currentStep: model.remoteCurrentStep,
            requiresForeground: model.remoteRequiresForeground,
            isStartingCall: model.isStartingCall,
            showingEndedScreen: model.showingEndedScreen,
            hasTransportError: model.remoteTransportError != nil
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    mainVoiceScreen
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(0)

                    secondaryHubPage
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(1)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $selectedPage)
            .ignoresSafeArea()
            .background(WatchDesignTokens.screenBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $model.selectedResultID) { resultID in
                WatchVoiceResultView(model: model, id: resultID)
            }
            .navigationDestination(isPresented: $showingVoiceTask) {
                WatchVoiceTaskView(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.opened()
                WidgetCenter.shared.reloadTimelines(ofKind: "PokiWatchFace")
                Task { await model.requestNotifications() }
            } else if phase == .background {
                model.cancelRecording()
            }
        }
        .onChange(of: mode) { _, next in
            if next != .idle && next != .ended {
                selectedPage = 0
            }
        }
    }

    private var mainVoiceScreen: some View {
        ZStack {
            WatchDesignTokens.screenBackground

            VStack(spacing: 0) {
                HStack {
                    topLeadingStatus(forSecondary: false)
                    Spacer()
                }
                .frame(height: 18)
                .padding(.horizontal, 2)

                WatchVoiceOrbView(
                    mode: mode,
                    meterLevel: model.remoteMeterLevel,
                    title: primaryTitle,
                    subtitle: subtitleText,
                    isInteractive: mode == .idle || mode == .muted,
                    isDisabled: model.remoteCommandInFlight || model.remoteState == .ending,
                    accessibilityIdentifier: mode == .muted ? "watchRemote.unmuteBear" : "watchRemote.primary",
                    onTap: { model.remotePrimaryAction() },
                    onLongPress: mode == .idle ? {
                        WKInterfaceDevice.current().play(.click)
                        showingVoiceTask = true
                    } : nil
                )
                .padding(.top, 7)

                Spacer(minLength: 4)

                WatchVoiceControlsBar(
                    layout: bottomLayout,
                    disabled: model.remoteState == .ending || (model.remoteCommandInFlight && mode != .waking && mode != .connecting),
                    onPrimary: { model.remotePrimaryAction() },
                    onEnd: { model.remoteEndAction() }
                )
            }
            .padding(.top, 17)
            .padding(.horizontal, WatchDesignTokens.screenHorizontalPadding)
            .padding(.bottom, WatchDesignTokens.screenBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var secondaryHubPage: some View {
        VStack(spacing: 0) {
            HStack {
                topLeadingStatus(forSecondary: true)
                Spacer()
            }
            .frame(height: 18)
            .padding(.top, 16)
            .padding(.horizontal, WatchDesignTokens.screenHorizontalPadding + 2)

            WatchVoiceSecondaryHubView(model: model)
        }
        .background(WatchDesignTokens.screenBackground)
    }

    private func topLeadingStatus(forSecondary: Bool) -> some View {
        let dotColor: Color
        let labelColor: Color
        let labelText: LocalizedStringResource

        if forSecondary {
            dotColor = WatchDesignTokens.statusGreen
            labelColor = WatchDesignTokens.statusPokiLabel
            labelText = "Poki"
        } else {
            switch mode.topStatus {
            case .connected:
                dotColor = WatchDesignTokens.statusGreen
                labelColor = WatchDesignTokens.statusPokiLabel
                labelText = "Poki"
            case .attention:
                dotColor = WatchDesignTokens.statusOrange
                labelColor = WatchDesignTokens.statusOrange
                labelText = "Poki"
            case .disconnected:
                dotColor = WatchDesignTokens.statusRed
                labelColor = WatchDesignTokens.statusRedText
                labelText = "Not connected"
            }
        }

        return HStack(spacing: WatchDesignTokens.statusDotGap) {
            Circle()
                .fill(dotColor)
                .frame(width: WatchDesignTokens.statusDotSize, height: WatchDesignTokens.statusDotSize)
            Text(labelText)
                .font(WatchDesignTokens.topBarFont)
                .foregroundStyle(labelColor)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watchRemote.topStatus")
    }

    private var primaryTitle: LocalizedStringResource {
        switch mode {
        case .unavailable: "Unavailable"
        case .needsSetup: "Not set up"
        case .idle: "Ready"
        case .connecting, .waking: "Connecting"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .acting: "Acting"
        case .speaking: "Poki is speaking"
        case .muted: "Muted"
        case .ending: "Ending"
        case .ended: "Ended"
        case .locked: "Unlock iPhone to continue"
        case .failed: "Connection failed"
        }
    }

    private var subtitleText: String? {
        if model.hasPendingRemoteEnd {
            return String(localized: "Ending when iPhone reconnects…")
        }
        switch mode {
        case .unavailable:
            return String(localized: "iPhone not connected")
        case .needsSetup:
            return String(localized: "Finish voice setup on iPhone")
        case .idle:
            if let transportError = model.remoteTransportError {
                return String(localized: transportError)
            }
            return String(localized: "Tap to talk or hold to speak")
        case .connecting:
            return String(localized: "Checking connection and mic")
        case .waking:
            return String(localized: "Waking iPhone…")
        case .listening, .thinking, .speaking:
            return nil
        case .acting(let step, _):
            let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "Using the phone") : trimmed
        case .muted:
            return String(localized: "Tap Poki to unmute")
        case .ending:
            return String(localized: "Disconnecting call")
        case .ended:
            return String(localized: "Call ended. Returning in 3s")
        case .locked:
            return String(localized: "Continues automatically after unlock")
        case .failed:
            if let transportError = model.remoteTransportError {
                return String(localized: transportError)
            }
            return String(localized: "Poki isn’t running on iPhone")
        }
    }

    private var bottomLayout: WatchBottomActionLayout {
        switch mode {
        case .unavailable:
            if model.canEndRemoteCall {
                return .endOnly
            }
            return .caption(text: "Waiting for iPhone to reconnect", color: WatchDesignTokens.subtitleDefault)
        case .needsSetup:
            return .primaryBlue(title: "Continue on iPhone", identifier: "watchRemote.continueOnPhone")
        case .idle:
            return .caption(text: "Supports Double Tap", color: WatchDesignTokens.hintMuted)
        case .connecting, .waking, .muted:
            return .endOnly
        case .listening, .thinking, .acting, .speaking:
            return .muteAndEnd
        case .ending, .ended:
            return .spacer
        case .locked:
            return .primaryBlue(title: "Continue on iPhone", identifier: "watchRemote.continueOnPhone")
        case .failed:
            if model.canEndRemoteCall {
                return .endOnly
            }
            return .primaryBlue(title: "Retry", identifier: "watchRemote.retry")
        }
    }
}
