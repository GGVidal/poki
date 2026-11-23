import Foundation
import XCTest
@testable import PokiCore

/// The link from this Poki to the owner's other Poki (an iPad workspace, issue #689) over that Poki's
/// own connector URL.
final class WorkspaceLinkTests: XCTestCase {
    static let label = String(repeating: "a", count: 52)
    static let secret = String(repeating: "S", count: 43)
    static let url = "https://relay.example.dev/v1/\(label)/\(secret)/mcp"

    /// Answers like a PokiCore behind the relay: a session from initialize, then tools/call.
    final class FakePoki: WorkspaceHTTP, @unchecked Sendable {
        let lock = NSLock()
        var requests: [(headers: [String: String], body: JSON)] = []
        var sessions: Set<String> = []
        var next = 0
        /// Status codes to answer tools/call with before answering normally.
        var failCalls: [Int] = []
        var jpeg = Data([0xff, 0xd8, 0xff, 0xd9])

        func forgetSessions() { lock.withLock { sessions.removeAll() } }

        func post(_ url: URL, headers: [String: String], body: Data, timeout: Double) async throws -> (status: Int, headers: [String: String], body: Data) {
            let json = try JSON.parse(body)
            return lock.withLock {
                requests.append((headers, json))
                let id = json["id"] ?? .null
                switch json["method"]?.string {
                case "initialize":
                    next += 1
                    let session = "s\(next)"
                    sessions.insert(session)
                    let reply: JSON = ["jsonrpc": "2.0", "id": id, "result": ["protocolVersion": "2025-06-18", "serverInfo": ["name": "poki"]]]
                    return (200, ["mcp-session-id": session, "content-type": "application/json"], reply.data())
                case "notifications/initialized":
                    return (202, [:], Data())
                case "tools/call":
                    if !failCalls.isEmpty { return (failCalls.removeFirst(), [:], Data()) }
                    guard let session = headers["mcp-session-id"], sessions.contains(session) else {
                        let reply: JSON = ["jsonrpc": "2.0", "id": id, "error": ["code": -32001, "message": "Session not found"]]
                        return (404, [:], reply.data())
                    }
                    let name = json["params"]?["name"]?.string ?? ""
                    let reply: JSON = ["jsonrpc": "2.0", "id": id, "result": [
                        "content": [["type": "text", "text": .string("\(name) on the workspace display")],
                                    ["type": "image", "data": .string(jpeg.base64EncodedString()), "mimeType": "image/jpeg"]],
                        "isError": false]]
                    return (200, ["content-type": "application/json"], reply.data())
                default:
                    return (400, [:], Data())
                }
            }
        }
    }

    func testAddressAcceptsConnectorURLsOnly() {
        XCTAssertNotNil(WorkspaceLinkAddress(Self.url))
        XCTAssertNotNil(WorkspaceLinkAddress("  \(Self.url)\n"))
        XCTAssertNotNil(WorkspaceLinkAddress("http://localhost:8787/v1/\(Self.label)/\(Self.secret)/mcp"))
        XCTAssertNotNil(WorkspaceLinkAddress("http://192.168.1.20:8787/v1/\(Self.label)/\(Self.secret)/mcp"))
        // Plain http to a public host would send the secret in the clear.
        XCTAssertNil(WorkspaceLinkAddress("http://relay.example.dev/v1/\(Self.label)/\(Self.secret)/mcp"))
        XCTAssertNil(WorkspaceLinkAddress("https://relay.example.dev"))
        XCTAssertNil(WorkspaceLinkAddress("https://relay.example.dev/v1/\(Self.label)/mcp"))
        XCTAssertNil(WorkspaceLinkAddress("https://relay.example.dev/v1/short/\(Self.secret)/mcp"))
        XCTAssertNil(WorkspaceLinkAddress("\(Self.url)?x=1"))
        XCTAssertNil(WorkspaceLinkAddress("ftp://relay.example.dev/v1/\(Self.label)/\(Self.secret)/mcp"))
        XCTAssertEqual(WorkspaceLinkAddress(Self.url)?.host, "relay.example.dev")
    }

    func testCallsThroughOneSessionAndReturnsTheScreenshot() async throws {
        let poki = FakePoki()
        let link = WorkspaceLink(address: try XCTUnwrap(WorkspaceLinkAddress(Self.url)), http: poki)
        let look = await link.call("look", arguments: "{}")
        XCTAssertFalse(look.isError, look.text)
        XCTAssertEqual(look.text, "look on the workspace display")
        XCTAssertEqual(look.jpeg, poki.jpeg)
        let act = await link.call("do", arguments: #"{"actions":[{"tap":3}]}"#)
        XCTAssertFalse(act.isError, act.text)
        let methods = poki.requests.compactMap { $0.body["method"]?.string }
        XCTAssertEqual(methods, ["initialize", "notifications/initialized", "tools/call", "tools/call"])
        XCTAssertEqual(poki.requests.last?.headers["mcp-session-id"], "s1")
        XCTAssertEqual(poki.requests.last?.body["params"]?["arguments"]?["actions"]?[0]?["tap"]?.int, 3)
        XCTAssertEqual(poki.requests.first?.headers["accept"], "application/json, text/event-stream")
    }

    func testANewSessionWhenTheOtherPokiForgotIt() async throws {
        let poki = FakePoki()
        let link = WorkspaceLink(address: try XCTUnwrap(WorkspaceLinkAddress(Self.url)), http: poki)
        _ = await link.call("look", arguments: "{}")
        poki.forgetSessions()
        let again = await link.call("look", arguments: "{}")
        XCTAssertFalse(again.isError, again.text)
        XCTAssertEqual(poki.requests.filter { $0.body["method"]?.string == "initialize" }.count, 2)
        XCTAssertEqual(poki.requests.last?.headers["mcp-session-id"], "s2")
    }

    func testALostDoSaysTheActionsMayHaveRun() async throws {
        let poki = FakePoki()
        poki.failCalls = [502]
        let link = WorkspaceLink(address: try XCTUnwrap(WorkspaceLinkAddress(Self.url)), http: poki)
        let act = await link.call("do", arguments: #"{"actions":[{"tap":3}]}"#)
        XCTAssertTrue(act.isError)
        XCTAssertTrue(act.text.contains("may have run"), act.text)
        // Never sent again by the link itself.
        XCTAssertEqual(poki.requests.filter { $0.body["method"]?.string == "tools/call" }.count, 1)
    }

    func testOfflineAndUnknownAddressesReadAsErrors() async throws {
        let poki = FakePoki()
        poki.failCalls = [503]
        let link = WorkspaceLink(address: try XCTUnwrap(WorkspaceLinkAddress(Self.url)), http: poki)
        let offline = await link.call("look", arguments: "{}")
        XCTAssertTrue(offline.isError)
        XCTAssertTrue(offline.text.contains("offline"), offline.text)
    }
}
