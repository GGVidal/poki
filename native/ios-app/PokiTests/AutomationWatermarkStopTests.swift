import PokiCore
import XCTest
@testable import Poki

/// Faithful in-process WDA transport mirroring `InProcessWDA`'s real session contract:
/// - `POST /session` calls `InProcessWDA.openThroughGate { session.prepare() }` and returns `inprocess-<generation>`.
/// - Requests carrying a stale session id (after `session.close()`) get HTTP 404 `invalid session id`.
/// - Tracks foreground app transitions (starting in Poki, switching to Settings on launch/activate, returning to Poki).
final class InProcessContractTransport: HTTPTransport, @unchecked Sendable {
    private let session: FakeAutomation
    private let pokiBundle: String
    private let beforeSource: (@Sendable (Int) async -> Void)?
    private let beforeActivate: (@Sendable (String) async -> Void)?
    private let lock = NSLock()
    private var frontBundle: String
    private var reads = 0
    private var activations: [String] = []
    private var sessionCreates = 0

    var screenReads: Int { lock.withLock { reads } }
    var activatedApps: [String] { lock.withLock { activations } }
    var postSessionCalls: Int { lock.withLock { sessionCreates } }

    init(
        session: FakeAutomation,
        pokiBundle: String = Bundle.main.bundleIdentifier ?? "nz.zheha.poki",
        beforeSource: (@Sendable (Int) async -> Void)? = nil,
        beforeActivate: (@Sendable (String) async -> Void)? = nil
    ) {
        self.session = session
        self.pokiBundle = pokiBundle
        self.frontBundle = pokiBundle
        self.beforeSource = beforeSource
        self.beforeActivate = beforeActivate
    }

    func send(method: String, url: URL, body: Data?, timeout: Double) async throws -> (status: Int, body: Data) {
        let components = url.path.split(separator: "/").map(String.init)
        let sessionID: String?
        let path: String
        if components.count >= 2, components[0] == "session" {
            sessionID = components[1]
            path = "/" + components.dropFirst(2).joined(separator: "/")
        } else {
            sessionID = nil
            path = url.path
        }

        if method == "POST", path == "/session" {
            lock.withLock { sessionCreates += 1 }
            let prepared = InProcessWDA.openThroughGate { session.prepare() }
            guard prepared["ok"] as? Bool == true else {
                let msg = "the automation session could not be opened: \(prepared["code"] ?? "unknown")"
                return (500, (["value": ["error": "session not created", "message": .string(msg)]] as JSON).data())
            }
            return (200, (["value": ["sessionId": .string("inprocess-\(session.generation)")]] as JSON).data())
        }

        if method == "DELETE", sessionID != nil, path == "/" {
            return (200, (["value": .null] as JSON).data())
        }

        if let sessionID {
            let expected = "inprocess-\(session.generation)"
            if !session.isOpen || sessionID != expected {
                let msg = "the automation session \(sessionID) has ended (now generation \(session.generation))"
                return (404, (["value": ["error": "invalid session id", "message": .string(msg)]] as JSON).data())
            }
        }

        let value: JSON
        switch "\(method) \(path)" {
        case "GET /status":
            value = ["ready": true]
        case "GET /wda/locked":
            value = false
        case "GET /wda/screen":
            value = ["screenSize": ["width": 390, "height": 844]]
        case "GET /wda/activeAppInfo":
            let bundle = lock.withLock { frontBundle }
            let name = bundle == pokiBundle ? "Poki" : "Settings"
            value = ["bundleId": .string(bundle), "name": .string(name)]
        case "POST /wda/apps/launch", "POST /wda/apps/activate":
            if let body, let bundle = (try? JSON.parse(body))?["bundleId"]?.string {
                await beforeActivate?(bundle)
                lock.withLock {
                    frontBundle = bundle
                    activations.append(bundle)
                }
            }
            value = .null
        case "GET /screenshot":
            value = .string("iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAADklEQVR4nGP4DwYMEAoAU7oL9ZisIGcAAAAASUVORK5CYII=")
        case "GET /source":
            let readIndex = lock.withLock { () -> Int in
                reads += 1
                return reads
            }
            await beforeSource?(readIndex)
            // Re-check session after any async wait, matching InProcessWDA checking native session.
            if let sessionID, (!session.isOpen || sessionID != "inprocess-\(session.generation)") {
                return (404, (["value": ["error": "invalid session id", "message": "the automation session ended"]] as JSON).data())
            }
            let bundle = lock.withLock { frontBundle }
            let appName = bundle == pokiBundle ? "Poki" : "Settings"
            value = .string(#"<AppiumAUT><XCUIElementTypeApplication name="\#(appName)" label="\#(appName)" x="0" y="0" width="390" height="844"><XCUIElementTypeButton name="General" label="General" x="16" y="100" width="358" height="44" /></XCUIElementTypeApplication></AppiumAUT>"#)
        case "POST /appium/settings":
            value = .null
        default:
            value = .null
        }
        return (200, (["value": value] as JSON).data())
    }
}

@MainActor
final class AutomationWatermarkStopTests: XCTestCase {
    private let defaultsKeys = [
        "chat.provider", "chat.customURL", "chat.customModel",
        "custom.providers", "chat.customProvider", "chat.model.custom",
        "relayAddress", "relayEnabled", "chatEngine",
    ]
    private var savedDefaults: [Any?] = []
    private var savedSetup: SetupState!
    private var savedAllowance: Any?
    private var savedLanguage = AppLocalization.system
    private var model: AppModel!
    private var session: FakeAutomation!
    private var launcher: FakeLauncher!
    private var tempFolder: URL!
    private var suiteName: String!

