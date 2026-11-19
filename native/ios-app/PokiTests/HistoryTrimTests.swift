import PiSwiftAgent
import PiSwiftAI
import XCTest
@testable import Poki

final class HistoryTrimTests: XCTestCase {
    private func read(_ n: Int, picture: Bool = true) -> AgentMessage {
        let text = "app: Notes   read: now (80 ms)\ndid: tap \(n) (sent)\nscreen_changed: true (the elements changed)\nelements (2):\n 1 Button \"Done\" [0,0,10,10]\n 2 Text \"Milk\" [0,20,10,10]"
        var content: [ContentBlock] = [.text(TextContent(text: text))]
        if picture { content.append(.image(ImageContent(data: "AAAA", mimeType: "image/jpeg"))) }
        return .toolResult(ToolResultMessage(toolCallId: "call-\(n)", toolName: "do", content: content, isError: false))
    }

    private func text(_ message: AgentMessage) -> String {
        guard case .toolResult(let result) = message else { return "" }
        return result.content.compactMap { if case .text(let content) = $0 { content.text } else { nil } }.joined()
    }

    private func hasPicture(_ message: AgentMessage) -> Bool {
        guard case .toolResult(let result) = message else { return false }
        return result.content.contains { if case .image = $0 { true } else { false } }
    }

    func testAFewReadsStayWhole() {
        let messages = (1...6).map { read($0) }
        let sent = HistoryTrim.trimmed(messages, taskStart: 0)
        XCTAssertTrue(sent.allSatisfy(hasPicture))
        XCTAssertTrue(sent.allSatisfy { text($0).contains("Milk") })
    }

    func testOldReadsKeepWhatWasDoneAndLoseTheScreen() {
        let messages = (1...7).map { read($0) }
        let sent = HistoryTrim.trimmed(messages, taskStart: 0)
        XCTAssertEqual(sent.count, 7)
        for old in sent.prefix(4) {
            XCTAssertFalse(hasPicture(old))
            XCTAssertFalse(text(old).contains("Milk"))
            XCTAssertTrue(text(old).contains("did: tap"))
            XCTAssertTrue(text(old).contains("screen_changed: true"))
            XCTAssertTrue(text(old).contains("Call look"))
        }
        for recent in sent.suffix(3) {
            XCTAssertTrue(hasPicture(recent))
            XCTAssertTrue(text(recent).contains("Milk"))
        }
    }

    func testTheCutMovesInStepsSoTheSentHistoryHoldsStillBetween() {
        XCTAssertEqual((0...11).map(HistoryTrim.cutCount), [0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 8])
    }

    func testReadsOfFinishedTasksAreAllCutAndTheirWordsStay() {
        var messages: [AgentMessage] = [read(1), read(2)]
        messages.append(.toolResult(ToolResultMessage(toolCallId: "finish", toolName: "finish_task", content: [.text(TextContent(text: "Result recorded."))], isError: false)))
        let start = messages.count
        messages.append(read(3))
        let sent = HistoryTrim.trimmed(messages, taskStart: start)
        XCTAssertFalse(hasPicture(sent[0]))
        XCTAssertFalse(hasPicture(sent[1]))
        XCTAssertTrue(text(sent[0]).contains("did: tap 1"))
        XCTAssertEqual(text(sent[2]), "Result recorded.")
        XCTAssertTrue(hasPicture(sent[3]))
    }

    func testALongOldAnswerWithoutElementsKeepsItsStart() {
        let page = String(repeating: "word ", count: 1000)
        let short = HistoryTrim.shortened(page)
        XCTAssertTrue(short.hasPrefix("word word"))
        XCTAssertLessThan(short.count, 1700)
        XCTAssertEqual(HistoryTrim.shortened("Plan published."), "Plan published.")
    }
}
