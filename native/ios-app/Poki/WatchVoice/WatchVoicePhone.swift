#if POKI_WATCH
import Foundation
import UIKit
import WatchConnectivity

@MainActor
final class WatchVoicePhone: NSObject, WCSessionDelegate {
    private let app: AppModel
    private let chat: ChatModel
    private let session = WCSession.default
    private let journal = URL.applicationSupportDirectory.appending(path: "WatchVoice.json")
    private var updates: [UUID: WatchVoiceUpdate] = [:]
    private var journalAvailable = true
    private var activeID: UUID?
    private var work: Task<Void, Never>?
    private var latestTaskContext: Data?
    private var latestRemoteContext: Data?
    private var handlingRemoteCommand = false
    private var remoteBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private lazy var remoteHost: WatchVoiceRemoteHost = {
        let host = WatchVoiceRemoteHost(app: app, chat: chat, isWatchTaskBusy: { [weak self] in self?.activeID != nil })
        host.onSnapshot = { [weak self] snapshot in self?.publishRemoteSnapshot(snapshot) }
        host.onMeter = { [weak self] meter in self?.publishRemoteMeter(meter) }
        host.onResult = { [weak self] result in self?.storeRemoteResult(result) }
        return host
    }()

    init(app: AppModel, chat: ChatModel) {
        self.app = app
        self.chat = chat
        super.init()
        do {
            let saved = try Data(contentsOf: journal)
            updates = try JSONDecoder().decode([UUID: WatchVoiceUpdate].self, from: saved)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // The first accepted request creates the journal.
        } catch {
            // An unreadable journal cannot safely distinguish a new request from a retry.
            journalAvailable = false
        }
        remoteHost.startObserving()
        session.delegate = self
        session.activate()
    }

    private func store(_ update: WatchVoiceUpdate) throws {
        guard journalAvailable else { throw CocoaError(.fileReadCorruptFile) }
        var next = updates
        next[update.id] = update
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: journal, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        updates = next
    }

    private func reply(to request: WatchVoiceRequest) -> Data {
        switch request {
        case .status(let id):
            return encodeUpdate(status(for: id))
        case .submit(let id, let audio):
            return encodeUpdate(accept(id, audio: audio))
        case .result(let id, let offset):
            return updates[id]?.resultChunk(at: offset) ?? Data()
        }
    }

    private func accept(_ id: UUID, audio: Data) -> WatchVoiceUpdate {
        if let existing = status(for: id) { return existing }
        guard !audio.isEmpty, audio.count <= WatchVoiceRequest.maxAudioBytes else {
            return blocked(id, "The recording is empty or too long. Record a shorter request.")
        }
        let receipt = WatchVoiceUpdate(id: id, phase: .received, text: nil)
        do {
            try store(receipt)
        } catch {
            return blocked(id, "Poki couldn’t save this request on iPhone. Check available storage and try again.")
        }
        AppLog.shared.add("watch", "Received Watch task \(id)")
        guard activeID == nil else {
            return complete(blocked(id, "Poki is handling another Watch task. Wait for it to finish and try again."))
        }
        activeID = id
        work = Task { await run(id, audio: audio) }
        return receipt
    }

    private func status(for id: UUID) -> WatchVoiceUpdate? {
        guard let update = updates[id], !update.phase.isTerminal, activeID != id else { return updates[id] }
        return complete(blocked(id, "Poki was interrupted on iPhone. Check what happened there before sending the task again."))
    }

    private func run(_ id: UUID, audio: Data) async {
        var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask(withName: "Poki Watch task") { [weak self] in
            self?.work?.cancel()
            if background != .invalid {
                UIApplication.shared.endBackgroundTask(background)
                background = .invalid
            }
        }
        defer {
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            work = nil
            activeID = nil
        }
        do {
            try checkReady()
            let transcript = try await Dictation.transcribe(recording: audio)
            try Task.checkCancellation()
            try checkReady()
            let running = WatchVoiceUpdate(id: id, phase: .running, text: nil)
            try store(running)
            publish(running)
            let task = ChatModel(app: app, kind: .handoff, requester: "Apple Watch", sessionID: id.uuidString)
            let result = await task.runDelegated(transcript)
            let update = WatchVoiceUpdate(id: id, phase: result.success == true ? .finished : .blocked,
                                          text: result.text)
            complete(update)
        } catch is CancellationError {
            complete(blocked(id, "iPhone stopped the background task. Check Poki on iPhone before trying again."))
        } catch let error as WatchVoiceStartError {
            complete(WatchVoiceUpdate(id: id, phase: .blocked, text: error.errorDescription))
        } catch let error as WatchVoiceSpeechError {
            complete(WatchVoiceUpdate(id: id, phase: .blocked, text: error.errorDescription))
        } catch {
            complete(blocked(id, "Poki couldn’t save the task on iPhone. Check available storage and try again."))
        }
    }

    private func checkReady() throws {
        guard UIApplication.shared.isProtectedDataAvailable else {
            throw WatchVoiceStartError(message: "Unlock your iPhone and open Poki, then try again.")
        }
        if let message = app.signer.installMessage { throw WatchVoiceStartError(text: message) }
        guard ModelKeys.hasUsableKey else {
            throw WatchVoiceStartError(message: "Choose a model in Poki’s settings on iPhone, then try again.")
        }
        guard !chat.running, !app.voice.isOn, ChatModel.delegatedBusy == nil else {
            throw WatchVoiceStartError(message: "Poki is busy on iPhone. Wait for the current task and try again.")
        }
        guard app.automationPath == .inProcess, app.sessionOn, !app.ownerPaused else {
            throw WatchVoiceStartError(message: "Turn on Poki with on-device automation on iPhone, then try again.")
        }
    }

