import Foundation
import PokiCore
import XCTest
@testable import Poki

private final class DirectVoiceTimingStub: URLProtocol {
    static let baseURL = "https://voice-direct-timing.test/v1"
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host() == "voice-direct-timing.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = #"{"value":"ek_direct_timing","model":"gpt-realtime-2.1"}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class MacToolsBridgeStub: URLProtocol {
    static let address = "http://voice-mac-tools-timing.test/voice/0123456789abcdef"
    private static let lock = NSLock()
    nonisolated(unsafe) static var tapChangesScreen = true
    nonisolated(unsafe) static var tapBridgeMS = 180
    nonisolated(unsafe) static var readBridgeMS = 95

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host() == "voice-mac-tools-timing.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.lastPathComponent ?? ""
        let body: String
        if path == "token" {
            body = #"{"value":"ek_mac_bridge","model":"gpt-realtime-2.1","local_tools":["get_ios_version"]}"#
        } else if path == "tool" {
            let payload = readBody(request)
            let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
            let name = json["name"] as? String ?? ""
            let checked = json["checked"] as? [String: Any]
            let (changesScreen, tapMS, readMS) = Self.lock.withLock { (Self.tapChangesScreen, Self.tapBridgeMS, Self.readBridgeMS) }
            if name == "tap_text", checked == nil {
                body = #"{"call_id":"t1","state":"check","app":{"bundle_id":"com.apple.calculator","name":"Calculator"},"target":{"text":"7","says":"7"},"ms":45,"action_host":"mac_tools","observation_source":"mac_mcp_accessibility","effective_action":false,"target_confirmed":false,"replayed":false}"#
            } else if name == "tap_text" {
                let change = changesScreen ? "changed" : "unchanged"
                let confirmed = changesScreen ? "true" : "false"
                body = #"{"call_id":"t1","state":"done","output":"{\"sent\":true,\"screen_change\":\"\#(change)\",\"screen_change_verified\":true}","ms":\#(tapMS),"action_host":"mac_tools","observation_source":"mac_mcp_action_readback","effective_action":true,"target_confirmed":\#(confirmed),"replayed":false}"#
            } else if name == "read_screen" {
                body = #"{"call_id":"r1","state":"done","output":"{\"source\":\"accessibility\",\"elements\":[{\"label\":\"7\"}]}","ms":\#(readMS),"action_host":"mac_tools","observation_source":"mac_mcp_accessibility","effective_action":false,"target_confirmed":true,"replayed":false}"#
            } else {
                body = #"{"call_id":"x","state":"done","output":"{\"opened\":\"Settings\"}","ms":60,"action_host":"mac_tools","observation_source":"mac_mcp_action","effective_action":true,"target_confirmed":true,"replayed":false}"#
            }
        } else {
            body = "{}"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private func readBody(_ request: URLRequest) -> Data {
        if let data = request.httpBody, !data.isEmpty { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@MainActor
final class VoiceTurnTimingTests: XCTestCase {
    private var savedBridge: String?
    private var savedDirectEnabled: Any?
    private var savedCustomProviders: [CustomProvider] = []

    override func setUp() {
        savedBridge = UserDefaults.standard.string(forKey: "voiceBridge")
        savedDirectEnabled = UserDefaults.standard.object(forKey: "voice.openai.enabled")
        savedCustomProviders = CustomProviders.all
        VoiceDirect.enabled = false
        CustomProviders.all = []
        AppLog.shared.clear()
        URLProtocol.registerClass(BridgeStub.self)
        URLProtocol.registerClass(DirectVoiceTimingStub.self)
        URLProtocol.registerClass(MacToolsBridgeStub.self)
        MacToolsBridgeStub.tapChangesScreen = true
        MacToolsBridgeStub.tapBridgeMS = 180
        MacToolsBridgeStub.readBridgeMS = 95
    }

    override func tearDown() {
        URLProtocol.unregisterClass(BridgeStub.self)
        URLProtocol.unregisterClass(DirectVoiceTimingStub.self)
        URLProtocol.unregisterClass(MacToolsBridgeStub.self)
        CustomProviders.all = savedCustomProviders
        UserDefaults.standard.set(savedBridge, forKey: "voiceBridge")
        UserDefaults.standard.set(savedDirectEnabled, forKey: "voice.openai.enabled")
    }

    private func makeModel(time: FakeTime,
                           clearTap: @escaping @MainActor (String, String?, String?) async -> TapClearance = { _, _, _ in .clear },
                           phoneTool: @escaping @MainActor (String, String) async -> PhoneAnswer = { _, _ in ("", false, nil) }) -> (voice: VoiceModel, link: () -> FakeConnection) {
        var latest: FakeConnection!
        let voice = VoiceModel(
            clearTap: clearTap,
            phoneTool: { name, arguments, _ in await phoneTool(name, arguments) },
            connection: { onEvent, onClosed in
                let conn = FakeConnection()
                conn.onEvent = onEvent
                conn.onClosed = onClosed
                latest = conn
                return conn
            },
            time: time.clock
        )
        voice.onConversationEnded = { _, _ in }
        return (voice, { latest })
    }

    private func timingLines() -> [String] {
        AppLog.shared.lines.filter { $0.contains("[\(VoiceTurnTiming.logArea)]") }
    }

    func testPhoneDirectSilentTurnLogsCompleteTimelineAndAnnotations() async throws {
        var provider = CustomProvider(name: "Direct Test", endpoints: [CustomEndpoint(url: DirectVoiceTimingStub.baseURL)], model: "gpt-realtime-2.1")
        provider.liveVoice = true
        CustomProviders.all = [provider]

        let time = FakeTime()
        let (voice, getLink) = makeModel(time: time, phoneTool: { name, _ in
            await time.clock.sleep(.milliseconds(140))
            if name == "look" {
                return ("app: Calculator   read: 2026-11-22T01:00:00Z (40 ms)\nelements (1):\n 1 Button \"7\" [10,10,40,40]", false, Data("before".utf8))
            }
            return ("app: Calculator   read: 2026-11-22T01:00:00Z (50 ms)\ndid: tap \"7\" (sent, 30 ms)\nscreen_changed: true (the elements changed)\nelements (1):\n~1 StaticText \"7\" [10,10,40,40]", false, Data("after".utf8))
        })
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])

        voice.say(pcm24k: Data(repeating: 0, count: 4_800))
        await time.advance(0.08)
        link.play(["type": "conversation.item.added", "item": ["role": "user"]])
        await time.advance(0.12)
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c-look", "name": "look", "arguments": "{}"]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await time.advance(0.14)
        await time.advance(0.10)
        link.play(
            ["type": "response.created", "response": ["id": "r2"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c-tap", "name": "do", "arguments": #"{"actions":[{"tap":1}]}"#]],
            ["type": "response.done", "response": ["id": "r2"]]
        )
        await time.advance(0.14)
        await time.advance(0.09)
        link.play(
            ["type": "response.created", "response": ["id": "r3"]],
            ["type": "output_audio_buffer.started"],
            ["type": "response.output_audio_transcript.done", "transcript": "7 is entered."],
            ["type": "response.done", "response": ["id": "r3"]],
            ["type": "output_audio_buffer.stopped"]
        )

        XCTAssertEqual(voice.clock.entryRoute, .directEphemeralCredential)
        XCTAssertEqual(voice.clock.voiceHost, .phoneDirect)
        XCTAssertEqual(voice.clock.actionHost, .phoneLocal)
        XCTAssertEqual(voice.clock.observationSource, .phoneTreeAndScreenshot)
        XCTAssertEqual(voice.clock.ms(.said), 0)
        XCTAssertEqual(voice.clock.ms(.heard), 80)
        XCTAssertEqual(voice.clock.ms(.call), 200)
        XCTAssertEqual(voice.clock.ms(.firstEffectiveAction), 440, "look is read-only; first effective action starts at do")
        XCTAssertEqual(voice.clock.ms(.toolDone), 580)
        XCTAssertEqual(voice.clock.ms(.targetConfirmed), 580)
        XCTAssertEqual(voice.clock.ms(.delivered), 580)
        XCTAssertEqual(voice.clock.ms(.spoken), 670)
        XCTAssertEqual(voice.clock.phoneLocalMS, 280)
        XCTAssertEqual(voice.clock.macToolsMS, 0)

        let logs = timingLines()
        let entry = try XCTUnwrap(logs.first { $0.contains("event=entry_selected") })
        XCTAssertTrue(entry.contains("entry_route=direct_ephemeral_credential"), entry)
        XCTAssertTrue(entry.contains("voice_host=phone_direct"), entry)
        XCTAssertTrue(entry.contains("default_action_host=phone_local"), entry)
        let spoken = try XCTUnwrap(logs.last { $0.contains("event=turn_spoken") })
        for expected in [
            "flow=voice", "entry_route=direct_ephemeral_credential", "voice_host=phone_direct",
            "action_host=phone_local", "observation_source=phone_tree_and_screenshot",
            "said_ms=0", "heard_ms=80", "call_ms=200", "first_effective_action_ms=440",
            "tool_done_ms=580", "target_confirmed_ms=580", "delivered_ms=580", "spoken_ms=670",
            "phone_local_ms=280", "mac_tools_ms=0",
        ] {
            XCTAssertTrue(spoken.contains(expected), "missing \(expected) in \(spoken)")
        }
        voice.stop()
    }

    func testVoiceBridgePhoneLocalSilentTurnSeparatesVoiceHostFromActionHost() async throws {
        let time = FakeTime()
        let (voice, getLink) = makeModel(time: time, phoneTool: { _, _ in
            await time.clock.sleep(.milliseconds(160))
            return ("app: Settings   read: 2026-11-22T01:00:00Z (60 ms)\ndid: launch com.apple.Preferences (sent, 90 ms)\nscreen_changed: true (the elements changed)\nelements (2):\n 1 StaticText \"Settings\" [0,0,100,40]", false, Data("settings".utf8))
        })
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])

        voice.say(pcm24k: Data(repeating: 0, count: 4_800))
        await time.advance(0.06)
        link.play(["type": "conversation.item.added", "item": ["role": "user"]])
        await time.advance(0.10)
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c-open", "name": "do", "arguments": #"{"actions":[{"launch":"com.apple.Preferences"}]}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await time.advance(0.16)
        await time.advance(0.09)
        link.play(
            ["type": "response.created", "response": ["id": "r2"]],
            ["type": "output_audio_buffer.started"],
            ["type": "response.output_audio_transcript.done", "transcript": "Settings is open."],
            ["type": "response.done", "response": ["id": "r2"]],
            ["type": "output_audio_buffer.stopped"]
        )

        XCTAssertEqual(voice.clock.entryRoute, .voiceBridge)
        XCTAssertEqual(voice.clock.voiceHost, .voiceBridge)
        XCTAssertEqual(voice.clock.actionHost, .phoneLocal)
        XCTAssertEqual(voice.clock.observationSource, .phoneTreeAndScreenshot)
        XCTAssertEqual(voice.clock.ms(.firstEffectiveAction), 160)
        XCTAssertEqual(voice.clock.ms(.targetConfirmed), 320)
        XCTAssertEqual(voice.clock.ms(.spoken), 410)
        XCTAssertEqual(voice.clock.phoneLocalMS, 160)
        XCTAssertEqual(voice.clock.macToolsMS, 0)

        let logs = timingLines()
        let entry = try XCTUnwrap(logs.first { $0.contains("event=entry_selected") })
        let spoken = try XCTUnwrap(logs.last { $0.contains("event=turn_spoken") })
        XCTAssertTrue(entry.contains("entry_route=voice_bridge"), entry)
        XCTAssertTrue(entry.contains("default_action_host=phone_local"), entry)
        for expected in [
            "entry_route=voice_bridge", "voice_host=voice_bridge", "action_host=phone_local",
            "observation_source=phone_tree_and_screenshot", "said_ms=0", "heard_ms=60",
            "call_ms=160", "first_effective_action_ms=160", "tool_done_ms=320",
            "target_confirmed_ms=320", "delivered_ms=320", "spoken_ms=410",
            "phone_local_ms=160", "mac_tools_ms=0",
        ] {
            XCTAssertTrue(spoken.contains(expected), "missing \(expected) in \(spoken)")
        }
        voice.stop()
    }

    func testMacToolsTurnAttributesDurationToActionHostAndNeverPhoneDirect() async throws {
        let time = FakeTime()
        let approvalEntered = expectation(description: "tap_text reached phone approval check")
        let (voice, getLink) = makeModel(time: time, clearTap: { _, _, _ in
            approvalEntered.fulfill()
            await time.clock.sleep(.milliseconds(200))
            return .approved("owner tapped allow")
        })
        XCTAssertTrue(voice.setBridge(MacToolsBridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])

        voice.say(pcm24k: Data(repeating: 0, count: 4_800))
        await time.advance(0.05)
        link.play(["type": "conversation.item.added", "item": ["role": "user"]])
        await time.advance(0.07)
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "t1", "name": "tap_text", "arguments": #"{"text":"7"}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await fulfillment(of: [approvalEntered], timeout: 2)
        await time.advance(0.20)
        let delivered = expectation(for: NSPredicate { _, _ in voice.clock.delivered != nil }, evaluatedWith: nil)
        await fulfillment(of: [delivered], timeout: 2)
        await time.advance(0.08)
        link.play(
            ["type": "response.created", "response": ["id": "r2"]],
            ["type": "output_audio_buffer.started"],
            ["type": "response.output_audio_transcript.done", "transcript": "Tapped 7."],
            ["type": "response.done", "response": ["id": "r2"]],
            ["type": "output_audio_buffer.stopped"]
        )

        XCTAssertEqual(voice.clock.entryRoute, .voiceBridge)
        XCTAssertEqual(voice.clock.voiceHost, .voiceBridge)
        XCTAssertEqual(voice.clock.actionHost, .macTools)
        XCTAssertEqual(voice.clock.observationSource, .macMCPActionReadback)
        XCTAssertEqual(voice.clock.phoneLocalMS, 0, "Mac tool execution must never be charged to phone_local or phone_direct")
        XCTAssertGreaterThanOrEqual(voice.clock.macToolsMS, 225, "Mac check (45 ms) + checked tap (180 ms) must accrue under mac_tools")
        XCTAssertEqual(voice.clock.ms(.call), 120)
        XCTAssertEqual(voice.clock.ms(.firstEffectiveAction), 320, "first effective action begins after approval check, not during check")
        XCTAssertNotNil(voice.clock.ms(.targetConfirmed))

        let logs = timingLines()
        let entry = try XCTUnwrap(logs.first { $0.contains("event=entry_selected") })
        let actionEnd = try XCTUnwrap(logs.last { $0.contains("event=action_end") })
        let spoken = try XCTUnwrap(logs.last { $0.contains("event=turn_spoken") })
        XCTAssertTrue(entry.contains("default_action_host=mac_tools"), entry)
        XCTAssertTrue(actionEnd.contains("action_host=mac_tools"), actionEnd)
        XCTAssertTrue(actionEnd.contains("bridge_ms=225"), actionEnd)
        XCTAssertTrue(spoken.contains("voice_host=voice_bridge"), spoken)
        XCTAssertTrue(spoken.contains("action_host=mac_tools"), spoken)
        XCTAssertTrue(spoken.contains("observation_source=mac_mcp_action_readback"), spoken)
        XCTAssertTrue(spoken.contains("phone_local_ms=0"), spoken)
        XCTAssertTrue(spoken.contains("mac_tools_ms=225"), spoken)
        XCTAssertFalse(spoken.contains("phone_direct"), spoken)
        voice.stop()
    }

    func testMacToolsUnchangedTapWaitsForReadScreenToConfirmTarget() async {
        MacToolsBridgeStub.tapChangesScreen = false
        let time = FakeTime()
        let (voice, getLink) = makeModel(time: time)
        XCTAssertTrue(voice.setBridge(MacToolsBridgeStub.address))
        voice.muted = true
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])
        voice.say(pcm24k: Data(repeating: 0, count: 1_200))

        await time.advance(0.10)
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "t1", "name": "tap_text", "arguments": #"{"text":"7"}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        let tapDelivered = expectation(for: NSPredicate { _, _ in voice.calls.first(where: { $0.id == "t1" })?.delivered == true }, evaluatedWith: nil)
        await fulfillment(of: [tapDelivered], timeout: 2)
        XCTAssertEqual(voice.clock.ms(.firstEffectiveAction), 100)
        XCTAssertNil(voice.clock.targetConfirmed, "unchanged Mac screen_change must not claim target confirmation")
        XCTAssertEqual(voice.clock.phoneLocalMS, 0)
        XCTAssertGreaterThanOrEqual(voice.clock.macToolsMS, 225)

        await time.advance(0.06)
        link.play(
            ["type": "response.created", "response": ["id": "r2"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "r1", "name": "read_screen", "arguments": "{}"]],
            ["type": "response.done", "response": ["id": "r2"]]
        )
        let readDelivered = expectation(for: NSPredicate { _, _ in voice.calls.first(where: { $0.id == "r1" })?.delivered == true }, evaluatedWith: nil)
        await fulfillment(of: [readDelivered], timeout: 2)
        XCTAssertEqual(voice.clock.ms(.targetConfirmed), 160)
        XCTAssertEqual(voice.clock.observationSource, .macMCPAccessibility)
        XCTAssertEqual(voice.clock.phoneLocalMS, 0)
        XCTAssertGreaterThanOrEqual(voice.clock.macToolsMS, 320)
        voice.stop()
    }

    func testUnconfirmedAndRefusedActionsWaitForFreshConfirmationOrExternalVerifier() async {
        let time = FakeTime()
        var step = 0
        let (voice, getLink) = makeModel(time: time, phoneTool: { name, _ in
            step += 1
            await time.clock.sleep(.milliseconds(50))
            if step == 1 {
                return ("not_sent: element 9 is not in the latest read; nothing was sent.", true, nil)
            }
            if step == 2 {
                return ("app: Calculator   read: 2026-11-22T01:00:00Z (30 ms)\ndid: tap \"7\" (sent, 20 ms)\nscreen_changed: false (the elements and the picture are the same)\ntouch effect: unconfirmed", false, Data("same".utf8))
            }
            return ("app: Calculator   read: 2026-11-22T01:00:00Z (35 ms)\nelements (1):\n 1 StaticText \"7\" [10,10,40,40]", false, Data("verified".utf8))
        })
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])
        voice.say(pcm24k: Data(repeating: 0, count: 1_200))