    override func setUp() async throws {
        try XCTSkipUnless(AutomationPath.current == .inProcess, "Poki Runner path")
        InProcessWDA.gate.withLock {
            $0 = InProcessWDA.OpenGate()
            $0.startedThisBoot = true
        }
        savedLanguage = AppLocalization.shared.preference
        AppLocalization.shared.preference = "en"
        savedAllowance = UserDefaults.standard.object(forKey: AutomationAllowance.key)
        UserDefaults.standard.removeObject(forKey: AutomationAllowance.key)
        savedSetup = SetupState.load()
        savedDefaults = defaultsKeys.map { UserDefaults.standard.object(forKey: $0) }
        UserDefaults.standard.removeObject(forKey: "chatEngine")
        tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent("WatermarkStop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        suiteName = "WatermarkStop-\(UUID().uuidString)"
        session = FakeAutomation()
        launcher = FakeLauncher()
    }

    override func tearDown() async throws {
        session?.answer(nil)
        session?.releasePause()
        model?.stopSession()
        for (key, value) in zip(defaultsKeys, savedDefaults) {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.set(savedAllowance, forKey: AutomationAllowance.key)
        AppLocalization.shared.preference = savedLanguage
        savedSetup?.save()
        if let suiteName { UserDefaults().removePersistentDomain(forName: suiteName) }
        if let tempFolder { try? FileManager.default.removeItem(at: tempFolder) }
    }

    private func makeHarness(
        system major: Int = 27,
        server: FakeCompletions,
        beforeSource: (@Sendable (Int) async -> Void)? = nil,
        beforeActivate: (@Sendable (String) async -> Void)? = nil
    ) async throws -> (ChatModel, InProcessContractTransport) {
        ModelKeys.customURL = "http://127.0.0.1:\(server.port)/v1"
        ModelKeys.customModel = "fake-model"
        ModelKeys.selectedProvider = .custom
        let transport = InProcessContractTransport(
            session: session,
            beforeSource: beforeSource,
            beforeActivate: beforeActivate
        )
        model?.stopSession()
        model = AppModel(
            launcher: launcher,
            pairer: FakePairing(),
            automation: session,
            transport: transport,
            systemVersion: OperatingSystemVersion(majorVersion: major, minorVersion: 2, patchVersion: 0)
        )
        model.loopback.simulate(.working(ms: 9))
        model.setup.loopback = .proxy
        XCTAssertTrue(model.setRelay("https://relay.invalid"))
        model.startSession()
        XCTAssertTrue(model.sessionOn)
        await finishSimulatorPrepare()

        let store = SessionStore(folder: tempFolder, defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let chat = ChatModel(app: model, store: store)
        AskPoki.install(app: model, chat: chat)
        return (chat, transport)
    }

    private func finishSimulatorPrepare() async {
        model.prepareForTask()
        await waitFor("simulator prerequisite check finished") { ["failed", "running"].contains(self.model.runner.state) }
        model.runnerChanged(RunnerStatus(state: "running", code: "local_ddi"))
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        done.expectationDescription = what
        await fulfillment(of: [done], timeout: timeout)
    }

    private func launchSettingsTool() -> String {
        FakeCompletions.tool("do", ["actions": [["launch": "com.apple.Preferences"]]])
    }

    // MARK: - Baseline Control

    func testNormalCompletionClosesAutomationAndAllowsNextTask() async throws {
        let server = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.text("Done opening Settings."),
            launchSettingsTool(),
            FakeCompletions.text("Second task done."),
        ])
        let (chat, transport) = try await makeHarness(server: server)

        chat.send("Open Settings.")
        await waitFor("first task finished") { !chat.running }
        XCTAssertGreaterThanOrEqual(transport.screenReads, 1)
        await waitFor("automation closed after normal completion") { !self.session.isOpen && self.model.runnerPaused }
        XCTAssertFalse(model.hasOpenInProcessSession)

        // Immediately start next task.
        await finishSimulatorPrepare()
        chat.send("Open Settings again.")
        await waitFor("second task finished") { !chat.running }
        XCTAssertGreaterThanOrEqual(transport.screenReads, 2)
        await waitFor("automation closed after second task") { !self.session.isOpen && self.model.runnerPaused }
    }

    // MARK: - Path 1: Task Failure

    func testTaskFailureAfterSwitchingBackToPokiClosesAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                #"{"error":{"message":"simulated upstream failure"}}"#,
            ],
            responseStatuses: ["200 OK", "500 Internal Server Error"],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, _) = try await makeHarness(server: server)

