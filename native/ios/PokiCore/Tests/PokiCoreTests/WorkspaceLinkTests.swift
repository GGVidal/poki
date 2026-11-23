import Foundation
import XCTest
@testable import PokiCore

/// The link from this Poki to the owner's other Poki (an iPad workspace, issue #689) over that Poki's
/// own connector URL.
final class WorkspaceLinkTests: XCTestCase {
    static let label = String(repeating: "a", count: 52)
    static let secret = String(repeating: "S", count: 43)
    static let url = "https://relay.example.dev/v1/\(label)/\(secret)/mcp"

    /// Answers like the relay (OAuth with PKCE) in front of a PokiCore: a session from initialize, then tools/call.
    final class FakePoki: WorkspaceHTTP, @unchecked Sendable {
        let lock = NSLock()
        var requests: [(method: String, path: String, headers: [String: String], body: JSON?)] = []
        var sessions: Set<String> = []
        var tokens: Set<String> = []
        var challenges: [String: String] = [:]
        var next = 0
        /// Whether the owner allows the client on the other device.
        var allow = true
        /// Status codes to answer tools/call with before answering normally.
        var failCalls: [Int] = []
        var jpeg = Data([0xff, 0xd8, 0xff, 0xd9])

        func forgetSessions() { lock.withLock { sessions.removeAll() } }
        func revokeTokens() { lock.withLock { tokens.removeAll() } }
        var mcpCalls: [JSON] { lock.withLock { requests.filter { $0.path.hasSuffix("/mcp") }.compactMap(\.body) } }
        func count(_ suffix: String) -> Int { lock.withLock { requests.filter { $0.path.hasSuffix(suffix) }.count } }

