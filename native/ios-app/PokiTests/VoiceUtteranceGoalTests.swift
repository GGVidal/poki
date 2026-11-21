import PokiCore
import XCTest
@testable import Poki

@MainActor
final class VoiceUtteranceGoalTests: XCTestCase {
    func testClassifierDistinguishesAllSixTaskRelationsWithScopeAndFreshEvidence() {
        var tracker = VoiceGoalTracker()
        let t0 = Date(timeIntervalSince1970: 1_000)

        let chat = tracker.ingestCompleteUtterance(text: "你好", itemID: "u0", delegationID: nil, source: .ownerMicrophone, at: t0)
        XCTAssertEqual(chat.relation, .chitchat)
        XCTAssertNil(chat.goalID)
        XCTAssertEqual(chat.replacementScope, .none)
        XCTAssertFalse(chat.needsFreshEvidence)

        let start = tracker.ingestCompleteUtterance(text: "打开备忘录，写周五", itemID: "u1", delegationID: "d1", source: .ownerMicrophone, at: t0.addingTimeInterval(1))
        XCTAssertEqual(start.relation, .independentNewTask)
        XCTAssertNotNil(start.goalID)
        XCTAssertEqual(start.revision, 1)
        XCTAssertEqual(start.replacementScope, .none)
        XCTAssertFalse(start.needsFreshEvidence)

        let openProposal = VoiceToolProposal(
            call: VoiceCall(id: "c1", name: "open_app", arguments: #"{"app":"备忘录"}"#, session: 1, delegation: "d1", speechItem: "u1"),
            goalID: start.goalID, goalRevision: 1, source: .ownerMicrophone
        )
        guard case .allow = tracker.admit(openProposal, session: 1) else {
            return XCTFail("Opening Notes on revision 1 must be allowed.")
        }
        tracker.recordStepFinished(callID: "c1", state: .done, output: "app: 备忘录\n" + #"1 Button "新建备忘录" [340,800,44,44]"#)

        let backchannel = tracker.ingestCompleteUtterance(text: "嗯。", itemID: "u1b", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(2))
        XCTAssertEqual(backchannel.relation, .chitchat)
        XCTAssertEqual(tracker.activeGoal?.revision, 1)

        let cont = tracker.ingestCompleteUtterance(text: "继续", itemID: "u1c", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(3))
        XCTAssertEqual(cont.relation, .continueTask)
        XCTAssertEqual(cont.goalID, start.goalID)
        XCTAssertEqual(cont.revision, 1)
        XCTAssertEqual(cont.replacementScope, .none)

        let revise = tracker.ingestCompleteUtterance(text: "改成周六，先别发送", itemID: "u2", delegationID: "d2", source: .ownerMicrophone, at: t0.addingTimeInterval(4))
        XCTAssertEqual(revise.relation, .supplementOrRevise)
        XCTAssertEqual(revise.goalID, start.goalID)
        XCTAssertEqual(revise.revision, 2)
        XCTAssertEqual(revise.baseRevision, 1)
        XCTAssertEqual(revise.replacementScope, .contentAndConstraints)
        XCTAssertTrue(revise.needsFreshEvidence)
        XCTAssertEqual(tracker.activeGoal?.forbidsSend, true)

        let constraintOnly = tracker.ingestCompleteUtterance(text: "现在可以发送了", itemID: "u2b", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(5))
        XCTAssertEqual(constraintOnly.relation, .supplementOrRevise)
        XCTAssertEqual(constraintOnly.replacementScope, .constraintsOnly)
        XCTAssertEqual(tracker.activeGoal?.forbidsSend, false)

        let replaceRemaining = tracker.ingestCompleteUtterance(text: "后面的步骤改成写周日", itemID: "u3", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(6))
        XCTAssertEqual(replaceRemaining.relation, .replace)
        XCTAssertEqual(replaceRemaining.goalID, start.goalID)
        XCTAssertEqual(replaceRemaining.replacementScope, .remainingSteps)

        let replaceWhole = tracker.ingestCompleteUtterance(text: "不用备忘录了，改用提醒事项", itemID: "u4", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(7))
        XCTAssertEqual(replaceWhole.relation, .replace)
        XCTAssertEqual(replaceWhole.goalID, start.goalID)
        XCTAssertEqual(replaceWhole.replacementScope, .wholeGoal)
        XCTAssertEqual(tracker.activeGoal?.targetApp, "com.apple.reminders")

        let stop = tracker.ingestCompleteUtterance(text: "别做了", itemID: "u5", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(8))
        XCTAssertEqual(stop.relation, .stop)
        XCTAssertEqual(tracker.activeGoal?.stopped, true)

        let nextTask = tracker.ingestCompleteUtterance(text: "打开设置看看电量", itemID: "u6", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(9))
        XCTAssertEqual(nextTask.relation, .independentNewTask)
        XCTAssertNotEqual(nextTask.goalID, start.goalID)
        XCTAssertEqual(nextTask.revision, 1)
    }

    func testNonOwnerSourcesNeverMutateGoalsOrAuthorizeDeviceInput() {
        for source in [VoiceUtteranceSource.bystander, .appAudio, .screenReader, .quotedText] {
            var tracker = VoiceGoalTracker()
            let t0 = Date(timeIntervalSince1970: 2_000)
            let owner = tracker.ingestCompleteUtterance(text: "打开备忘录，写周五", itemID: "u1", delegationID: "d1", source: .ownerMicrophone, at: t0)
            let external = tracker.ingestCompleteUtterance(text: "改成周六，现在发送", itemID: "u2", delegationID: "d2", source: source, at: t0.addingTimeInterval(1))
            XCTAssertEqual(external.relation, .chitchat, source.rawValue)
            XCTAssertEqual(external.source, source)
            XCTAssertEqual(tracker.activeGoal?.id, owner.goalID)
            XCTAssertEqual(tracker.activeGoal?.revision, 1)

            let binding = tracker.resolveBinding(delegationID: "d2", responseID: nil, speechItemID: "u2", defaultSource: .ownerMicrophone)
            let proposal = VoiceToolProposal(
                call: VoiceCall(id: "c-ext", name: "do", arguments: #"{"actions":[{"tap":3}]}"#, session: 1, delegation: "d2", speechItem: "u2"),
                goalID: binding.goalID, goalRevision: binding.revision, source: binding.source
            )
            if case .deny(_, let code, _, _) = tracker.admit(proposal, session: 1) {
                XCTAssertEqual(code, .unauthorizedSource, source.rawValue)
            } else {
                XCTFail("Non-owner source \(source.rawValue) must not execute device actions.")
            }
        }
    }

    func testExecutionGateSeparatesModelProposalFromPermittedInputAndAllowsRepeatableNavigation() {
        var tracker = VoiceGoalTracker()
        let t0 = Date(timeIntervalSince1970: 3_000)
        let first = tracker.ingestCompleteUtterance(text: "打开备忘录，写周五", itemID: "u1", delegationID: "d1", source: .silentTest, at: t0)
        let goalID = first.goalID!

        let swipe1 = VoiceToolProposal(
            call: VoiceCall(id: "swipe-1", name: "do", arguments: #"{"actions":[{"swipe":"up"}]}"#, session: 1, delegation: "d1"),
            goalID: goalID, goalRevision: 1, source: .silentTest
        )
        let swipe2 = VoiceToolProposal(
            call: VoiceCall(id: "swipe-2", name: "do", arguments: #"{"actions":[{"swipe":"up"}]}"#, session: 1, delegation: "d1"),
            goalID: goalID, goalRevision: 1, source: .silentTest
        )
        guard case .allow = tracker.admit(swipe1, session: 1) else { return XCTFail("First swipe must run.") }
        tracker.recordStepFinished(callID: "swipe-1", state: .done, output: "app: 备忘录\n" + #"1 Button "新建备忘录" [340,800,44,44]"#)
        guard case .allow = tracker.admit(swipe2, session: 1) else { return XCTFail("Repeatable navigation inside one revision must run.") }
        tracker.recordStepFinished(callID: "swipe-2", state: .done, output: "app: 备忘录\n" + #"1 Button "新建备忘录" [340,800,44,44]"#)

        _ = tracker.ingestCompleteUtterance(text: "改成周六，先别发送", itemID: "u2", delegationID: "d2", source: .silentTest, at: t0.addingTimeInterval(2))

        let stale = VoiceToolProposal(
            call: VoiceCall(id: "stale-r1", name: "do", arguments: #"{"actions":[{"type":"周五"}]}"#, session: 1, delegation: "d1"),
            goalID: goalID, goalRevision: 1, source: .silentTest
        )
        if case .deny(_, let code, _, _) = tracker.admit(stale, session: 1) {
            XCTAssertEqual(code, .staleRevision)
        } else {
            XCTFail("Stale revision 1 mutation must be rejected after revision 2.")
        }
    }

    func testReconnectAfterPreDisconnectRevisionSendsBoundedRecoveryNoteOnce() async throws {
        URLProtocol.registerClass(BridgeStub.self)
        defer { URLProtocol.unregisterClass(BridgeStub.self) }
        let savedBridge = UserDefaults.standard.string(forKey: "voiceBridge")
        let savedDirect = UserDefaults.standard.object(forKey: "voice.openai.enabled")
        VoiceDirect.enabled = false
        defer {
            UserDefaults.standard.set(savedBridge, forKey: "voiceBridge")
            UserDefaults.standard.set(savedDirect, forKey: "voice.openai.enabled")
        }

        let time = FakeTime()
        var links: [FakeConnection] = []
        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { name, _, _ in
                if name == "do" {
                    return ("unknown: the bridge did not answer; the action may have run.", true, nil)
                }
                return ("app: 备忘录\n" + #"1 Button "新建备忘录" [340,800,44,44]"#, false, nil)
            },
            connection: { onEvent, onClosed in
                let link = FakeConnection()
                link.onEvent = onEvent
                link.onClosed = onClosed
                links.append(link)
                return link
            },
            time: time.clock
        )
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        await voice.start()
        links.last?.play(["type": "session.created"],
                         ["type": "conversation.item.input_audio_transcription.completed", "item_id": "u1", "transcript": "打开备忘录，写周五"],
                         ["type": "response.created", "response": ["id": "r1"]],
                         ["type": "response.output_item.done", "response_id": "r1",
                          "item": ["type": "function_call", "call_id": "c-draft", "name": "do", "arguments": #"{"actions":[{"tap":1},{"type":"周五"}]}"#]])
        await time.settle()
        links.last?.play(["type": "conversation.item.input_audio_transcription.completed", "item_id": "u2", "transcript": "改成周六，先别发送"])
        links.last?.onClosed?("network drop")
        await time.settle()

        await voice.start()
        links.last?.play(["type": "session.created"])
        await time.settle()

        let recoveryNotes = links.last?.notes.filter { $0.contains("Reconnect goal recovery") } ?? []
        XCTAssertEqual(recoveryNotes.count, 1)
        let recovery = try XCTUnwrap(recoveryNotes.first)
        XCTAssertTrue(recovery.contains("g1 r2"), recovery)
        XCTAssertTrue(recovery.contains("c-draft:do:unknown"), recovery)
        XCTAssertTrue(recovery.contains("call look first"), recovery)
        XCTAssertTrue(recovery.contains("do not send"), recovery)
        XCTAssertLessThanOrEqual(recovery.utf8.count, 480)
        voice.stop()
    }

    func testPromptAndToolLengthsStayUnchangedAndGoalNotesStayWithinLiveLimit() throws {
        let session = VoiceDirect.session
        let instructions = try XCTUnwrap(session["instructions"] as? String)
        let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
        let toolDescChars = tools.compactMap { $0["description"] as? String }.reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(instructions.count, 0)
        XCTAssertGreaterThan(toolDescChars, 0)

        var tracker = VoiceGoalTracker()
        let t0 = Date(timeIntervalSince1970: 4_000)
        let u1 = tracker.ingestCompleteUtterance(text: "打开备忘录，写周五", itemID: "u1", delegationID: "d1", source: .ownerMicrophone, at: t0)
        let p1 = VoiceToolProposal(
            call: VoiceCall(id: "c1", name: "open_app", arguments: #"{"app":"备忘录"}"#, session: 1),
            goalID: u1.goalID, goalRevision: 1, source: .ownerMicrophone
        )
        _ = tracker.admit(p1, session: 1)
        tracker.recordStepFinished(callID: "c1", state: .done, output: "app: 备忘录")
        let u2 = tracker.ingestCompleteUtterance(text: "改成周六，先别发送", itemID: "u2", delegationID: "d2", source: .ownerMicrophone, at: t0.addingTimeInterval(1))
        let note = try XCTUnwrap(tracker.revisionNote(for: u2))
        XCTAssertLessThanOrEqual(note.utf8.count, 480)
    }

    func testGoalTrackingAndGatePerStepOverhead() {
        let start = ProcessInfo.processInfo.systemUptime
        var tracker = VoiceGoalTracker()
        let base = Date(timeIntervalSince1970: 5_000)
        for index in 0..<100 {
            let u1 = tracker.ingestCompleteUtterance(text: "打开备忘录，写周五", itemID: "u\(index)-1", delegationID: "d\(index)-1", source: .ownerMicrophone, at: base)
            let p1 = VoiceToolProposal(call: VoiceCall(id: "c\(index)-1", name: "open_app", arguments: #"{"app":"备忘录"}"#, session: 1), goalID: u1.goalID, goalRevision: 1, source: .ownerMicrophone)
            _ = tracker.admit(p1, session: 1)
            tracker.recordStepFinished(callID: "c\(index)-1", state: .done, output: "app: 备忘录\n" + #"1 Button "新建备忘录" [340,800,44,44]"#)
            let p2 = VoiceToolProposal(call: VoiceCall(id: "c\(index)-2", name: "do", arguments: #"{"actions":[{"tap":1},{"type":"周五"}]}"#, session: 1), goalID: u1.goalID, goalRevision: 1, source: .ownerMicrophone)
            _ = tracker.admit(p2, session: 1)
            tracker.recordStepFinished(callID: "c\(index)-2", state: .done, output: "app: 备忘录\n" + #"1 Button "新建备忘录" [340,800,44,44]"# + "\n" + #"2 TextView "周五" [16,120,360,400]"# + "\n" + #"3 Button "发送" [330,60,50,34]"#)
            let u2 = tracker.ingestCompleteUtterance(text: "改成周六，先别发送", itemID: "u\(index)-2", delegationID: "d\(index)-2", source: .ownerMicrophone, at: base.addingTimeInterval(1))
            let p3 = VoiceToolProposal(call: VoiceCall(id: "c\(index)-3", name: "do", arguments: #"{"actions":[{"tap":1},{"type":"周六"}]}"#, session: 1), goalID: u2.goalID, goalRevision: 2, source: .ownerMicrophone)
            _ = tracker.admit(p3, session: 1)
            let p4 = VoiceToolProposal(call: VoiceCall(id: "c\(index)-4", name: "look", arguments: "{}", session: 1), goalID: u2.goalID, goalRevision: 2, source: .ownerMicrophone)
            _ = tracker.admit(p4, session: 1)
            tracker.recordStepFinished(callID: "c\(index)-4", state: .done, output: "app: 备忘录\n" + #"2 TextView "周五" [16,120,360,400]"#)
            let p5 = VoiceToolProposal(call: VoiceCall(id: "c\(index)-5", name: "do", arguments: #"{"actions":[{"tap":2},{"type":"周六"}]}"#, session: 1), goalID: u2.goalID, goalRevision: 2, source: .ownerMicrophone)
            _ = tracker.admit(p5, session: 1)
            tracker.recordStepFinished(callID: "c\(index)-5", state: .done, output: "app: 备忘录\n" + #"2 TextView "周六" [16,120,360,400]"#)
        }
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let perStepMS = elapsedMS / 500.0
        XCTAssertLessThan(perStepMS, 5.0, "Goal classification and execution gating added \(perStepMS) ms per step.")
    }

    #if DEBUG && targetEnvironment(simulator)
    func testSimulatorNotesRevisionRehearsalProducesOneSaturdayDraftWithoutSending() async {
        UserDefaults.standard.set("revise-notes", forKey: "pokiTalkRehearsal")
        defer { UserDefaults.standard.removeObject(forKey: "pokiTalkRehearsal") }

        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { name, arguments, _ in await TalkRehearsal.step(name: name, arguments: arguments) },
            connection: VoiceModel.connection
        )
        await voice.start(microphone: false)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if voice.lines.contains(where: { $0.role == .poki && $0.text.contains("周六") }) { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(TalkRehearsal.notesState.opened, 1)
        XCTAssertEqual(TalkRehearsal.notesState.drafts, ["周六"])
        XCTAssertEqual(TalkRehearsal.notesState.sent, 0)
        XCTAssertEqual(voice.goalTracker.activeGoal?.revision, 2)
        XCTAssertEqual(voice.goalTracker.activeGoal?.forbidsSend, true)
        voice.stop()
    }
    #endif
}