    private func blocked(_ id: UUID, _ message: LocalizedStringResource) -> WatchVoiceUpdate {
        WatchVoiceUpdate(id: id, phase: .blocked, text: AppLocalization.text(message))
    }

    @discardableResult
    private func complete(_ update: WatchVoiceUpdate) -> WatchVoiceUpdate {
        let terminal: WatchVoiceUpdate
        do {
            try store(update)
            terminal = update
        } catch {
            terminal = blocked(update.id, "Poki couldn’t save the result on iPhone. Check the task there before trying again.")
            updates[update.id] = terminal
        }
        AppLog.shared.add("watch", "Watch task \(update.id) ended as \(terminal.phase)")
        publish(terminal)
        return terminal
    }

    private func publish(_ update: WatchVoiceUpdate) {
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        let data = encodeUpdate(update)
        guard !data.isEmpty else { return }
        if session.isReachable { session.sendMessageData(data, replyHandler: nil, errorHandler: nil) }
        if update.phase.isTerminal {
            latestTaskContext = data
            syncApplicationContext()
        }
    }

    private func storeRemoteResult(_ update: WatchVoiceUpdate) {
        do {
            try store(update)
        } catch {
            updates[update.id] = update
        }
    }

    private func publishRemoteSnapshot(_ snapshot: WatchVoiceRemoteSnapshot) {
        if !snapshot.state.isActiveCall && snapshot.state != .ending {
            endRemoteBackgroundTask()
        }
        guard !handlingRemoteCommand,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        latestRemoteContext = data
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage([WatchVoiceRemote.snapshotKey: data], replyHandler: nil, errorHandler: nil)
        }
        syncApplicationContext()
    }

    private func syncRemoteContext(_ snapshot: WatchVoiceRemoteSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        latestRemoteContext = data
        syncApplicationContext()
    }

    private func beginRemoteBackgroundTask() {
        guard remoteBackgroundTask == .invalid else { return }
        remoteBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Poki Watch voice remote") { [weak self] in
            Task { @MainActor in
                self?.endRemoteBackgroundTask()
            }
        }
    }

    private func endRemoteBackgroundTask() {
        guard remoteBackgroundTask != .invalid else { return }
        let id = remoteBackgroundTask
        remoteBackgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(id)
    }

    private func publishRemoteMeter(_ meter: WatchVoiceRemoteMeter) {
        guard session.activationState == .activated, session.isReachable,
              let data = try? JSONEncoder().encode(meter) else { return }
        session.sendMessage([WatchVoiceRemote.meterKey: data], replyHandler: nil, errorHandler: nil)
    }

    private func syncApplicationContext() {
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        var context: [String: Any] = [:]
        if let latestTaskContext { context[WatchVoiceRequest.contextKey] = latestTaskContext }
        if let latestRemoteContext { context[WatchVoiceRemote.contextKey] = latestRemoteContext }
        guard !context.isEmpty else { return }
        do {
            try session.updateApplicationContext(context)
        } catch {
            AppLog.shared.add("watch", "Watch application context sync deferred")
        }
    }

    private func encodeUpdate(_ update: WatchVoiceUpdate?) -> Data {
        guard let update else { return Data() }
        return (try? JSONEncoder().encode(update.forDelivery())) ?? Data()
    }

    private func handleRemoteMessage(_ message: [String: Any]) -> [String: Any] {
        guard let data = message[WatchVoiceRemote.commandKey] as? Data,
              data.count <= WatchVoiceRequest.maxMessageBytes,
              let command = try? JSONDecoder().decode(WatchVoiceRemoteCommand.self, from: data) else {
            return [:]
        }
        handlingRemoteCommand = true
        let reply = remoteHost.handle(command)
        handlingRemoteCommand = false
        if reply.snapshot.state.isActiveCall || reply.snapshot.state == .ending {
            beginRemoteBackgroundTask()
        } else {
            endRemoteBackgroundTask()
        }
        syncRemoteContext(reply.snapshot)
        AppLog.shared.add("watch", "Watch remote \(command.action) (\(command.requestID)) -> \(reply.outcome.rawValue), state \(reply.snapshot.state.rawValue) [\(reply.snapshot.epoch):\(reply.snapshot.sequence)]")
        guard let encoded = try? JSONEncoder().encode(reply) else { return [:] }
        return [WatchVoiceRemote.replyKey: encoded]
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData data: Data, replyHandler: @escaping (Data) -> Void) {
        guard data.count <= WatchVoiceRequest.maxMessageBytes,
              let request = try? JSONDecoder().decode(WatchVoiceRequest.self, from: data) else {
            replyHandler(Data())
            return
        }
        Task { @MainActor in replyHandler(self.reply(to: request)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in replyHandler(self.handleRemoteMessage(message)) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            guard activationState == .activated else { return }
            remoteHost.setMeterStreaming(session.isReachable)
            publishRemoteSnapshot(remoteHost.currentSnapshot())
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            remoteHost.setMeterStreaming(session.isReachable)
            if session.isReachable {
                publishRemoteSnapshot(remoteHost.currentSnapshot())
            }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            remoteHost.setMeterStreaming(session.isReachable)
            if session.isPaired, session.isWatchAppInstalled {
                syncRemoteContext(remoteHost.currentSnapshot())
            }
            if session.isReachable {
                publishRemoteSnapshot(remoteHost.currentSnapshot())
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

private struct WatchVoiceStartError: LocalizedError {
    let errorDescription: String?

    init(message: LocalizedStringResource) { errorDescription = AppLocalization.text(message) }
    init(text: String) { errorDescription = text }
}
#endif