        chat.send("Open Settings and check something.")
        await waitFor("task opened Settings and entered second model turn") {
            self.session.isOpen && server.requests.count == 2
        }
        model.wentToBackground()

        // User switches back to Poki to see what is happening; Poki closes automation on foreground.
        model.becameActive()
        await waitFor("becameActive closed session") { !self.session.isOpen && self.model.runnerPaused }

        // Now the model request fails.
        server.release()
        await waitFor("failed task finished") { !chat.running }
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertFalse(session.isOpen, "task failure after returning to Poki must not leave automation reopened")
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    func testTaskFailureMidTaskInBackgroundClosesAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                #"{"error":{"message":"simulated upstream failure"}}"#,
            ],
            responseStatuses: ["200 OK", "500 Internal Server Error"]
        )
        let (chat, transport) = try await makeHarness(server: server)

        chat.send("Open Settings and fail.")
        await waitFor("failed task finished") { !chat.running }
        XCTAssertGreaterThanOrEqual(transport.screenReads, 1)
        await waitFor("automation closed after background task failure") { !self.session.isOpen && self.model.runnerPaused }
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    // MARK: - Path 2: Stop from Dynamic Island (Live Activity)

    func testLiveActivityStopWhileWaitingForModelClosesAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.text("Should not finish."),
            ],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, _) = try await makeHarness(server: server)

        chat.send("Open Settings and keep working.")
        await waitFor("task opened Settings and waiting on model") {
            self.session.isOpen && server.requests.count == 2
        }
        model.wentToBackground()

        // User taps Stop on Dynamic Island.
        model.stopFromOutside(AppModel.liveActivityStop)
        await waitFor("task stopped") { !chat.running }
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertFalse(session.isOpen, "Dynamic Island stop must close automation and never reopen it during teardown")
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    func testLiveActivityStopDuringInFlightStepClosesAutomation() async throws {
        let gate = StepHoldGate()
        let server = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.tool("look", [:]),
            FakeCompletions.text("Should not finish."),
        ])
        let (chat, _) = try await makeHarness(server: server, beforeSource: { readIndex in
            if readIndex == 2 { await gate.wait() }
        })

        chat.send("Open Settings and read again.")
        await waitFor("second phone step is in flight") { gate.isBlocked }
        model.wentToBackground()

        // User taps Stop on Dynamic Island while the phone step is in flight.
        model.stopFromOutside(AppModel.liveActivityStop)

        // Let the in-flight native step finish.
        gate.release()
        await waitFor("task stopped") { !chat.running }
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertFalse(session.isOpen, "Dynamic Island stop during an in-flight step must not leave automation open")
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    // MARK: - Path 3: Stop inside Poki App

    func testInAppStopAfterSwitchingBackToPokiWhileWaitingForModelClosesAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.text("Should not finish."),
            ],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, _) = try await makeHarness(server: server)

        chat.send("Open Settings and wait.")
        await waitFor("task opened Settings and waiting on model") {
            self.session.isOpen && server.requests.count == 2
        }
        model.wentToBackground()

        // User switches back to Poki App, then taps Stop button in ChatView.
        model.becameActive()
        await waitFor("becameActive closed session") { !self.session.isOpen && self.model.runnerPaused }
        chat.stop()
        await waitFor("task stopped") { !chat.running }
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertFalse(session.isOpen, "In-app stop after switching back to Poki must not reopen automation")
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    func testInAppStopDuringInFlightStepClosesAutomation() async throws {
        let gate = StepHoldGate()
        let server = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.tool("look", [:]),
            FakeCompletions.text("Should not finish."),
        ])
        let (chat, _) = try await makeHarness(server: server, beforeSource: { readIndex in
            if readIndex == 2 { await gate.wait() }
        })

        chat.send("Open Settings and read again.")
        await waitFor("second phone step is in flight") { gate.isBlocked }
        model.wentToBackground()

        // User switches back to Poki App while the step is in flight, then taps Stop in ChatView.
        model.becameActive()
        chat.stop()

        gate.release()
        await waitFor("task stopped") { !chat.running }
        try await Task.sleep(for: .milliseconds(600))

        XCTAssertFalse(session.isOpen, "In-app stop during an in-flight step must close automation and not reopen it")
        XCTAssertTrue(model.runnerPaused)
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    func testInAppStopWhileWaitingForModelWithoutBecameActiveClosesAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.text("Should not finish."),
            ],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, _) = try await makeHarness(server: server)

        chat.send("Open Settings and wait.")
        await waitFor("task opened Settings and waiting on model") {
            self.session.isOpen && server.requests.count == 2
        }

        // User taps Stop inside Poki App (e.g. without leaving Poki or on Duo).
        chat.stop()
        await waitFor("task stopped") { !chat.running }
        await waitFor("automation closed after in-app stop") { !self.session.isOpen && self.model.runnerPaused }
        XCTAssertFalse(model.hasOpenInProcessSession)
    }

    func testInAppStopOnIOS26PerformsFullCloseAndAllowsNextTask() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.text("Should not finish."),
                launchSettingsTool(),
                FakeCompletions.text("Next task done."),
            ],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, transport) = try await makeHarness(system: 26, server: server)

        chat.send("Open Settings and wait.")
        await waitFor("task opened Settings and waiting on model") {
            self.session.isOpen && server.requests.count == 2
        }

        chat.stop()
        await waitFor("task stopped") { !chat.running }
        await waitFor("iOS 26 owner stop fully closes automation") { !self.session.isOpen && self.model.runnerPaused }
        XCTAssertGreaterThanOrEqual(session.closes, 1)
        XCTAssertEqual(session.pauses, 0)

        // Start a follow-up task immediately after stopping.
        let nextServer = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.text("Next task done."),
        ])
        ModelKeys.customURL = "http://127.0.0.1:\(nextServer.port)/v1"
        await finishSimulatorPrepare()
        chat.send("Open Settings again.")
        await waitFor("next task finished") { !chat.running }
        XCTAssertGreaterThanOrEqual(transport.screenReads, 2)
        await waitFor("next task on iOS 26 stood by") { self.model.runnerPaused && self.session.pauses >= 1 }
    }

    func testImmediateNextTaskAfterLiveActivityStopReopensAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                FakeCompletions.text("Should not finish."),
            ],
            holdAfter: 1
        )
        defer { server.release() }
        let (chat, transport) = try await makeHarness(server: server)

        chat.send("Open Settings and wait.")
        await waitFor("task opened Settings and waiting on model") {
            self.session.isOpen && server.requests.count == 2
        }
        model.wentToBackground()

        model.stopFromOutside(AppModel.liveActivityStop)
        await waitFor("task stopped and automation closed") { !chat.running && !self.session.isOpen && self.model.runnerPaused }

        // Next task starts cleanly and reopens automation.
        let nextServer = try FakeCompletions(replies: [
            launchSettingsTool(),
            FakeCompletions.text("Second task done."),
        ])
        ModelKeys.customURL = "http://127.0.0.1:\(nextServer.port)/v1"
        await finishSimulatorPrepare()
        chat.send("Open Settings again.")
        await waitFor("second task finished") { !chat.running }
        XCTAssertGreaterThanOrEqual(transport.screenReads, 2)
        await waitFor("second task closed automation") { !self.session.isOpen && self.model.runnerPaused }
    }

    func testImmediateNextTaskAfterFailureReopensAutomation() async throws {
        let server = try FakeCompletions(
            replies: [
                launchSettingsTool(),
                #"{"error":{"message":"simulated upstream failure"}}"#,
                launchSettingsTool(),
                FakeCompletions.text("Recovered on retry."),
            ],
            responseStatuses: ["200 OK", "500 Internal Server Error", "200 OK", "200 OK"]
        )
        let (chat, transport) = try await makeHarness(server: server)

        chat.send("Open Settings and fail.")
        await waitFor("failed task finished") { !chat.running }
        await waitFor("automation closed after failure") { !self.session.isOpen && self.model.runnerPaused }
        let readsAfterFailure = transport.screenReads
        XCTAssertGreaterThanOrEqual(readsAfterFailure, 1)

        await finishSimulatorPrepare()
        chat.send("Try again.")
        await waitFor("retry task finished") { !chat.running }
        XCTAssertGreaterThan(transport.screenReads, readsAfterFailure)
        await waitFor("automation closed after retry") { !self.session.isOpen && self.model.runnerPaused }
    }
}

private final class StepHoldGate: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var blocked = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var isBlocked: Bool { lock.withLock { blocked } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if released { return true }
                blocked = true
                continuations.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func release() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            released = true
            blocked = false
            defer { continuations.removeAll() }
            return continuations
        }
        pending.forEach { $0.resume() }
    }
}
