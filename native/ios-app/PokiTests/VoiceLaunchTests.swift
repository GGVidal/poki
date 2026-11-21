import XCTest
@testable import Poki

@MainActor
final class VoiceLaunchTests: XCTestCase {
    func testTalkToPokiRecordsTheStartedRequest() async throws {
        #if targetEnvironment(simulator)
        let voice = try XCTUnwrap(AskPoki.app?.voice)
        let defaults = UserDefaults.standard
        let rehearsal = defaults.object(forKey: "pokiTalkRehearsal")
        let hold = defaults.object(forKey: "pokiTalkHold")
        let muted = voice.muted
        defaults.set("1", forKey: "pokiTalkRehearsal")
        defaults.set("listening", forKey: "pokiTalkHold")
        defer {
            voice.stop()
            voice.muted = muted
            defaults.set(rehearsal, forKey: "pokiTalkRehearsal")
            defaults.set(hold, forKey: "pokiTalkHold")
        }
        let start = AppLog.shared.lines.count
        let listening = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in voice.phase == .listening }, object: nil)

        _ = try await TalkToPokiIntent().perform()
        await fulfillment(of: [listening], timeout: 8)

        let log = AppLog.shared.lines.dropFirst(start)
        let started = try XCTUnwrap(log.first { line in
            line.contains("result=started") && line.range(of: #"request=[0-9A-Fa-f-]{36}"#, options: .regularExpression) != nil
        }, "The activity log must record the request that started the talk")
        let session = String(try XCTUnwrap(started.split(separator: " ").last))
        XCTAssertTrue(session.hasPrefix("session="))
        voice.muted = true
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            AppLog.shared.lines.dropFirst(start).filter { $0.contains("result=returned") }.count == 2
        }, object: nil)

        _ = try await TalkToPokiIntent().perform()
        _ = try await TalkToPokiIntent(fromControl: true).perform()
        await fulfillment(of: [returned], timeout: 3)

        let returns = AppLog.shared.lines.dropFirst(start).filter { $0.contains("result=returned") }
        XCTAssertTrue(returns.allSatisfy { $0.hasSuffix(session) })
        XCTAssertTrue(returns.contains { $0.contains("source=appShortcut") })
        XCTAssertTrue(returns.contains { $0.contains("source=control") })
        XCTAssertEqual(AppLog.shared.lines.dropFirst(start).filter { $0.contains("result=started") }.count, 1)
        XCTAssertTrue(voice.muted)
        XCTAssertTrue(voice.isOn)
        #endif
    }

    func testEndingATalkInvalidatesAQueuedRequestAndItsReplay() async throws {
        #if targetEnvironment(simulator)
        let voice = try XCTUnwrap(AskPoki.app?.voice)
        let defaults = UserDefaults.standard
        let rehearsal = defaults.object(forKey: "pokiTalkRehearsal")
        defaults.set("1", forKey: "pokiTalkRehearsal")
        defer {
            voice.stop()
            defaults.set(rehearsal, forKey: "pokiTalkRehearsal")
        }
        await voice.start(microphone: false)
        XCTAssertTrue(voice.isOn)
        let entry = PokiEntry.shared
        let pending = PokiEntry.Request(id: UUID(), destination: .talk, issuedAt: .now, source: .appShortcut, epoch: entry.epoch)
        let invalidated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            AppLog.shared.lines.contains { $0.contains("request=\(pending.id)") && $0.contains("result=invalidated reason=voiceEpochChanged") }
        }, object: nil)

        entry.ask(pending)
        voice.stop()
        await fulfillment(of: [invalidated], timeout: 3)

        let expired = PokiEntry.Request(id: UUID(), destination: .talk, issuedAt: Date.now.addingTimeInterval(-16),
                                        source: .appShortcut, epoch: entry.epoch)
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            AppLog.shared.lines.contains { $0.contains("request=\(expired.id)") && $0.contains("result=shown reason=expired") }
        }, object: nil)
        entry.ask(pending)
        entry.ask(expired)
        await fulfillment(of: [shown], timeout: 3)

        XCTAssertEqual(AppLog.shared.lines.filter { $0.contains("request=\(pending.id)") }.count, 1)
        XCTAssertFalse(voice.isOn)
        #endif
    }
}
