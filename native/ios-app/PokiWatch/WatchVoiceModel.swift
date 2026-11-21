import AVFoundation
import Observation
import UserNotifications
import WatchConnectivity
import WatchKit

@MainActor
@Observable
final class WatchVoiceModel: NSObject, WCSessionDelegate {
    static let shared = WatchVoiceModel()

    private struct Pending: Codable {
        let id: UUID
        var audio: Data?
        var update: WatchVoiceUpdate?
    }

    private struct Archive: Codable {
        var pending: Pending?
        var results: [WatchVoiceUpdate] = []
    }

    private let session = WCSession.default
    private let archiveURL = URL.applicationSupportDirectory.appending(path: "WatchVoice.json")
    private let recordingURL = FileManager.default.temporaryDirectory.appending(path: "PokiWatchVoice.m4a")
    private var archive = Archive()
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingLimit: Task<Void, Never>?
    @ObservationIgnored private var reachabilityWait: Task<Void, Never>?
    @ObservationIgnored private var sendTimeout: Task<Void, Never>?
    @ObservationIgnored private var sendToken = 0
    @ObservationIgnored private var pendingContent: NSKeyValueObservation?
    @ObservationIgnored private var backgroundTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private(set) var microphone = AVAudioApplication.shared.recordPermission
    private(set) var recording = false
    private(set) var sending = false
    private(set) var deliveryFailure: WatchVoiceDeliveryFailure?
    private(set) var problem: LocalizedStringResource?

    var hasPending: Bool { archive.pending != nil }
    var update: WatchVoiceUpdate? { archive.pending?.update }
    var results: [WatchVoiceUpdate] { archive.results }
    var pendingStatus: WatchVoicePendingStatus {
        WatchVoicePendingStatus.resolve(hasPending: hasPending, sending: sending, update: update, failure: deliveryFailure)
    }

    private override init() {
        super.init()
        if let saved = try? Data(contentsOf: archiveURL),
           let decoded = try? JSONDecoder().decode(Archive.self, from: saved) {
            archive = decoded
        }
        session.delegate = self
        pendingContent = session.observe(\.hasContentPending) { [weak self] _, _ in
            Task { @MainActor in self?.finishBackgroundTasks() }
        }
        session.activate()
    }

    func opened() {
        microphone = AVAudioApplication.shared.recordPermission
        receiveContext(session.receivedApplicationContext)
        if archive.pending != nil { sync() }
    }

