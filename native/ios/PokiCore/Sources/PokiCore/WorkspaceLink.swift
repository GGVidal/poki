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

/// One HTTP exchange with headers both ways, never following a redirect (the OAuth answer is the
/// redirect itself). URLSession on the phone; a fake in tests.
public protocol WorkspaceHTTP: Sendable {
    func send(_ method: String, _ url: URL, headers: [String: String], body: Data?, timeout: Double) async throws -> (status: Int, headers: [String: String], body: Data)
}

public final class URLSessionWorkspaceHTTP: NSObject, WorkspaceHTTP, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!
    public override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    deinit { session.finishTasksAndInvalidate() }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    public func send(_ method: String, _ url: URL, headers: [String: String], body: Data?, timeout: Double) async throws -> (status: Int, headers: [String: String], body: Data) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
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

/// The OAuth grant the relay gave this link, kept by the app (in the keychain) between launches.
public struct WorkspaceLinkGrant: Codable, Sendable, Equatable {
    public var clientID: String
    public var accessToken: String
    public var refreshToken: String?
    public var expires: Date
    public init(clientID: String, accessToken: String, refreshToken: String?, expires: Date) {
        self.clientID = clientID; self.accessToken = accessToken; self.refreshToken = refreshToken; self.expires = expires
    }
}