        func send(_ method: String, _ url: URL, headers: [String: String], body: Data?, timeout: Double) async throws -> (status: Int, headers: [String: String], body: Data) {
            lock.withLock {
                let json = body.flatMap { try? JSON.parse($0) }
                requests.append((method, url.path, headers, json))
                next += 1
                if url.path.hasSuffix("/register") {
                    let reply: JSON = ["client_id": .string("client\(next)")]
                    return (201, [:], reply.data())
                }
                if url.path.hasSuffix("/authorize") {
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    func item(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
                    var back = URLComponents(string: item("redirect_uri"))!
                    if allow && item("code_challenge_method") == "S256" {
                        challenges["code\(next)"] = item("code_challenge")
                        back.queryItems = [URLQueryItem(name: "code", value: "code\(next)"), URLQueryItem(name: "state", value: item("state"))]
                    } else {
                        back.queryItems = [URLQueryItem(name: "error", value: "access_denied"), URLQueryItem(name: "state", value: item("state"))]
                    }
                    return (302, ["location": back.url!.absoluteString], Data())
                }
                if url.path.hasSuffix("/token") {
                    let form = URLComponents(string: "?" + String(decoding: body ?? Data(), as: UTF8.self))?.queryItems ?? []
                    func item(_ name: String) -> String { form.first { $0.name == name }?.value ?? "" }
                    if item("grant_type") == "authorization_code" {
                        let expected = challenges[item("code")]
                        let got = WorkspaceLink.base64url(SHA256Digest.hash(Data(item("code_verifier").utf8)))
                        guard expected == got else { return (400, [:], (["error": "invalid_grant"] as JSON).data()) }
                    }
                    let token = "token\(next)"
                    tokens.insert(token)
                    let reply: JSON = ["access_token": .string(token), "refresh_token": "refresh", "expires_in": 3600, "token_type": "Bearer"]
                    return (200, [:], reply.data())
                }
                guard let bearer = headers["authorization"], bearer.hasPrefix("Bearer "), tokens.contains(String(bearer.dropFirst(7))) else {
                    return (401, [:], (["error": "invalid_token"] as JSON).data())
                }
                let id = json?["id"] ?? .null
                switch json?["method"]?.string {
                case "initialize":
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
                    let name = json?["params"]?["name"]?.string ?? ""
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

    func testSHA256MatchesKnownDigests() {
        XCTAssertEqual(SHA256Digest.hash(Data()).map { String(format: "%02x", $0) }.joined(),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Digest.hash(Data("abc".utf8)).map { String(format: "%02x", $0) }.joined(),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        // RFC 7636 appendix B.
        XCTAssertEqual(WorkspaceLink.base64url(SHA256Digest.hash(Data("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk".utf8))),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testAuthorizesOnceAndKeepsTheGrant() async throws {
        let poki = FakePoki()
        let saved = LockedGrant()
        let link = WorkspaceLink(address: try XCTUnwrap(WorkspaceLinkAddress(Self.url)), http: poki, saveGrant: { saved.value = $0 })
        _ = await link.call("look", arguments: "{}")
        _ = await link.call("look", arguments: "{}")
        XCTAssertEqual(poki.count("/register"), 1)
        XCTAssertEqual(poki.count("/authorize"), 1)
        XCTAssertNotNil(saved.value)
        // A later launch with the kept grant asks nobody again.
        let later = WorkspaceLink(address: try XCTUnwrap(WorkspaceLinkAddress(Self.url)), http: poki, grant: saved.value)
        let look = await later.call("look", arguments: "{}")
        XCTAssertFalse(look.isError, look.text)
        XCTAssertEqual(poki.count("/authorize"), 1)
    }

    func testARefusedTokenAuthorizesAgainBeforeTheCall() async throws {
        let poki = FakePoki()
        let link = WorkspaceLink(address: try XCTUnwrap(WorkspaceLinkAddress(Self.url)), http: poki)
        _ = await link.call("look", arguments: "{}")
        poki.revokeTokens()
        let act = await link.call("do", arguments: #"{"actions":[{"tap":3}]}"#)
        XCTAssertFalse(act.isError, act.text)
        XCTAssertEqual(poki.count("/authorize"), 2)
        // The refused call never reached the other Poki, so it ran once.
        XCTAssertEqual(poki.mcpCalls.filter { $0["method"]?.string == "tools/call" && $0["params"]?["name"]?.string == "do" }.count, 2)
    }

    func testTheOwnerSayingNoIsAnError() async throws {
        let poki = FakePoki()
        poki.allow = false
        let link = WorkspaceLink(address: try XCTUnwrap(WorkspaceLinkAddress(Self.url)), http: poki)
        let look = await link.call("look", arguments: "{}")
        XCTAssertTrue(look.isError)
        XCTAssertTrue(look.text.contains("did not allow"), look.text)
        XCTAssertTrue(poki.mcpCalls.isEmpty)
    }

    final class LockedGrant: @unchecked Sendable {
        let lock = NSLock()
        var stored: WorkspaceLinkGrant?
        var value: WorkspaceLinkGrant? { get { lock.withLock { stored } } set { lock.withLock { stored = newValue } } }
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
        let methods = poki.mcpCalls.compactMap { $0["method"]?.string }
        XCTAssertEqual(methods, ["initialize", "notifications/initialized", "tools/call", "tools/call"])
        let last = try XCTUnwrap(poki.requests.last)
        XCTAssertNotNil(last.headers["mcp-session-id"])
        XCTAssertEqual(last.body?["params"]?["arguments"]?["actions"]?[0]?["tap"]?.int, 3)
        XCTAssertEqual(last.headers["accept"], "application/json, text/event-stream")
        XCTAssertTrue(last.headers["authorization"]?.hasPrefix("Bearer token") == true)
    }

    func testANewSessionWhenTheOtherPokiForgotIt() async throws {
        let poki = FakePoki()
        let link = WorkspaceLink(address: try XCTUnwrap(WorkspaceLinkAddress(Self.url)), http: poki)
        _ = await link.call("look", arguments: "{}")
        poki.forgetSessions()
        let again = await link.call("look", arguments: "{}")
        XCTAssertFalse(again.isError, again.text)
        XCTAssertEqual(poki.mcpCalls.filter { $0["method"]?.string == "initialize" }.count, 2)
    }

    func testALostDoSaysTheActionsMayHaveRun() async throws {
        let poki = FakePoki()
        poki.failCalls = [502]
        let link = WorkspaceLink(address: try XCTUnwrap(WorkspaceLinkAddress(Self.url)), http: poki)
        let act = await link.call("do", arguments: #"{"actions":[{"tap":3}]}"#)
        XCTAssertTrue(act.isError)
        XCTAssertTrue(act.text.contains("may have run"), act.text)
        // Never sent again by the link itself.
        XCTAssertEqual(poki.mcpCalls.filter { $0["method"]?.string == "tools/call" }.count, 1)
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
