#if POKI_WATCH
import Foundation
import XCTest
@testable import Poki

@MainActor
final class WatchVoiceBackgroundTests: XCTestCase {
    private var tempDirectory: URL!
    private var savedDefaults: [String: Any?] = [:]
    private var savedSetup: SetupState!
    private var savedCustomProviders: [CustomProvider] = []
    private var savedLanguage = AppLocalization.system

    private let trackedKeys = [
        "wantsOn",
        "relayAddress",
        "relayEnabled",
        "chat.provider",
        "chat.model.custom",
        CustomProviders.selectedKey,
    ]

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "WatchVoiceBackgroundTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        savedLanguage = AppLocalization.shared.preference
        AppLocalization.shared.preference = "en"
        savedSetup = SetupState.load()
        savedCustomProviders = CustomProviders.all
        for key in trackedKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        try ModelKeys.saveCustom(address: "http://127.0.0.1:29199/v1", model: "poki-mock", typedKey: "")
    }

    override func tearDown() async throws {
        if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        for current in CustomProviders.all where !savedCustomProviders.contains(where: { $0.id == current.id }) {
            CustomProviders.remove(current.id)
        }
        savedSetup?.save()
        AppLocalization.shared.preference = savedLanguage
    }

    private func makeApp(wantsOn: Bool, sessionOn: Bool) -> (AppModel, ChatModel) {
        UserDefaults.standard.set(wantsOn, forKey: "wantsOn")
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), automation: FakeAutomation())
        app.setup.loopback = .proxy
        app.loopback.simulate(.working(ms: 5))
        if sessionOn {
            app.startSession()
        }
        let chat = ChatModel(app: app)
        return (app, chat)
    }

    func testBackgroundColdWakeTurnsOnWantedSessionAndExecutesTask() async throws {
        let (app, chat) = makeApp(wantsOn: true, sessionOn: false)
        defer { app.stopSession() }
        app.wentToBackground()
        XCTAssertFalse(app.sessionOn, "Background cold wake starts with sessionOn == false until activated")

        var published: [WatchVoiceUpdate] = []
        var ranTranscript: String?
        let phone = WatchVoicePhone(
            app: app,
            chat: chat,
            journal: tempDirectory.appending(path: "WatchVoice.json"),
            isProtectedDataAvailable: { true },
            isScreenLocked: { false },
            transcribeRecording: { _ in "Open Calculator" },
            executeTask: { transcript, _ in
                ranTranscript = transcript
                return ("Opened Calculator.", true)
            },
            onPublish: { published.append($0) },
            activateSession: false
        )

        let id = UUID()
        let receipt = phone.handleRequest(.submit(id: id, audio: Data("m4a".utf8)))
        XCTAssertEqual(receipt?.phase, .received)
        await phone.waitForCurrentWork()

        XCTAssertTrue(app.sessionOn, "Background wake must turn Poki on when wantsOn is true")
        XCTAssertEqual(ranTranscript, "Open Calculator")
        XCTAssertEqual(published.map(\.phase), [.running, .finished])
        XCTAssertEqual(published.last?.text, "Opened Calculator.")
    }

    func testLockedPhoneParksTaskPostsUnlockNoticeAndResumesAfterUnlock() async throws {
        let (app, chat) = makeApp(wantsOn: true, sessionOn: true)
        defer { app.stopSession() }
        app.wentToBackground()

        var protectedDataAvailable = false
        var screenLocked = true
        var published: [WatchVoiceUpdate] = []
        var postedNotices: [UUID] = []
        var clearedNotices: [UUID] = []
        var executedCount = 0

        let phone = WatchVoicePhone(
            app: app,
            chat: chat,
            journal: tempDirectory.appending(path: "WatchVoice.json"),
            isProtectedDataAvailable: { protectedDataAvailable },
            isScreenLocked: { screenLocked },
            transcribeRecording: { _ in "Open Calculator" },
            executeTask: { _, _ in
                executedCount += 1
                return ("Opened Calculator.", true)
            },
            postUnlockNotice: { postedNotices.append($0) },
            clearUnlockNotice: { clearedNotices.append($0) },
            onPublish: { published.append($0) },
            activateSession: false
        )

        let id = UUID()
        let receipt = phone.handleRequest(.submit(id: id, audio: Data("m4a".utf8)))
        await phone.waitForCurrentWork()

        XCTAssertEqual(receipt?.phase, .waitingForUnlock, "Locked phone must acknowledge receipt and prompt for unlock instead of blocking")
        XCTAssertEqual(postedNotices, [id], "Locked phone must post a local unlock reminder")
        XCTAssertEqual(executedCount, 0, "Task must not run while the phone is locked")

        let retryReceipt = phone.handleRequest(.submit(id: id, audio: Data("m4a".utf8)))
        XCTAssertEqual(retryReceipt?.phase, .waitingForUnlock, "Duplicate delivery while locked must stay idempotent")

        protectedDataAvailable = true
        screenLocked = false
        phone.handleUnlockSignal()
        await phone.waitForCurrentWork()

        XCTAssertEqual(clearedNotices, [id], "Unlocking the phone must clear the unlock reminder")
        XCTAssertEqual(executedCount, 1, "Task must resume exactly once after unlock")
        XCTAssertEqual(published.last?.phase, .finished)
        XCTAssertEqual(published.last?.text, "Opened Calculator.")
    }

    func testLockedScreenBeforeProtectedDataLocksStillWaitsForUnlock() async throws {
        let (app, chat) = makeApp(wantsOn: true, sessionOn: true)
        defer { app.stopSession() }
        app.wentToBackground()

        var screenLocked = true
        var postedNotices: [UUID] = []
        var executedCount = 0
        var published: [WatchVoiceUpdate] = []

        let phone = WatchVoicePhone(
            app: app,
            chat: chat,
            journal: tempDirectory.appending(path: "WatchVoice.json"),
            isProtectedDataAvailable: { true },
            isScreenLocked: { screenLocked },
            transcribeRecording: { _ in "Open Calculator" },
            executeTask: { _, _ in
                executedCount += 1
                return ("Opened Calculator.", true)
            },
            postUnlockNotice: { postedNotices.append($0) },
            onPublish: { published.append($0) },
            activateSession: false
        )

        let id = UUID()
        let receipt = phone.handleRequest(.submit(id: id, audio: Data("m4a".utf8)))
        await phone.waitForCurrentWork()

        XCTAssertEqual(receipt?.phase, .waitingForUnlock)
        XCTAssertEqual(postedNotices, [id])
        XCTAssertEqual(executedCount, 0)

        screenLocked = false
        phone.handleUnlockSignal()
        await phone.waitForCurrentWork()

        XCTAssertEqual(executedCount, 1)
        XCTAssertEqual(published.last?.phase, .finished)
    }

    func testWaitingForUnlockResumesAcrossPhoneRestartOnceUnlocked() async throws {
        let journal = tempDirectory.appending(path: "WatchVoice.json")
        let (app1, chat1) = makeApp(wantsOn: true, sessionOn: true)
        defer { app1.stopSession() }
        app1.wentToBackground()

        let firstPhone = WatchVoicePhone(
            app: app1,
            chat: chat1,
            journal: journal,
            isProtectedDataAvailable: { false },
            isScreenLocked: { true },
            transcribeRecording: { _ in "Open Calculator" },
            executeTask: { _, _ in ("Opened Calculator.", true) },
            activateSession: false
        )

        let id = UUID()
        let receipt = firstPhone.handleRequest(.submit(id: id, audio: Data("m4a".utf8)))
        await firstPhone.waitForCurrentWork()
        XCTAssertEqual(receipt?.phase, .waitingForUnlock)

        let (app2, chat2) = makeApp(wantsOn: true, sessionOn: false)
        defer { app2.stopSession() }
        app2.wentToBackground()
        var published: [WatchVoiceUpdate] = []
        var executedCount = 0
        let relaunchedPhone = WatchVoicePhone(
            app: app2,
            chat: chat2,
            journal: journal,
            isProtectedDataAvailable: { true },
            isScreenLocked: { false },
            transcribeRecording: { _ in "Open Calculator" },
            executeTask: { _, _ in
                executedCount += 1
                return ("Opened Calculator.", true)
            },
            onPublish: { published.append($0) },
            activateSession: false
        )

        let status = relaunchedPhone.handleRequest(.status(id: id))
        await relaunchedPhone.waitForCurrentWork()

        XCTAssertNotEqual(status?.phase, .blocked, "A persisted waitingForUnlock task must resume after unlock rather than fail as interrupted")
        XCTAssertEqual(executedCount, 1)
        XCTAssertEqual(published.last?.phase, .finished)
    }

    func testOwnerTurnedOffOrPausedRefusesBackgroundExecution() async throws {
        let (app, chat) = makeApp(wantsOn: false, sessionOn: false)
        defer { app.stopSession() }
        app.wentToBackground()

        var published: [WatchVoiceUpdate] = []
        let phone = WatchVoicePhone(
            app: app,
            chat: chat,
            journal: tempDirectory.appending(path: "WatchVoice.json"),
            isProtectedDataAvailable: { true },
            isScreenLocked: { false },
            transcribeRecording: { _ in "Open Calculator" },
            executeTask: { _, _ in ("Should not run", true) },
            onPublish: { published.append($0) },
            activateSession: false
        )

        _ = phone.handleRequest(.submit(id: UUID(), audio: Data("m4a".utf8)))
        await phone.waitForCurrentWork()

        XCTAssertFalse(app.sessionOn)
        XCTAssertEqual(published.last?.phase, .blocked)
    }

    func testForceQuitDeliveryFailureDoesNotStayStuckInSending() {
        let status = WatchVoicePendingStatus.resolve(
            hasPending: true,
            sending: false,
            update: nil,
            failure: .phoneUnavailable
        )
        XCTAssertEqual(status, .deliveryFailed(.phoneUnavailable), "Failed delivery must leave Sending state and show an explicit error")

        let noExplicitFailure = WatchVoicePendingStatus.resolve(
            hasPending: true,
            sending: false,
            update: nil,
            failure: nil
        )
        XCTAssertEqual(noExplicitFailure, .deliveryFailed(.deliveryFailed), "Idle pending request without a phone receipt must not claim it is sending")
    }

    func testWCErrorCodeMapsForceQuitAndTimeoutToExplicitFailures() {
        XCTAssertEqual(WatchVoiceDeliveryFailure.from(wcErrorCode: 7007), .phoneUnavailable)
        XCTAssertEqual(WatchVoiceDeliveryFailure.from(wcErrorCode: 7011), .phoneUnavailable)
        XCTAssertEqual(WatchVoiceDeliveryFailure.from(wcErrorCode: 7014), .phoneUnavailable)
        XCTAssertEqual(WatchVoiceDeliveryFailure.from(wcErrorCode: 7012), .timedOut)
        XCTAssertEqual(WatchVoiceDeliveryFailure.from(wcErrorCode: 7017), .timedOut)
        XCTAssertEqual(WatchVoiceDeliveryFailure.from(wcErrorCode: 7018), .companionNotInstalled)
        XCTAssertEqual(WatchVoiceDeliveryFailure.from(wcErrorCode: 7004), .sessionInactive)
    }

    func testPhaseProgressionPreservesRawValuesAndDropsStaleUpdates() {
        XCTAssertEqual(WatchVoiceUpdate.Phase.received.rawValue, 0)
        XCTAssertEqual(WatchVoiceUpdate.Phase.running.rawValue, 1)
        XCTAssertEqual(WatchVoiceUpdate.Phase.finished.rawValue, 2)
        XCTAssertEqual(WatchVoiceUpdate.Phase.blocked.rawValue, 3)
        XCTAssertEqual(WatchVoiceUpdate.Phase.waitingForUnlock.rawValue, 4)

        XCTAssertTrue(WatchVoiceUpdate.Phase.received.canAdvance(to: .waitingForUnlock))
        XCTAssertTrue(WatchVoiceUpdate.Phase.waitingForUnlock.canAdvance(to: .running))
        XCTAssertTrue(WatchVoiceUpdate.Phase.running.canAdvance(to: .finished))
        XCTAssertFalse(WatchVoiceUpdate.Phase.waitingForUnlock.canAdvance(to: .received))
        XCTAssertFalse(WatchVoiceUpdate.Phase.running.canAdvance(to: .waitingForUnlock))
        XCTAssertFalse(WatchVoiceUpdate.Phase.finished.canAdvance(to: .blocked))
    }
}
#endif
