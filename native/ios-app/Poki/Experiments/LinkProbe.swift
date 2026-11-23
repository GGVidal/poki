#if POKI_EXPERIMENTS && targetEnvironment(simulator)
import Foundation
import PokiCore

// Poki Lab, simulator only (issue #689): the two-simulator link check without tapping through.
// `-pokiInProcess link-host -pokiLinkRelay http://localhost:8787` (the iPad): sets the relay, opens
// the in-process session, adds a connector named iPhone link, writes its address to
// Documents/link-address.txt, and allows the link's one sign-in as the owner would (a simulator
// check has no owner at the screen; a device build never compiles this).
// `-pokiInProcess link-client -pokiLinkAddress URL` (the iPhone): saves the address as the iPad
// Workspace, then calls the iPad's status and look through it, into Documents/link-check.json.
@MainActor
enum LinkProbe {
    static func documents(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    }

    static func host(model: AppModel, probe: InProcessProbe) async {
        let relay = UserDefaults.standard.string(forKey: "pokiLinkRelay") ?? "http://localhost:8787"
        guard model.setRelay(relay) else { probe.note("link-host: relay address refused: \(relay)", ["step": "relay", "ok": false]); return }
        let ready = await probe.prepare()
        if ready { model.inProcessReadyForProbe() }
        model.labStartRelay()
        let secret = model.addConnector(name: "iPhone link")
        guard let url = model.connectorURL(for: secret) else { probe.note("link-host: no connector URL", ["step": "connector", "ok": false]); return }
        try? url.absoluteString.write(to: documents("link-address.txt"), atomically: true, encoding: .utf8)
        probe.note("link-host: relay \(relay), session \(ready ? "open" : "not open"), connector ready", ["step": "host_ready", "session": ready])
        // Allow sign-ins from the iPhone link for 10 minutes.
        let until = Date().addingTimeInterval(600)
        var allowed = 0
        while Date() < until {
            if let ask = model.connectionAsk {
                probe.note("link-host: allowing \(ask.client) through \(ask.connector) (simulator check)", ["step": "allow", "client": ask.client])
                model.answerConnection(true)
                allowed += 1
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        probe.note("link-host: done, \(allowed) sign-ins allowed", ["step": "done", "allowed": allowed])
    }

    /// `-pokiInProcess display-check` (the iPad, with its external display powered on): lists the
    /// displays, runs Check Displays, chooses the first display that is not the main one, reads and taps
    /// through PokiCore as an agent would, then sets the workspace display back to Off. Into
    /// Documents/display-check.json.
    static func displayCheck(model: AppModel, probe: InProcessProbe) async {
        var out: [String: Any] = [:]
        let ready = await probe.prepare()
        if ready { model.inProcessReadyForProbe() }
        out["session"] = ready
        let queue = DispatchQueue(label: "poki.lab.display.check")
        func onQueue<T>(_ work: @escaping () -> T) async -> T { await withCheckedContinuation { c in queue.async { c.resume(returning: work()) } } }
        let displays = await onQueue { PKInProcess.shared().labDisplays() }
        out["displays"] = displays
        out["check"] = await onQueue { PKInProcess.shared().labDisplayCheck() }
        let other = displays.first { ($0["main"] as? Bool) == false }.flatMap { ($0["id"] as? NSNumber) }
        out["chosen"] = other ?? NSNull()
        if let other {
            await onQueue { PKInProcess.shared().labDisplayID = other }
            for (label, tool, args) in [("look", "look", "{}"), ("tap", "do", "{\"actions\":[{\"tap\":[200,200]}]}"), ("home", "do", "{\"actions\":[{\"button\":\"home\"}]}")] {
                let answer = await model.phoneToolWithPicture(tool, arguments: args)
                out[label] = ["error": answer.isError, "picture": answer.jpeg?.count ?? 0, "text": String(answer.text.prefix(1200))]
                if let jpeg = answer.jpeg { try? jpeg.write(to: documents("display-\(label).jpg")) }
            }
            await onQueue { PKInProcess.shared().labDisplayID = nil }
            out["after_off"] = await onQueue { PKInProcess.shared().labDisplayID == nil }
        }
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: documents("display-check.json")) }
        probe.note("display-check done", ["step": "done"])
    }

    static func client(probe: InProcessProbe) async {
        guard let address = UserDefaults.standard.string(forKey: "pokiLinkAddress"), WorkspaceLinkStore.save(address) else {
            probe.note("link-client: no valid -pokiLinkAddress", ["step": "address", "ok": false]); return
        }
        var results: [[String: Any]] = []
        for (tool, args) in [("status", "{}"), ("look", "{}"), ("do", "{\"actions\":[{\"launch\":\"com.apple.Preferences\"},{\"wait\":1500}]}"), ("look", "{}")] {
            let t = Date()
            guard let link = WorkspaceLinkStore.link else { break }
            let answer = await link.call(tool, arguments: args, timeout: 120)
            let entry: [String: Any] = ["tool": tool, "error": answer.isError, "seconds": Date().timeIntervalSince(t), "picture": answer.jpeg?.count ?? 0, "text": String(answer.text.prefix(1500))]
            results.append(entry)
            probe.note("link-client: \(tool) \(answer.isError ? "failed" : "ok") in \(String(format: "%.1f", Date().timeIntervalSince(t))) s: \(answer.text.prefix(160))", entry.merging(["step": "call"]) { a, _ in a })
            if let jpeg = answer.jpeg { try? jpeg.write(to: documents("link-\(tool)-\(results.count).jpg")) }
        }
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted]) { try? data.write(to: documents("link-check.json")) }
    }
}

import SwiftUI

/// `-pokiShowLab ipadWorkspace|workspaceDisplay` opens that Lab page over the app at launch, for
/// screenshots without tapping through.
struct LabPagePreview: ViewModifier {
    @State private var page = UserDefaults.standard.string(forKey: "pokiShowLab")
    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { page != nil }, set: { if !$0 { page = nil } })) {
            NavigationStack {
                if page == "workspaceDisplay" { WorkspaceDisplayView(back: {}) } else { WorkspaceLinkView(back: {}) }
            }
        }
    }
}
#endif