    func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
        microphone = AVAudioApplication.shared.recordPermission
        if microphone == .granted { await requestNotifications() }
    }

    func requestNotifications() async {
        let notifications = UNUserNotificationCenter.current()
        if await notifications.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await notifications.requestAuthorization(options: [.alert, .sound])
        }
    }

    func startRecording() {
        guard microphone == .granted, !hasPending, !recording else { return }
        problem = nil
        deliveryFailure = nil
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .default)
            try audio.setActive(true)
            let recorder = try AVAudioRecorder(url: recordingURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 16_000
            ])
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            recording = true
            recordingLimit = Task {
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { stopRecording() }
            }
        } catch {
            releaseMicrophone()
            problem = "Poki couldn’t start recording. Try holding the microphone again."
        }
    }

    func stopRecording() {
        guard let recorder else { return }
        let seconds = recorder.currentTime
        releaseMicrophone()
        defer { try? FileManager.default.removeItem(at: recordingURL) }
        guard seconds >= 0.3 else {
            problem = "Hold the microphone while you speak."
            return
        }
        guard let audio = try? Data(contentsOf: recordingURL), !audio.isEmpty, audio.count <= WatchVoiceRequest.maxAudioBytes else {
            problem = "The recording couldn’t be saved. Try a shorter request."
            return
        }
        var next = archive
        next.pending = Pending(id: UUID(), audio: audio)
        if save(next) { sync() }
    }

    func cancelRecording() {
        guard recording else { return }
        releaseMicrophone()
        try? FileManager.default.removeItem(at: recordingURL)
    }

    func discardPending() {
        guard archive.pending?.update == nil else { return }
        cancelInFlightDelivery()
        var next = archive
        next.pending = nil
        if save(next) {
            deliveryFailure = nil
            problem = nil
        }
    }

    private func releaseMicrophone() {
        recordingLimit?.cancel()
        recordingLimit = nil
        recorder?.stop()
        recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cancelInFlightDelivery() {
        sendToken &+= 1
        reachabilityWait?.cancel()
        reachabilityWait = nil
        sendTimeout?.cancel()
        sendTimeout = nil
        sending = false
    }

    func sync() {
        guard let pending = archive.pending, !sending else { return }
        deliveryFailure = nil
        problem = nil
        if session.activationState != .activated {
            session.activate()
            waitForConnection(id: pending.id, onTimeout: .sessionInactive)
            return
        }
        if !session.isCompanionAppInstalled {
            failDelivery(.companionNotInstalled)
            return
        }
        if session.iOSDeviceNeedsUnlockAfterRebootForReachability {
            failDelivery(.needsUnlockAfterReboot)
            return
        }
        if !session.isReachable {
            waitForConnection(id: pending.id, onTimeout: .phoneUnavailable)
            return
        }
        sendNow(pending)
    }

    private func waitForConnection(id: UUID, onTimeout failure: WatchVoiceDeliveryFailure) {
        reachabilityWait?.cancel()
        sending = true
        sendToken &+= 1
        let token = sendToken
        reachabilityWait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.sendToken == token, self.archive.pending?.id == id else { return }
            self.reachabilityWait = nil
            self.sending = false
            if self.session.activationState == .activated, self.session.isReachable {
                self.sync()
            } else if self.session.iOSDeviceNeedsUnlockAfterRebootForReachability {
                self.failDelivery(.needsUnlockAfterReboot)
            } else {
                self.failDelivery(failure)
            }
        }
    }

    private func sendNow(_ pending: Pending) {
        reachabilityWait?.cancel()
        reachabilityWait = nil
        let request = pending.audio.map { WatchVoiceRequest.submit(id: pending.id, audio: $0) } ?? .status(id: pending.id)
        guard let data = try? JSONEncoder().encode(request) else {
            failDelivery(.deliveryFailed)
            return
        }
        sendToken &+= 1
        let token = sendToken
        sending = true
        sendTimeout?.cancel()
        sendTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.sendToken == token, self.archive.pending?.id == pending.id else { return }
            self.sendTimeout = nil
            self.sending = false
            self.failDelivery(.timedOut)
        }
        session.sendMessageData(data) { [weak self] reply in
            Task { @MainActor in
                guard let self, self.archive.pending?.id == pending.id else { return }
                let matchesCurrent = self.sendToken == token
                if matchesCurrent {
                    self.sendTimeout?.cancel()
                    self.sendTimeout = nil
                    self.sending = false
                }
                if let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: reply), update.id == pending.id {
                    self.receive(update)
                } else if !matchesCurrent {
                    return
                } else if pending.update != nil {
                    self.receive(WatchVoiceUpdate(id: pending.id, phase: .blocked, text: String(localized:
                        "Poki couldn’t find the accepted task on iPhone. Check what happened there before recording it again.")))
                } else {
                    self.failDelivery(.phoneUnavailable)
                }
            }
        } errorHandler: { [weak self] error in
            Task { @MainActor in
                guard let self, self.sendToken == token, self.archive.pending?.id == pending.id else { return }
                self.sendTimeout?.cancel()
                self.sendTimeout = nil
                self.sending = false
                let nsError = error as NSError
                let failure = nsError.domain == WCErrorDomain
                    ? WatchVoiceDeliveryFailure.from(wcErrorCode: nsError.code)
                    : .deliveryFailed
                self.failDelivery(failure)
            }
        }
    }

    private func failDelivery(_ failure: WatchVoiceDeliveryFailure) {
        deliveryFailure = failure
        if archive.pending?.update != nil {
            problem = failure.detail
        } else {
            problem = nil
        }
        if WKApplication.shared().applicationState == .active {
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func loadFullResult(_ id: UUID) async -> Bool {
        guard let result = results.first(where: { $0.id == id }),
              let total = result.fullTextBytes else { return true }
        var received = Data()
        while received.count < total {
            guard !Task.isCancelled, session.activationState == .activated, session.isReachable,
                  let request = try? JSONEncoder().encode(WatchVoiceRequest.result(id: id, offset: received.count)),
                  let chunk = await resultReply(to: request),
                  chunk.count == min(total - received.count, WatchVoiceRequest.resultChunkBytes) else { return false }
            received.append(chunk)
        }
        guard !Task.isCancelled, let text = String(data: received, encoding: .utf8),
              let index = archive.results.firstIndex(where: { $0.id == id }) else { return false }
        var next = archive
        next.results[index] = WatchVoiceUpdate(id: id, phase: result.phase, text: text)
        return save(next)
    }

    private func resultReply(to request: Data) async -> Data? {
        await withCheckedContinuation { continuation in
            session.sendMessageData(request, replyHandler: { continuation.resume(returning: $0) },
                                    errorHandler: { _ in continuation.resume(returning: nil) })
        }
    }

    private func save(_ next: Archive) -> Bool {
        do {
            try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: archiveURL, options: .atomic)
            archive = next
            return true
        } catch {
            problem = "Poki couldn’t save this task on Watch. Check available storage and retry."
            return false
        }
    }

    private func receive(_ update: WatchVoiceUpdate) {
        guard var pending = archive.pending, update.id == pending.id,
              pending.update.map({ $0.phase.canAdvance(to: update.phase) }) ?? true else { return }
        var next = archive
        if update.phase.isTerminal {
            next.pending = nil
            next.results.insert(update, at: 0)
        } else {
            pending.update = update
            pending.audio = nil
            next.pending = pending
        }
        guard save(next) else { return }
        cancelInFlightDelivery()
        deliveryFailure = nil
        problem = nil
        if update.phase.isTerminal {
            notify(update)
        } else if update.phase == .waitingForUnlock, WKApplication.shared().applicationState == .active {
            WKInterfaceDevice.current().play(.notification)
        }
    }

    private func notify(_ update: WatchVoiceUpdate) {
        if WKApplication.shared().applicationState == .active {
            WKInterfaceDevice.current().play(update.phase == .finished ? .success : .failure)
        } else {
            let content = UNMutableNotificationContent()
            content.title = String(localized: update.phase == .finished ? "Poki task finished" : "Poki task needs attention")
            content.body = String(localized: "Open Poki to see the result.")
            content.sound = .default
            let request = UNNotificationRequest(identifier: update.id.uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func receiveContext(_ context: [String: Any]) {
        if let data = context[WatchVoiceRequest.contextKey] as? Data,
           let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: data) {
            receive(update)
        }
    }

    func handle(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        backgroundTasks.append(task)
        finishBackgroundTasks()
    }

    private func finishBackgroundTasks() {
        guard session.activationState == .activated, !session.hasContentPending else { return }
        receiveContext(session.receivedApplicationContext)
        for task in backgroundTasks { task.setTaskCompletedWithSnapshot(false) }
        backgroundTasks.removeAll()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if activationState == .activated {
                if self.reachabilityWait != nil {
                    self.reachabilityWait?.cancel()
                    self.reachabilityWait = nil
                    self.sending = false
                }
                opened()
                finishBackgroundTasks()
            } else {
                self.cancelInFlightDelivery()
                self.failDelivery(.sessionInactive)
                for task in backgroundTasks { task.setTaskCompletedWithSnapshot(false) }
                backgroundTasks.removeAll()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            guard session.isReachable else { return }
            if self.reachabilityWait != nil {
                self.reachabilityWait?.cancel()
                self.reachabilityWait = nil
                self.sending = false
            }
            if self.archive.pending != nil { self.sync() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: messageData) else { return }
        Task { @MainActor in receive(update) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            receiveContext(applicationContext)
            finishBackgroundTasks()
        }
    }
}

extension WatchVoiceDeliveryFailure {
    var title: LocalizedStringResource {
        switch self {
        case .needsUnlockAfterReboot: "Unlock iPhone first"
        case .phoneUnavailable: "Poki isn’t responding on iPhone"
        case .timedOut: "iPhone didn’t reply in time"
        case .companionNotInstalled: "Install Poki on iPhone"
        case .sessionInactive: "Couldn’t connect to iPhone"
        case .deliveryFailed: "Couldn’t send to iPhone"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .needsUnlockAfterReboot: "Your iPhone restarted. Unlock your iPhone, then try again."
        case .phoneUnavailable: "Open Poki on your iPhone if it was closed, then try again."
        case .timedOut: "iPhone took too long to reply. Open Poki on your iPhone and try again."
        case .companionNotInstalled: "Install Poki on your paired iPhone and try again."
        case .sessionInactive: "Move closer to your paired iPhone and try again."
        case .deliveryFailed: "Check your iPhone connection or open Poki, then try again."
        }
    }

    var symbol: String {
        switch self {
        case .needsUnlockAfterReboot: "lock.fill"
        case .phoneUnavailable, .timedOut, .companionNotInstalled, .sessionInactive, .deliveryFailed:
            "exclamationmark.triangle"
        }
    }
}
