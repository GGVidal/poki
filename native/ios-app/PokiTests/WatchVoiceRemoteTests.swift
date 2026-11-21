import AVFAudio
import Foundation
import XCTest
@testable import Poki

private final class RemoteTestConnection: VoiceConnection, @unchecked Sendable {
    var onEvent: (@MainActor ([String: Any]) -> Void)?
    var onClosed: (@MainActor (String) -> Void)?
    private let lock = NSLock()
    private var localAudioEnabledStorage = true
    private var closedStorage = false
    private var connectErrorStorage: Error?
    private var remoteLevelStorage: Double = 0

    var localAudioEnabled: Bool { lock.withLock { localAudioEnabledStorage } }
    var closed: Bool { lock.withLock { closedStorage } }

    func setConnectError(_ error: Error?) { lock.withLock { connectErrorStorage = error } }
    func setRemoteLevel(_ level: Double) { lock.withLock { remoteLevelStorage = level } }

    @MainActor func connect(secret: String, base: URL?, microphone: Bool, direct: Bool) async throws {
        if let error = lock.withLock({ connectErrorStorage }) { throw error }
    }

    @MainActor func connectLive(microphone: Bool, direct: Bool, exchange: (String) async throws -> String) async throws {
        if let error = lock.withLock({ connectErrorStorage }) { throw error }
    }

    func hasRemoteSpeech() async -> Bool { lock.withLock { remoteLevelStorage > 0.005 } }
    func remoteAudioLevel() async -> Double? { lock.withLock { remoteLevelStorage } }
    func send(_ event: [String: Any]) -> Bool { true }
    func setRemoteVolume(_ value: Double) {}
    func setLocalAudioEnabled(_ enabled: Bool) { lock.withLock { localAudioEnabledStorage = enabled } }
    func diagnose(_ write: @escaping @MainActor (String) -> Void) {}
    @MainActor func close() { lock.withLock { closedStorage = true } }

    @MainActor func play(_ event: [String: Any]) { onEvent?(event) }
}

@MainActor
final class WatchVoiceRemoteTests: XCTestCase {
    private var previousBridge: VoiceBridge?
    private var previousRehearsal: Any?
    private var previousHold: Any?

    override func setUp() async throws {
        previousBridge = VoiceBridge.saved
        previousRehearsal = UserDefaults.standard.object(forKey: "pokiTalkRehearsal")
        previousHold = UserDefaults.standard.object(forKey: "pokiTalkHold")
        UserDefaults.standard.removeObject(forKey: "pokiTalkRehearsal")
        UserDefaults.standard.removeObject(forKey: "pokiTalkHold")
        URLProtocol.registerClass(BridgeStub.self)
    }

    override func tearDown() async throws {
        URLProtocol.unregisterClass(BridgeStub.self)
        VoiceBridge.saved = previousBridge
        if let previousRehearsal { UserDefaults.standard.set(previousRehearsal, forKey: "pokiTalkRehearsal") }
        else { UserDefaults.standard.removeObject(forKey: "pokiTalkRehearsal") }
        if let previousHold { UserDefaults.standard.set(previousHold, forKey: "pokiTalkHold") }
        else { UserDefaults.standard.removeObject(forKey: "pokiTalkHold") }
    }

    @MainActor
    private final class Harness {
        let time = FakeTime()
        let connection = RemoteTestConnection()
        let voice: VoiceModel
        var host: WatchVoiceRemoteHost!
        var snapshots: [WatchVoiceRemoteSnapshot] = []
        var fullResults: [WatchVoiceUpdate] = []
        var preparedCount = 0
        var foregroundRequestedCount = 0
        var isProtectedDataAvailable = true
        var isSetupReady = true
        var isBusy = false
        var hasMicrophonePermission = true
        var stepOverride: String?
        var toolGate: CheckedContinuation<PhoneAnswer, Never>?

        init(epoch: UInt64 = 10, bridgeAddress: String? = BridgeStub.address, suspendPhoneTool: Bool = false) {
            let conn = connection
            var ownerBox: Harness?
            voice = VoiceModel(
                clearTap: { _, _, _ in .clear },
                phoneTool: { _, _, _ in
                    if suspendPhoneTool {
                        return await withCheckedContinuation { continuation in
                            ownerBox?.toolGate = continuation
                        }
                    }
                    return ("ok", false, nil)
                },
                connection: { onEvent, onClosed in
                    conn.onEvent = onEvent
                    conn.onClosed = onClosed
                    return conn
                },
                time: time.clock
            )
            ownerBox = self
            if let bridgeAddress { _ = voice.setBridge(bridgeAddress) }
            host = WatchVoiceRemoteHost(
                voice: voice,
                environment: WatchVoiceRemoteEnvironment(
                    isProtectedDataAvailable: { [unowned self] in self.isProtectedDataAvailable },
                    isSetupReady: { [unowned self] in self.isSetupReady && self.voice.canTalkLive },
                    isBusy: { [unowned self] in self.isBusy },
                    hasMicrophonePermission: { [unowned self] in self.hasMicrophonePermission },
                    currentStep: { [unowned self] in self.stepOverride ?? self.voice.activeStepDescription },
                    prepareForVoice: { [unowned self] in self.preparedCount += 1 },
                    stopVoice: { [unowned self] in self.voice.stop() },
                    requestForegroundContinuation: { [unowned self] in self.foregroundRequestedCount += 1 },
                    now: { [unowned self] in self.time.now }
                ),
                epoch: epoch
            )
            host.onSnapshot = { [weak self] snapshot in
                self?.snapshots.append(snapshot)
            }
            host.onResult = { [weak self] result in
                self?.fullResults.append(result)
            }
            host.startObserving()
        }
    }

