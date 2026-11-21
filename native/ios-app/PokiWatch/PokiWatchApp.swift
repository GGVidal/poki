import SwiftUI
import WatchKit

@main
struct PokiWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchVoiceDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup { WatchVoiceRemoteView(model: .shared) }
    }
}

final class WatchVoiceDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask {
                WatchVoiceModel.shared.handle(connectivity)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

private struct WatchVoiceRemoteView: View {
    @Environment(\.scenePhase) private var scenePhase
    let model: WatchVoiceModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    statusHeader
                    if let step = model.remoteCurrentStep {
                        Text(step)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityIdentifier("watchRemote.step")
                    }
                    if model.remoteState.isActiveCall {
                        WatchVoiceLevelBars(level: model.remoteMeterLevel, muted: model.remoteIsMuted)
                            .accessibilityIdentifier("watchRemote.meter")
                    }
                    if model.remoteRequiresForeground {
                        Label("Continue on iPhone", systemImage: "iphone.and.arrow.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("watchRemote.continueOnPhone")
                    }
                    primaryButton
                    if model.canEndRemoteCall {
                        Button(role: .destructive) {
                            model.remoteEndAction()
                        } label: {
                            Label("End", systemImage: "phone.down.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(model.remoteCommandInFlight || model.remoteState == .ending)
                        .accessibilityIdentifier("watchRemote.end")
                    }
                    if let notice = detailLine {
                        Text(notice)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if let latest = model.results.first {
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
                        .accessibilityIdentifier("watchRemote.latestResult")
                    }
                    if !model.results.isEmpty {
                        NavigationLink("Task history") {
                            WatchVoiceHistoryView(model: model)
                        }
                        .accessibilityIdentifier("watchRemote.history")
                    }
                    NavigationLink {
                        WatchVoiceTaskView(model: model)
                    } label: {
                        HStack {
                            Label("Voice Task", systemImage: "mic")
                            Spacer()
                            if model.hasPending {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .accessibilityIdentifier("watchRemote.voiceTask")
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Poki")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.opened()
                Task { await model.requestNotifications() }
            } else if phase == .background {
                model.cancelRecording()
            }
        }
    }

    private var statusHeader: some View {
        Label(model.remoteState.title, systemImage: model.remoteState.symbol)
            .font(.headline)
            .foregroundStyle(model.remoteState.tint)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("watchRemote.status")
    }

    private var primaryButton: some View {
        let active = model.remoteState.isActiveCall
        let muted = model.remoteIsMuted
        let title: LocalizedStringResource = active ? (muted ? "Unmute" : "Mute") : "Start"
        let symbol = active ? (muted ? "mic.slash.fill" : "mic.fill") : "waveform"
        let tint: Color = active ? (muted ? .orange : .blue) : .blue
        return Button {
            model.remotePrimaryAction()
        } label: {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(model.remoteCommandInFlight || model.remoteState == .ending)
        .handGestureShortcut(.primaryAction)
        .accessibilityIdentifier("watchRemote.primary")
    }

    private var detailLine: String? {
        if model.hasPendingRemoteEnd {
            return String(localized: "Ending when iPhone reconnects…")
        }
        if let transportError = model.remoteTransportError {
            return String(localized: transportError)
        }
        if let detail = model.remoteDetail, !detail.isEmpty {
            return detail
        }
        return nil
    }
}

private struct WatchVoiceLevelBars: View {
    let level: UInt8
    let muted: Bool

    private static let weights: [Double] = [0.45, 0.78, 1.0, 0.78, 0.45]

    var body: some View {
        let normalized = muted ? 0.0 : Double(level) / 255.0
        HStack(spacing: 4) {
            ForEach(Self.weights.indices, id: \.self) { index in
                let height = max(4, 16 * normalized * Self.weights[index])
                Capsule()
                    .fill(muted ? Color.secondary.opacity(0.4) : Color.blue)
                    .frame(width: 4, height: height)
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.14), value: level)
        .accessibilityHidden(true)
    }
}

private struct WatchVoiceTaskView: View {
    let model: WatchVoiceModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if model.microphone == .undetermined {
                    Button("Enable microphone", systemImage: "mic") {
                        Task { await model.requestMicrophone() }
                    }
                } else if model.microphone == .denied {
                    Label("Allow Poki’s microphone in Watch Settings.", systemImage: "mic.slash")
                        .font(.footnote)
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
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if model.hasPending, !model.sending {
                    Button(model.update == nil ? "Retry delivery" : "Check iPhone") { model.sync() }
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
        .navigationTitle("Voice Task")
        .task {
            if model.microphone == .granted { await model.requestNotifications() }
        }
    }

    private var recordControl: some View {
        VStack(spacing: 7) {
            Image(systemName: model.recording ? "waveform" : "mic.fill")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(model.recording ? .white : .blue)
                .frame(width: 64, height: 64)
                .background(model.recording ? Color.red : .blue.opacity(0.18), in: Circle())
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
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct WatchVoiceHistoryView: View {
    let model: WatchVoiceModel

    var body: some View {
        List(model.results) { update in
            NavigationLink {
                WatchVoiceResultView(model: model, id: update.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(update.phase.title, systemImage: update.phase.symbol)
                    if let text = update.text { Text(text).font(.footnote).lineLimit(2) }
                }
            }
        }
        .navigationTitle("Task history")
    }
}

private struct WatchVoiceResultView: View {
    let model: WatchVoiceModel
    let id: UUID
    @State private var retry = 0
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            if let update = model.results.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(update.phase.title, systemImage: update.phase.symbol)
                        .font(.footnote.weight(.semibold))
                    if update.fullTextBytes != nil {
                        if loadFailed {
                            Text("Couldn’t load the full result.")
                                .font(.footnote)
                            Button("Try again") { retry += 1 }
                        } else {
                            ProgressView("Loading full result…")
                        }
                        Text("Preview").font(.caption).foregroundStyle(.secondary)
                    }
                    if let text = update.text { Text(text) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
        }
        .navigationTitle("Result")
        .task(id: retry) {
            loadFailed = false
            let loaded = await model.loadFullResult(id)
            if !Task.isCancelled { loadFailed = !loaded }
        }
    }
}

private extension WatchVoiceCallState {
    var title: LocalizedStringResource {
        switch self {
        case .unavailable: "Unavailable"
        case .needsSetup: "Not set up"
        case .idle: "Ready"
        case .connecting: "Connecting"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Poki is speaking"
        case .muted: "Muted"
        case .ending: "Ending"
        case .failed: "Connection failed"
        }
    }

    var symbol: String {
        switch self {
        case .unavailable: "iphone.slash"
        case .needsSetup: "gearshape"
        case .idle: "waveform"
        case .connecting: "ellipsis.circle"
        case .listening: "mic.fill"
        case .thinking: "brain"
        case .speaking: "speaker.wave.2.fill"
        case .muted: "mic.slash.fill"
        case .ending: "phone.down"
        case .failed: "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .unavailable, .needsSetup, .ending: .secondary
        case .idle, .connecting, .listening, .thinking, .speaking: .primary
        case .muted: .orange
        case .failed: .red
        }
    }
}

private extension WatchVoiceUpdate.Phase {
    var title: LocalizedStringResource {
        switch self {
        case .received: "iPhone received it"
        case .waitingForUnlock: "Received. Unlock your iPhone."
        case .running: "Poki is working"
        case .finished: "Task finished"
        case .blocked: "Task needs attention"
        }
    }

    var symbol: String {
        switch self {
        case .received: "iphone"
        case .waitingForUnlock: "lock.fill"
        case .running: "ellipsis.circle"
        case .finished: "checkmark.circle"
        case .blocked: "exclamationmark.circle"
        }
    }
}
