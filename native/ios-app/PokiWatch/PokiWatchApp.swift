import SwiftUI
import WatchKit

@main
struct PokiWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchVoiceDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup { WatchVoiceView(model: .shared) }
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

private struct WatchVoiceView: View {
    @Environment(\.scenePhase) private var scenePhase
    let model: WatchVoiceModel

    var body: some View {
        NavigationStack {
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
                            result(latest)
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
                            List(model.results) { update in
                                NavigationLink {
                                    result(update)
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
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Poki")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.opened()
                if model.microphone == .granted { Task { await model.requestNotifications() } }
            } else if phase == .background {
                model.cancelRecording()
            }
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

    private func result(_ update: WatchVoiceUpdate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Label(update.phase.title, systemImage: update.phase.symbol)
                    .font(.footnote.weight(.semibold))
                if let text = update.text { Text(text) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
        .navigationTitle("Result")
    }
}

private extension WatchVoiceUpdate.Phase {
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
