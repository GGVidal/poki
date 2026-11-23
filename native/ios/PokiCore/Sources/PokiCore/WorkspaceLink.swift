import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The owner's other Poki, such as Poki on their iPad driving apps on its workspace display, as an MCP
/// server this Poki calls (issue #689). The address is that Poki's own connector URL: the owner makes a
/// connector on the iPad and pastes its URL here, so the link uses the same relay, the same secret and
/// the same approval rules as any other MCP client of that Poki. Nothing here weakens or replaces them.
public struct WorkspaceLinkAddress: Sendable, Equatable {
    public let url: URL

    /// Accepts `https://<relay>/v1/<label>/<secret>/mcp`. `http` only for a relay on this machine or
    /// the local network (`wrangler dev` on a Mac, as in the simulator demo), never for a public host.
    public init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(),
              !host.isEmpty, parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: true)
        guard path.count == 4, path[0] == "v1", path[3] == "mcp", path[1].count == 52, path[2].count >= 32 else { return nil }
        switch scheme {
        case "https": break
        case "http": guard Self.isLocal(host) else { return nil }
        default: return nil
        }
        guard let url = parts.url else { return nil }
        self.url = url
    }

    /// The relay host, for display: never the secret.
    public var host: String { url.host ?? "" }

    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]" || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (192, 168), (127, _): return true
        case (172, let b) where (16...31).contains(b): return true
        default: return false
        }
    }
}

/// One HTTP exchange with headers both ways. URLSession on the phone; a fake in tests.
public protocol WorkspaceHTTP: Sendable {
    func post(_ url: URL, headers: [String: String], body: Data, timeout: Double) async throws -> (status: Int, headers: [String: String], body: Data)
}

public final class URLSessionWorkspaceHTTP: WorkspaceHTTP {
    let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }
    deinit { session.finishTasksAndInvalidate() }

    public func post(_ url: URL, headers: [String: String], body: Data, timeout: Double) async throws -> (status: Int, headers: [String: String], body: Data) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            var out: [String: String] = [:]
            for (name, value) in http?.allHeaderFields ?? [:] {
                if let name = name as? String, let value = value as? String { out[name.lowercased()] = value }
            }
            return (http?.statusCode ?? 0, out, data)
        } catch let error as URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost: throw TransportError.refused
            case .timedOut: throw TransportError.timedOut
            default: throw TransportError.other(error.localizedDescription)
            }
        }
    }
}

