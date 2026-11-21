import AVFoundation
import Observation
import UserNotifications
import WatchConnectivity
import WatchKit

@MainActor
@Observable
final class WatchVoiceModel: NSObject, WCSessionDelegate {
    static let shared = WatchVoiceModel()

    private struct Pending: Codable, Equatable {
        let id: UUID
        var audio: Data?
        var update: WatchVoiceUpdate?
    }

    private struct Archive: Codable, Equatable {
        var pending: Pending?
        var results: [WatchVoiceUpdate] = []
        var remoteSnapshot: WatchVoiceRemoteSnapshot? = nil
        var pendingEnd: WatchVoicePendingEnd? = nil
    }

    private let session = WCSession.default
    private let archiveURL = URL.applicationSupportDirectory.appending(path: "WatchVoice.json")
    private let recordingURL = FileManager.default.temporaryDirectory.appending(path: "PokiWatchVoice.m4a")
    private var archive = Archive()
    private var remoteReducer = WatchVoiceRemoteStateReducer()
    @ObservationIgnored private let cuePlayer = WatchVoiceCuePlayer()
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingLimit: Task<Void, Never>?
    @ObservationIgnored private var meterDecayTask: Task<Void, Never>?
    @ObservationIgnored private var transientSyncTask: Task<Void, Never>?
    @ObservationIgnored private var lastStateQueryAt: Date?
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

    private(set) var remoteReachable = false
    private(set) var remoteCommandInFlight = false
    private(set) var remoteTransportError: LocalizedStringResource?

    var hasPending: Bool { archive.pending != nil }
    var update: WatchVoiceUpdate? { archive.pending?.update }
    var results: [WatchVoiceUpdate] { archive.results }
    var pendingStatus: WatchVoicePendingStatus {
        WatchVoicePendingStatus.resolve(hasPending: hasPending, sending: sending, update: update, failure: deliveryFailure)
    }

    var remoteSnapshot: WatchVoiceRemoteSnapshot? { remoteReducer.latestSnapshot }
    var remoteIsMuted: Bool { remoteReducer.latestSnapshot?.isMuted ?? false }
    var canEndRemoteCall: Bool { remoteReducer.canShowEndButton }
    var hasPendingRemoteEnd: Bool { remoteReducer.pendingEnd != nil }
    var remoteRequiresForeground: Bool { remoteReachable && remoteReducer.pendingContinueOnPhone }
    var remoteDetail: String? { remoteReducer.lastProblem }
    var remoteCurrentStep: String? {
        guard remoteReachable, remoteState.isActiveCall else { return nil }
        return remoteReducer.latestSnapshot?.currentStep
    }

    var remoteState: WatchVoiceCallState {
        guard remoteReachable else { return .unavailable }
        return remoteReducer.latestSnapshot?.state ?? .idle
    }

    var remoteMeterLevel: UInt8 {
        guard remoteReachable, remoteState.isActiveCall else { return 0 }
        return remoteReducer.meterLevel
    }

    private override init() {
        super.init()
        if let saved = try? Data(contentsOf: archiveURL),
           let decoded = try? JSONDecoder().decode(Archive.self, from: saved) {
            archive = decoded
            remoteReducer = WatchVoiceRemoteStateReducer(
                latestSnapshot: decoded.remoteSnapshot,
                pendingEnd: decoded.pendingEnd
            )
        }
        session.delegate = self
        pendingContent = session.observe(\.hasContentPending) { [weak self] _, _ in
            Task { @MainActor in self?.finishBackgroundTasks() }
        }
        session.activate()
    }

    func opened() {
        microphone = AVAudioApplication.shared.recordPermission
        updateReachability()
        receiveContext(session.receivedApplicationContext)
        flushPendingEnd()
        refreshRemoteState()
        updateActiveSync()
        if archive.pending != nil { sync() }
    }

    func refreshRemoteState() {
        guard remoteReachable else { return }
        let now = Date()
        if let last = lastStateQueryAt, now.timeIntervalSince(last) < 1.5 { return }
        lastStateQueryAt = now
        sendRemoteCommand(WatchVoiceRemoteCommand(action: .state), cueOnAccept: nil)
    }

    func remotePrimaryAction() {
        guard !remoteCommandInFlight else { return }
        guard remoteReachable else {
            remoteTransportError = "iPhone is unavailable. Open Poki on your iPhone and try again."
            cuePlayer.playFailureHaptic()
            return
        }
        if remoteState.isActiveCall {
            let nextMuted = !remoteIsMuted
            let command = WatchVoiceRemoteCommand(
                action: .setMuted(nextMuted),
                targetCallID: remoteSnapshot?.callID
            )
            sendRemoteCommand(command, cueOnAccept: nextMuted ? .mute : .unmute)
        } else {
            let command = WatchVoiceRemoteCommand(action: .start, targetCallID: nil)
            sendRemoteCommand(command, cueOnAccept: .start)
        }
    }