    func testStartMuteUnmuteAndEndLifecycleWithExplicitMuteIdempotency() async throws {
        let h = Harness()

        let startReply = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(startReply.outcome, .accepted)
        XCTAssertEqual(startReply.snapshot.state, .connecting)
        let callID = try XCTUnwrap(startReply.snapshot.callID)
        XCTAssertFalse(startReply.snapshot.isMuted)
        XCTAssertEqual(h.preparedCount, 1)

        await h.time.settle()
        h.connection.play(["type": "session.created"])
        await h.time.settle()

        let listening = h.host.currentSnapshot()
        XCTAssertEqual(listening.state, .listening)
        XCTAssertEqual(listening.callID, callID)
        XCTAssertTrue(listening.transportConnected)
        XCTAssertTrue(listening.inputReady)

        // Dynamic Island voice states flow through without renaming.
        h.connection.play(["type": "input_audio_buffer.speech_stopped"])
        await h.time.settle()
        XCTAssertEqual(h.host.currentSnapshot().state, .thinking)

        h.connection.play(["type": "output_audio_buffer.started"])
        await h.time.settle()
        XCTAssertEqual(h.host.currentSnapshot().state, .speaking)

        h.connection.play(["type": "output_audio_buffer.stopped"])
        await h.time.settle()
        XCTAssertEqual(h.host.currentSnapshot().state, .listening)

        // Explicit mute sets muted once; sending setMuted(true) again never toggles back.
        let mute1 = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .setMuted(true), targetCallID: callID))
        XCTAssertEqual(mute1.outcome, .accepted)
        XCTAssertEqual(mute1.snapshot.state, .muted)
        XCTAssertTrue(mute1.snapshot.isMuted)
        XCTAssertFalse(mute1.snapshot.inputReady)
        XCTAssertFalse(h.connection.localAudioEnabled)

        let mute2 = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .setMuted(true), targetCallID: callID))
        XCTAssertEqual(mute2.outcome, .noChange)
        XCTAssertEqual(mute2.snapshot.state, .muted)
        XCTAssertTrue(mute2.snapshot.isMuted)
        XCTAssertFalse(h.connection.localAudioEnabled)

        let unmute = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .setMuted(false), targetCallID: callID))
        XCTAssertEqual(unmute.outcome, .accepted)
        XCTAssertEqual(unmute.snapshot.state, .listening)
        XCTAssertFalse(unmute.snapshot.isMuted)
        XCTAssertTrue(unmute.snapshot.inputReady)
        XCTAssertTrue(h.connection.localAudioEnabled)

        // End with mismatched call ID is rejected without ending the active call.
        let wrongEnd = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .end, targetCallID: "stale-call"))
        XCTAssertEqual(wrongEnd.outcome, .callChanged)
        XCTAssertTrue(h.voice.isOn)

        // End with matching call ID ends the active call.
        let end = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .end, targetCallID: callID))
        XCTAssertEqual(end.outcome, .accepted)
        XCTAssertEqual(end.snapshot.state, .idle)
        XCTAssertNil(end.snapshot.callID)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertTrue(h.connection.closed)
    }

    func testExpiredCommandDoesNotExecuteAndDuplicateRequestReturnsCachedReply() async throws {
        let h = Harness()

        let expiredStart = WatchVoiceRemoteCommand(
            issuedAt: h.time.now.addingTimeInterval(-11),
            action: .start
        )
        let expiredReply = h.host.handle(expiredStart)
        XCTAssertEqual(expiredReply.outcome, .expired)
        XCTAssertEqual(expiredReply.requestID, expiredStart.requestID)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertEqual(h.preparedCount, 0)

        let futureStart = WatchVoiceRemoteCommand(
            issuedAt: h.time.now.addingTimeInterval(3),
            action: .start
        )
        let futureReply = h.host.handle(futureStart)
        XCTAssertEqual(futureReply.outcome, .expired)
        XCTAssertFalse(h.voice.isOn)

        let startCmd = WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start)
        let firstReply = h.host.handle(startCmd)
        XCTAssertEqual(firstReply.outcome, .accepted)
        XCTAssertEqual(h.preparedCount, 1)

        // Even after advancing past the command window, retrying the same requestID returns the original cached reply without re-executing.
        await h.time.advance(15)
        let duplicateReply = h.host.handle(startCmd)
        XCTAssertEqual(duplicateReply, firstReply)
        XCTAssertEqual(h.preparedCount, 1)

        let callID = try XCTUnwrap(firstReply.snapshot.callID)
        let endCmd = WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .end, targetCallID: callID)
        let endFirst = h.host.handle(endCmd)
        XCTAssertEqual(endFirst.outcome, .accepted)

        // Start a second call, then replay the first call's end requestID: cached reply returns without ending the second call.
        let secondStart = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(secondStart.outcome, .accepted)
        XCTAssertTrue(h.voice.isOn)
        let replayedEnd = h.host.handle(endCmd)
        XCTAssertEqual(replayedEnd, endFirst)
        XCTAssertTrue(h.voice.isOn)
        h.voice.stop()
    }

    func testStartReturnsRequiresForegroundWhenMicMissingOrProtectedDataUnavailable() {
        let h = Harness()
        h.hasMicrophonePermission = false

        let noMic = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(noMic.outcome, .requiresForeground)
        XCTAssertTrue(noMic.snapshot.requiresForeground)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertEqual(h.foregroundRequestedCount, 1)

        h.hasMicrophonePermission = true
        h.isProtectedDataAvailable = false

        let locked = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(locked.outcome, .requiresForeground)
        XCTAssertTrue(locked.snapshot.requiresForeground)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertEqual(h.foregroundRequestedCount, 2)
    }

    func testBackgroundAudioRestrictionDetectedAsForegroundRequired() {
        let restricted = NSError(
            domain: NSOSStatusErrorDomain,
            code: AVAudioSession.ErrorCode.cannotStartPlaying.rawValue
        )
        XCTAssertTrue(VoiceModel.isBackgroundAudioRestriction(restricted))
        let network = URLError(.timedOut)
        XCTAssertFalse(VoiceModel.isBackgroundAudioRestriction(network))
    }

    func testReducerDropsStaleSnapshotsByEpochAndSequenceAndFiltersMeterWindow() {
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        func snap(epoch: UInt64, seq: UInt64, state: WatchVoiceCallState, callID: String? = "call-1") -> WatchVoiceRemoteSnapshot {
            WatchVoiceRemoteSnapshot(
                epoch: epoch,
                sequence: seq,
                state: state,
                callID: callID,
                isMuted: state == .muted,
                transportConnected: state == .listening || state == .muted,
                inputReady: state == .listening,
                requiresForeground: false,
                updatedAt: baseTime,
                detail: nil
            )
        }

        var reducer = WatchVoiceRemoteStateReducer()
        XCTAssertTrue(reducer.apply(snapshot: snap(epoch: 2, seq: 5, state: .listening)))
        // Older sequence in same epoch is dropped.
        XCTAssertFalse(reducer.apply(snapshot: snap(epoch: 2, seq: 4, state: .connecting)))
        XCTAssertEqual(reducer.latestSnapshot?.state, .listening)
        // Duplicate (same epoch and sequence) is dropped.
        XCTAssertFalse(reducer.apply(snapshot: snap(epoch: 2, seq: 5, state: .muted)))
        XCTAssertEqual(reducer.latestSnapshot?.state, .listening)
        // Older epoch with higher sequence is dropped.
        XCTAssertFalse(reducer.apply(snapshot: snap(epoch: 1, seq: 99, state: .idle, callID: nil)))
        XCTAssertEqual(reducer.latestSnapshot?.state, .listening)
        // Newer epoch with sequence 1 supersedes older epoch.
        XCTAssertTrue(reducer.apply(snapshot: snap(epoch: 3, seq: 1, state: .muted, callID: "call-2")))
        XCTAssertEqual(reducer.latestSnapshot?.state, .muted)
        XCTAssertEqual(reducer.latestSnapshot?.epoch, 3)

        // Meter matching active epoch, callID, and [-0.5, 1.2]s window updates level.
        let validMeter = WatchVoiceRemoteMeter(epoch: 3, callID: "call-2", level: 180, timestamp: baseTime.addingTimeInterval(-0.4))
        XCTAssertTrue(reducer.apply(meter: validMeter, now: baseTime))
        XCTAssertEqual(reducer.meterLevel, 180)

        // Meter from stale timestamp or wrong callID is rejected.
        let oldMeter = WatchVoiceRemoteMeter(epoch: 3, callID: "call-2", level: 50, timestamp: baseTime.addingTimeInterval(-1.5))
        XCTAssertFalse(reducer.apply(meter: oldMeter, now: baseTime))
        let wrongCallMeter = WatchVoiceRemoteMeter(epoch: 3, callID: "call-1", level: 20, timestamp: baseTime)
        XCTAssertFalse(reducer.apply(meter: wrongCallMeter, now: baseTime))
        XCTAssertEqual(reducer.meterLevel, 180)
    }

    func testLiveStepAndLongResultUseSharedChunkedDelivery() async throws {
        let h = Harness(bridgeAddress: BridgeStub.liveAddress, suspendPhoneTool: true)
        let start = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(start.outcome, .accepted)
        let callID = try XCTUnwrap(start.snapshot.callID)
        await h.time.settle()
        h.connection.play(["type": "session.started"])
        await h.time.settle()

        // Running open_app emits a one-line currentStep naming the app.
        h.connection.play([
            "type": "response.event",
            "delegation_id": "d1",
            "event": [
                "type": "response.output_item.done",
                "item": [
                    "type": "function_call",
                    "call_id": "call-open-wechat",
                    "name": "open_app",
                    "arguments": #"{"app":"WeChat"}"#,
                ],
            ],
        ])
        await h.time.settle()

        let duringStep = h.host.currentSnapshot()
        XCTAssertEqual(duringStep.state, .thinking)
        XCTAssertEqual(duringStep.currentStep, "Opening WeChat")

        h.toolGate?.resume(returning: ("opened WeChat", false, nil))
        h.toolGate = nil
        await h.time.settle()

        // Long spoken answer (> 4096 UTF-8 bytes) delivers a preview with fullTextBytes in snapshot
        // while storing the complete text for #591 chunked retrieval.
        let longText = String(repeating: "Detailed result line 漢字 e\u{0301}.\n", count: 220) + "Final marker."
        XCTAssertGreaterThan(longText.utf8.count, 4_096)
        h.connection.play(["type": "session.output_transcript.delta", "delta": longText, "start_ms": 0, "end_ms": 900])
        h.connection.play(["type": "response.event", "delegation_id": "d1", "event": ["type": "response.completed", "response": ["id": "r1"]]])
        await h.time.settle()

        // Ending a Live session transitions through `.ending` until `session.closed` returns `.idle`.
        let end = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .end, targetCallID: callID))
        XCTAssertEqual(end.outcome, .accepted)
        XCTAssertEqual(end.snapshot.state, .ending)

        let delivered = try XCTUnwrap(end.snapshot.latestResult)
        XCTAssertEqual(delivered.phase, .finished)
        XCTAssertEqual(delivered.fullTextBytes, longText.utf8.count)
        XCTAssertNotEqual(delivered.text, longText)

        let storedFull = try XCTUnwrap(h.fullResults.first(where: { $0.id == delivered.id }))
        var assembled = Data()
        while assembled.count < longText.utf8.count {
            let chunk = storedFull.resultChunk(at: assembled.count)
            XCTAssertFalse(chunk.isEmpty)
            assembled.append(chunk)
        }
        XCTAssertEqual(String(data: assembled, encoding: .utf8), longText)

        h.connection.play(["type": "session.closed", "reason": "done"])
        await h.time.settle()
        XCTAssertEqual(h.host.currentSnapshot().state, .idle)
        XCTAssertNil(h.host.currentSnapshot().currentStep)
    }

    func testUnexpectedConnectionLossEmitsSingleBlockedResult() async throws {
        let h = Harness()
        let start = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(start.outcome, .accepted)
        await h.time.settle()
        h.connection.play(["type": "session.created"])
        await h.time.settle()

        h.connection.onClosed?("network dropped")
        await h.time.settle()

        let failed = h.host.currentSnapshot()
        XCTAssertEqual(failed.state, .failed)
        let delivered = try XCTUnwrap(failed.latestResult)
        XCTAssertEqual(delivered.phase, .blocked)
        XCTAssertEqual(h.fullResults.count, 1)
        XCTAssertEqual(h.fullResults.first?.id, delivered.id)

        // Querying state again keeps the same failure record without emitting a duplicate.
        let reread = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .state))
        XCTAssertEqual(reread.snapshot.latestResult?.id, delivered.id)
        XCTAssertEqual(h.fullResults.count, 1)
    }

    func testLocalToneSynthesisProducesValidDistinctWavBuffers() {
        let cues: [WatchVoiceCue] = [.start, .mute, .unmute, .end]
        let buffers = cues.map(WatchVoiceTone.wavData(for:))
        for data in buffers {
            XCTAssertGreaterThan(data.count, 44)
            XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        }
        XCTAssertEqual(Set(buffers).count, cues.count)
    }
}