        await time.advance(0.10)
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": #"{"actions":[{"tap":9}]}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await time.advance(0.05)
        XCTAssertNil(voice.clock.firstEffectiveAction, "not_sent refusal must not count as an effective action")
        XCTAssertNil(voice.clock.targetConfirmed, "not_sent refusal must not confirm the target")

        await time.advance(0.05)
        link.play(
            ["type": "response.created", "response": ["id": "r2"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c2", "name": "do", "arguments": #"{"actions":[{"tap":1}]}"#]],
            ["type": "response.done", "response": ["id": "r2"]]
        )
        await time.advance(0.05)
        XCTAssertEqual(voice.clock.ms(.firstEffectiveAction), 200)
        XCTAssertNil(voice.clock.targetConfirmed, "touch effect: unconfirmed must not mark target confirmed")

        await time.advance(0.05)
        link.play(
            ["type": "response.created", "response": ["id": "r3"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c3", "name": "look", "arguments": "{}"]],
            ["type": "response.done", "response": ["id": "r3"]]
        )
        await time.advance(0.05)
        XCTAssertEqual(voice.clock.ms(.targetConfirmed), 350)

        await time.advance(0.04)
        voice.confirmTarget(source: .independentObserver)
        XCTAssertEqual(voice.clock.ms(.targetConfirmed), 390)
        XCTAssertEqual(voice.clock.observationSource, .independentObserver)
        voice.stop()
    }

    func testEntryRouteResolutionCoversAllFourRoutesInPriorityOrder() {
        let custom = VoiceAccount.custom(UUID())
        XCTAssertEqual(
            VoiceEntryRoute.resolve(directAccount: .openai, hasDirectKey: true, hasBridge: true, canDictate: true, microphone: true, chatProvider: .chatgpt, chatGPTSignedIn: true, rehearsing: false),
            .directEphemeralCredential
        )
        XCTAssertEqual(
            VoiceEntryRoute.resolve(directAccount: custom, hasDirectKey: true, hasBridge: true, canDictate: true, microphone: true, chatProvider: .anthropic, chatGPTSignedIn: false, rehearsing: false),
            .directEphemeralCredential
        )
        XCTAssertEqual(
            VoiceEntryRoute.resolve(directAccount: nil, hasDirectKey: false, hasBridge: true, canDictate: true, microphone: true, chatProvider: .chatgpt, chatGPTSignedIn: true, rehearsing: false),
            .voiceBridge
        )
        XCTAssertEqual(
            VoiceEntryRoute.resolve(directAccount: nil, hasDirectKey: false, hasBridge: false, canDictate: true, microphone: true, chatProvider: .anthropic, chatGPTSignedIn: false, rehearsing: false),
            .dictationChatTTS
        )
        XCTAssertEqual(
            VoiceEntryRoute.resolve(directAccount: nil, hasDirectKey: false, hasBridge: false, canDictate: true, microphone: true, chatProvider: .chatgpt, chatGPTSignedIn: true, rehearsing: false),
            .chatgptResponses
        )
        XCTAssertNil(
            VoiceEntryRoute.resolve(directAccount: nil, hasDirectKey: false, hasBridge: false, canDictate: true, microphone: false, chatProvider: .chatgpt, chatGPTSignedIn: true, rehearsing: false)
        )
    }

    func testTimingMetadataDoesNotAddCharactersToModelToolOutputsOrSessionPrompt() async throws {
        let time = FakeTime()
        let rawOutput = "Settings is open"
        let (voice, getLink) = makeModel(time: time, phoneTool: { _, _ in (rawOutput, false, nil) })
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        await voice.start(microphone: false)
        let link = getLink()
        link.play(["type": "session.created"])
        voice.say(pcm24k: Data(repeating: 0, count: 1_200))
        link.play(
            ["type": "response.created", "response": ["id": "r1"]],
            ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "c1", "name": "do", "arguments": #"{"actions":[{"tap":1}]}"#]],
            ["type": "response.done", "response": ["id": "r1"]]
        )
        await time.settle()

        let toolOutputEvent = try XCTUnwrap(link.sent.first { ($0["item"] as? [String: Any])?["type"] as? String == "function_call_output" })
        let sentOutput = try XCTUnwrap((toolOutputEvent["item"] as? [String: Any])?["output"] as? String)
        XCTAssertEqual(sentOutput, rawOutput, "Timing annotations must never lengthen tool outputs sent to the model")
        let instructions = try XCTUnwrap(VoiceDirect.session["instructions"] as? String)
        XCTAssertFalse(instructions.contains("voice_host"))
        XCTAssertFalse(instructions.contains("action_host"))
        voice.stop()
    }
}