/// Calls the linked Poki's tools over MCP's streamable HTTP with JSON answers (PokiCore never answers
/// with SSE). One MCP session, made on first use and made again when the other side forgets it.
/// One call at a time, as PokiCore serves them.
public actor WorkspaceLink {
    public let address: WorkspaceLinkAddress
    let http: WorkspaceHTTP
    let clientName: String
    private var session: String?
    private var nextID = 1

    public init(address: WorkspaceLinkAddress, http: WorkspaceHTTP = URLSessionWorkspaceHTTP(), clientName: String = "Poki on iPhone") {
        self.address = address
        self.http = http
        self.clientName = clientName
    }

    /// Calls `tool` on the linked Poki with the arguments JSON object the model sent. Never throws: a
    /// failure is an error answer the model can read. A `do` whose answer was lost says so, since the
    /// actions may have run on the other device.
    public func call(_ tool: String, arguments: String, timeout: Double = 170) async -> PokiCore.ToolAnswer {
        let args = (try? JSON.parse(arguments)) ?? .object([:])
        do {
            if session == nil { try await initialize() }
            var reply = try await rpc("tools/call", ["name": .string(tool), "arguments": args], timeout: timeout)
            if reply.status == 404 || reply.status == 400, reply.json?["error"] != nil || reply.json == nil {
                // The other Poki restarted and forgot the session: one fresh session, then the call again.
                // A 404 from the relay itself (wrong or revoked secret) comes back the same way the second time.
                session = nil
                try await initialize()
                reply = try await rpc("tools/call", ["name": .string(tool), "arguments": args], timeout: timeout)
            }
            return Self.answer(reply, tool: tool)
        } catch let refused as LinkRefused {
            return PokiCore.ToolAnswer(text: refused.message, jpeg: nil, isError: true)
        } catch TransportError.timedOut {
            return Self.lost(tool, "no answer came in time")
        } catch TransportError.refused {
            return PokiCore.ToolAnswer(text: "The linked Poki at \(address.host) could not be reached. Check that its relay is running and the address is right.", jpeg: nil, isError: true)
        } catch {
            return Self.lost(tool, "\(error)")
        }
    }

    /// Ends the MCP session on the other Poki, so a task it tracked for this client ends too.
    public func close() async { session = nil }

    struct LinkRefused: Error { let message: String }
    struct Reply { let status: Int; let headers: [String: String]; let json: JSON? }

    private func initialize() async throws {
        let reply = try await rpc("initialize", [
            "protocolVersion": .string(PokiCore.protocolVersions[0]),
            "capabilities": .object([:]),
            "clientInfo": ["name": .string(clientName), "version": "1.0"],
        ], timeout: 20)
        guard reply.status == 200, reply.json?["result"] != nil else {
            throw LinkRefused(message: Self.httpProblem(reply))
        }
        session = reply.headers["mcp-session-id"]
        _ = try? await notify("notifications/initialized")
    }

    private func rpc(_ method: String, _ params: JSON, timeout: Double) async throws -> Reply {
        let id = nextID
        nextID += 1
        let body: JSON = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params]
        let (status, headers, data) = try await http.post(address.url, headers: headers(), body: body.data(), timeout: timeout)
        return Reply(status: status, headers: headers, json: try? JSON.parse(data))
    }

    private func notify(_ method: String) async throws {
        let body: JSON = ["jsonrpc": "2.0", "method": .string(method)]
        _ = try await http.post(address.url, headers: headers(), body: body.data(), timeout: 10)
    }

    private func headers() -> [String: String] {
        var out = ["content-type": "application/json", "accept": "application/json, text/event-stream",
                   "mcp-protocol-version": PokiCore.protocolVersions[0]]
        if let session { out["mcp-session-id"] = session }
        return out
    }

    static func answer(_ reply: Reply, tool: String) -> PokiCore.ToolAnswer {
        guard reply.status == 200, let json = reply.json else {
            if reply.status == 502 || reply.status == 504 { return lost(tool, httpProblem(reply)) }
            return PokiCore.ToolAnswer(text: httpProblem(reply), jpeg: nil, isError: true)
        }
        if let error = json["error"] {
            return PokiCore.ToolAnswer(text: "The linked Poki refused the call: \(error["message"]?.string ?? "error \(error["code"]?.int ?? 0)")", jpeg: nil, isError: true)
        }
        let content = json["result"]?["content"]?.array ?? []
        let text = content.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }.joined(separator: "\n")
        let jpeg = content.first { $0["type"]?.string == "image" }.flatMap { $0["data"]?.string }.flatMap { Data(base64Encoded: $0) }
        return PokiCore.ToolAnswer(text: text, jpeg: jpeg, isError: json["result"]?["isError"]?.bool ?? false, screen: text)
    }

    static func lost(_ tool: String, _ why: String) -> PokiCore.ToolAnswer {
        let note = tool == "do" ? " The actions may have run on the linked device: look before doing them again." : ""
        return PokiCore.ToolAnswer(text: "The linked Poki's answer was lost (\(why)).\(note)", jpeg: nil, isError: true)
    }

    static func httpProblem(_ reply: Reply) -> String {
        if let message = reply.json?["error"]?["message"]?.string { return message }
        switch reply.status {
        case 404: return "The linked Poki does not know this address. Make a new connector on that device and paste its address again."
        case 503: return "The linked Poki is offline. Open Poki on that device."
        default: return "The linked Poki answered HTTP \(reply.status)."
        }
    }
}