    func remoteEndAction() {
        guard !remoteCommandInFlight else { return }
        if let command = remoteReducer.queueEnd(now: Date()) {
            persistRemoteState(ingesting: [])
            if remoteReachable {
                sendRemoteCommand(command, cueOnAccept: .end)
            } else {
                enqueuePendingEndTransfer(command)
                remoteTransportError = nil
                cuePlayer.play(.end)
            }
            return
        }
        guard remoteReachable else {
            remoteTransportError = "iPhone is unavailable. Open Poki on your iPhone and try again."
            cuePlayer.playFailureHaptic()
            return
        }
        let command = WatchVoiceRemoteCommand(action: .end, targetCallID: remoteSnapshot?.callID)
        sendRemoteCommand(command, cueOnAccept: .end)
    }

    private func enqueuePendingEndTransfer(_ command: WatchVoiceRemoteCommand) {
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(command) else { return }
        session.transferUserInfo([WatchVoiceRemote.commandKey: data])
    }

    private func flushPendingEnd() {
        guard remoteReachable, !remoteCommandInFlight,
              let pending = remoteReducer.pendingEnd else { return }
        sendRemoteCommand(pending.makeCommand(), cueOnAccept: nil)
    }

    private func sendRemoteCommand(_ command: WatchVoiceRemoteCommand, cueOnAccept: WatchVoiceCue?) {
        guard session.activationState == .activated, session.isReachable else {
            remoteReachable = false
            if command.action == .end, command.targetCallID != nil {
                if remoteReducer.pendingEnd == nil {
                    _ = remoteReducer.queueEnd(requestID: command.requestID, now: command.issuedAt)
                    persistRemoteState(ingesting: [])
                }
                enqueuePendingEndTransfer(command)
                remoteTransportError = nil
                if let cue = cueOnAccept { cuePlayer.play(cue) }
                return
            }
            if command.action != .state {
                remoteTransportError = "iPhone is unavailable. Open Poki on your iPhone and try again."
                cuePlayer.playFailureHaptic()
            }
            return
        }
        guard let data = try? JSONEncoder().encode(command) else { return }
        let isUserCommand = command.action != .state
        if isUserCommand {
            remoteCommandInFlight = true
            remoteTransportError = nil
        }
        session.sendMessage([WatchVoiceRemote.commandKey: data]) { [weak self] replyMessage in
            Task { @MainActor in
                guard let self else { return }
                if isUserCommand { self.remoteCommandInFlight = false }
                guard let replyData = replyMessage[WatchVoiceRemote.replyKey] as? Data,
                      let reply = try? JSONDecoder().decode(WatchVoiceRemoteReply.self, from: replyData),
                      reply.requestID == command.requestID else {
                    if isUserCommand {
                        if command.action == .end, command.targetCallID != nil {
                            self.enqueuePendingEndTransfer(command)
                            self.remoteTransportError = nil
                        } else {
                            self.remoteTransportError = "iPhone didn’t confirm the command."
                            self.cuePlayer.playFailureHaptic()
                        }
                    }
                    return
                }
                self.applyRemoteReply(
                    reply,
                    targetCallID: command.targetCallID,
                    cueOnAccept: cueOnAccept,
                    isUserCommand: isUserCommand
                )
            }
        } errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if isUserCommand { self.remoteCommandInFlight = false }
                self.updateReachability()
                if command.action == .end, command.targetCallID != nil {
                    if self.remoteReducer.pendingEnd == nil {
                        _ = self.remoteReducer.queueEnd(requestID: command.requestID, now: command.issuedAt)
                        self.persistRemoteState(ingesting: [])
                    }
                    self.enqueuePendingEndTransfer(command)
                    self.remoteTransportError = nil
                    if let cue = cueOnAccept { self.cuePlayer.play(cue) }
                } else if isUserCommand {
                    self.remoteTransportError = "iPhone hasn’t replied. Open Poki on your iPhone and try again."
                    self.cuePlayer.playFailureHaptic()
                }
            }
        }
    }

    private func applyRemoteReply(
        _ reply: WatchVoiceRemoteReply,
        targetCallID: String?,
        cueOnAccept: WatchVoiceCue?,
        isUserCommand: Bool
    ) {
        guard remoteReducer.apply(reply: reply, targetCallID: targetCallID) else {
            return
        }
        remoteTransportError = nil
        persistRemoteState(ingesting: reply.snapshot.deliveredResults)
        updateActiveSync()
        if remoteReducer.pendingEnd != nil {
            flushPendingEnd()
        }
        guard isUserCommand else { return }
        if reply.outcome.isSuccess {
            if let cue = cueOnAccept {
                cuePlayer.play(cue)
            }
        } else {
            cuePlayer.playFailureHaptic()
        }
    }

    private func applyRemoteSnapshot(_ snapshot: WatchVoiceRemoteSnapshot) {
        guard remoteReducer.apply(snapshot: snapshot) else { return }
        persistRemoteState(ingesting: snapshot.deliveredResults)
        updateActiveSync()
        if remoteReducer.pendingEnd != nil {
            flushPendingEnd()
        }
    }

    private func updateActiveSync() {
        transientSyncTask?.cancel()
        transientSyncTask = nil
        let state = remoteState
        let needsInitialSync = remoteSnapshot == nil
        guard remoteReachable, needsInitialSync || state.isActiveCall || state == .ending || hasPendingRemoteEnd else { return }
        let intervalMs = (state == .connecting || state == .ending || hasPendingRemoteEnd) ? 1500 : 5000
        transientSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(intervalMs))
                guard !Task.isCancelled, let self else { return }
                guard WKApplication.shared().applicationState == .active else { return }
                let current = self.remoteState
                guard self.remoteReachable,
                      self.remoteSnapshot == nil || current.isActiveCall || current == .ending || self.hasPendingRemoteEnd else { return }
                self.flushPendingEnd()
                self.refreshRemoteState()
            }
        }
    }

    private func persistRemoteState(ingesting incoming: [WatchVoiceUpdate]) {
        var next = archive
        next.remoteSnapshot = remoteReducer.latestSnapshot
        next.pendingEnd = remoteReducer.pendingEnd
        let (merged, added) = WatchVoiceRemote.mergeResults(incoming, into: next.results)
        next.results = merged
        guard next != archive else { return }
        guard save(next), !added.isEmpty else { return }
        notify(added)
    }

    private func applyRemoteMeter(_ meter: WatchVoiceRemoteMeter) {
        let now = Date()
        guard remoteReducer.apply(meter: meter, now: now) else { return }
        meterDecayTask?.cancel()
        meterDecayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.remoteReducer.clearMeterIfStale(now: Date())
        }
    }

    private func updateReachability() {
        remoteReachable = session.activationState == .activated && session.isReachable
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

    private func notify(_ updates: [WatchVoiceUpdate]) {
        guard let newest = updates.first else { return }
        if WKApplication.shared().applicationState == .active {
            WKInterfaceDevice.current().play(newest.phase == .finished ? .success : .failure)
        } else {
            for update in updates {
                let content = UNMutableNotificationContent()
                content.title = String(localized: update.phase == .finished ? "Poki task finished" : "Poki task needs attention")
                content.body = String(localized: "Open Poki to see the result.")
                content.sound = .default
                let request = UNNotificationRequest(identifier: update.id.uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    private func notify(_ update: WatchVoiceUpdate) {
        notify([update])
    }

    private func receiveContext(_ context: [String: Any]) {
        if let data = context[WatchVoiceRequest.contextKey] as? Data,
           let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: data) {
            receive(update)
        }
        if let remoteData = context[WatchVoiceRemote.contextKey] as? Data,
           let snapshot = try? JSONDecoder().decode(WatchVoiceRemoteSnapshot.self, from: remoteData) {
            applyRemoteSnapshot(snapshot)
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
                remoteReachable = false
                self.cancelInFlightDelivery()
                self.failDelivery(.sessionInactive)
                for task in backgroundTasks { task.setTaskCompletedWithSnapshot(false) }
                backgroundTasks.removeAll()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            updateReachability()
            if remoteReachable {
                remoteTransportError = nil
                flushPendingEnd()
                refreshRemoteState()
            }
            updateActiveSync()
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

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let snapshotData = message[WatchVoiceRemote.snapshotKey] as? Data,
           let snapshot = try? JSONDecoder().decode(WatchVoiceRemoteSnapshot.self, from: snapshotData) {
            Task { @MainActor in applyRemoteSnapshot(snapshot) }
        }
        if let meterData = message[WatchVoiceRemote.meterKey] as? Data,
           let meter = try? JSONDecoder().decode(WatchVoiceRemoteMeter.self, from: meterData) {
            Task { @MainActor in applyRemoteMeter(meter) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        if let resultData = userInfo[WatchVoiceRemote.resultKey] as? Data,
           let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: resultData) {
            Task { @MainActor in
                self.persistRemoteState(ingesting: [update])
                self.finishBackgroundTasks()
            }
        }
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