/// Calls the linked Poki's tools over MCP's streamable HTTP with JSON answers (PokiCore never answers
/// with SSE). The relay asks every client for OAuth, and so does this one: it registers, asks to be
/// authorized (the owner allows it once in Poki on the other device, as for any agent), and keeps the
/// grant, refreshing it as it expires. One MCP session, made again when the other side forgets it.
public actor WorkspaceLink {
    public static let redirectURI = "http://127.0.0.1/poki-workspace-link"
    public let address: WorkspaceLinkAddress
    let http: WorkspaceHTTP
    let clientName: String
    private var session: String?
    private var nextID = 1
    private var grant: WorkspaceLinkGrant?
    private let saveGrant: @Sendable (WorkspaceLinkGrant?) -> Void
    let now: @Sendable () -> Date

    public init(address: WorkspaceLinkAddress, http: WorkspaceHTTP = URLSessionWorkspaceHTTP(), clientName: String = "Poki on iPhone",
                grant: WorkspaceLinkGrant? = nil, saveGrant: @escaping @Sendable (WorkspaceLinkGrant?) -> Void = { _ in },
                now: @escaping @Sendable () -> Date = Date.init) {
        self.address = address
        self.http = http
        self.clientName = clientName
        self.grant = grant
        self.saveGrant = saveGrant
        self.now = now
    }

    /// Calls `tool` on the linked Poki with the arguments JSON object the model sent. Never throws: a
    /// failure is an error answer the model can read. A `do` whose answer was lost says so, since the
    /// actions may have run on the other device. A call is never sent twice once it may have run.
    public func call(_ tool: String, arguments: String, timeout: Double = 170) async -> PokiCore.ToolAnswer {
        let args = (try? JSON.parse(arguments)) ?? .object([:])
        do {
            if session == nil { try await initialize() }
            var reply = try await rpc("tools/call", ["name": .string(tool), "arguments": args], timeout: timeout)
            if reply.status == 401 {
                // The token was refused before anything reached the other Poki: authorize again, then call.
                grant = nil
                saveGrant(nil)
                session = nil
                try await initialize()
                reply = try await rpc("tools/call", ["name": .string(tool), "arguments": args], timeout: timeout)
            } else if reply.status == 404 || reply.status == 400, reply.json?["error"] != nil {
                // The other Poki restarted and forgot the session; PokiCore refused it without running anything.
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

    /// Forgets the session and the grant, as when the owner removes the link.
    public func forget() { session = nil; grant = nil; saveGrant(nil) }

    struct LinkRefused: Error { let message: String }
    struct Reply { let status: Int; let headers: [String: String]; let json: JSON? }

    // MARK: OAuth (deploy/cf-relay/src/index.js: register, authorize with PKCE S256, token)

    var base: URL { address.url.deletingLastPathComponent() }

    private func accessToken() async throws -> String {
        if let grant, grant.expires.timeIntervalSince(now()) > 60 { return grant.accessToken }
        if let grant, let refresh = grant.refreshToken, let renewed = try? await exchange([
            "grant_type": "refresh_token", "refresh_token": refresh, "client_id": grant.clientID,
        ], clientID: grant.clientID) {
            return renewed.accessToken
        }
        return try await authorize().accessToken
    }

    private func authorize() async throws -> WorkspaceLinkGrant {
        let registration: JSON = ["client_name": .string(clientName), "redirect_uris": [.string(Self.redirectURI)],
                                  "token_endpoint_auth_method": "none", "grant_types": ["authorization_code", "refresh_token"]]
        let registered = try await http.send("POST", base.appendingPathComponent("register"), headers: ["content-type": "application/json"], body: registration.data(), timeout: 20)
        guard registered.status == 201, let clientID = (try? JSON.parse(registered.body))?["client_id"]?.string else {
            throw LinkRefused(message: Self.httpProblem(Reply(status: registered.status, headers: registered.headers, json: try? JSON.parse(registered.body))))
        }
        let verifier = Self.randomToken()
        let state = Self.randomToken()
        var ask = URLComponents(url: base.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        ask.queryItems = [
            URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI), URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.base64url(SHA256Digest.hash(Data(verifier.utf8)))),
            URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "resource", value: address.url.absoluteString),
        ]
        // Waits while the owner is asked on the other device (the relay allows 90 s).
        let asked = try await http.send("GET", ask.url!, headers: [:], body: nil, timeout: 120)
        guard (300..<400).contains(asked.status), let location = asked.headers["location"], let back = URLComponents(string: location) else {
            if asked.status == 503 { throw LinkRefused(message: "The linked Poki is offline. Open Poki on that device.") }
            throw LinkRefused(message: "The linked Poki did not authorize this iPhone (HTTP \(asked.status)).")
        }
        let items = back.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw LinkRefused(message: "The authorization came back for another request.") }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            let why = items.first(where: { $0.name == "error_description" })?.value ?? items.first(where: { $0.name == "error" })?.value ?? "no code"
            throw LinkRefused(message: "The owner did not allow this iPhone on the linked Poki (\(why)). Allow it there when Poki asks, then try again.")
        }
        return try await exchange(["grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI,
                                   "client_id": clientID, "code_verifier": verifier], clientID: clientID)
    }

    private func exchange(_ form: [String: String], clientID: String) async throws -> WorkspaceLinkGrant {
        var encoded = URLComponents()
        encoded.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = Data((encoded.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let answer = try await http.send("POST", base.appendingPathComponent("token"), headers: ["content-type": "application/x-www-form-urlencoded"], body: body, timeout: 20)
        let json = try? JSON.parse(answer.body)
        guard answer.status == 200, let access = json?["access_token"]?.string else {
            throw LinkRefused(message: "The linked Poki's relay refused the token (\(json?["error"]?.string ?? "HTTP \(answer.status)")).")
        }
        let fresh = WorkspaceLinkGrant(clientID: clientID, accessToken: access, refreshToken: json?["refresh_token"]?.string ?? grant?.refreshToken,
                                       expires: now().addingTimeInterval(json?["expires_in"]?.double ?? 3600))
        grant = fresh
        saveGrant(fresh)
        return fresh
    }

    // MARK: MCP

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
        _ = try? await post(["jsonrpc": "2.0", "method": "notifications/initialized"], timeout: 10)
    }

    private func rpc(_ method: String, _ params: JSON, timeout: Double) async throws -> Reply {
        let id = nextID
        nextID += 1
        return try await post(["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params], timeout: timeout)
    }

    private func post(_ body: JSON, timeout: Double) async throws -> Reply {
        var headers = ["content-type": "application/json", "accept": "application/json, text/event-stream",
                       "mcp-protocol-version": PokiCore.protocolVersions[0]]
        if let session { headers["mcp-session-id"] = session }
        headers["authorization"] = "Bearer " + (try await accessToken())
        let (status, replyHeaders, data) = try await http.send("POST", address.url, headers: headers, body: body.data(), timeout: timeout)
        return Reply(status: status, headers: replyHeaders, json: try? JSON.parse(data))
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
        case 404: return "The linked Poki does not know this address. Make a new agent address on that device and paste it again."
        case 503: return "The linked Poki is offline. Open Poki on that device."
        default: return "The linked Poki answered HTTP \(reply.status)."
        }
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return base64url(Data(bytes))
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// SHA-256 (FIPS 180-4) for the PKCE challenge, in Swift so PokiCore keeps building on Linux.
enum SHA256Digest {
    static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hash(_ data: Data) -> Data {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var message = [UInt8](data)
        let bits = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for i in (0..<8).reversed() { message.append(UInt8((bits >> (UInt64(i) * 8)) & 0xff)) }
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(message[j]) << 24 | UInt32(message[j + 1]) << 16 | UInt32(message[j + 2]) << 8 | UInt32(message[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        var out = Data()
        for word in h { for shift in [24, 16, 8, 0] { out.append(UInt8((word >> UInt32(shift)) & 0xff)) } }
        return out
    }
}
