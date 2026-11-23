import XCTest

extension SimFixtureTests {
    func ctxLine(_ tag: String) {
        let s = snap(); var n = 0; func w(_ e: XCUIElementSnapshot) { n += 1; e.children.forEach(w) }; if let s { w(s) }
        say("HID | \(tag) | state \(fixture.state.rawValue) | ctx \(s.map { PBHelper.contextId(ofSnapshot: $0) } ?? 0) | elements \(n) | last=\(lastEvent()) | front \(String(frontSummary().prefix(25)))")
    }
    func testHIDDEN_launch() {
        background = true
        fixture.terminate(); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(1)
        say("HID | open suspended: \(PBHelper.fbsOpen("local.pokimcp.axfixture", optionKeys: ["FBSOpenApplicationOptionKeyActivateSuspended"]))")
        sleep(2)
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        say("HID | pid \(pid) assertion \(pid > 0 ? "\(PBHelper.requestBackgroundAssertion(forPID: pid) ?? -1)" : "none")")
        ctxLine("after suspended open +2s"); sleep(3); ctxLine("+5s")
        if let b = find(snap(), { $0.label == "Plain button" }) {
            say("HID | plain 2010 \(act(b, 2010).prefix(40)) | last=\(lastEvent())")
            let f = fkaFocus(b); var e: NSString?
            if let app = snap() { let ok = PBHelper.pressSnapshot(app, action: 4000, value: nil, error: &e); usleep(800_000); say("HID | focus \(f) 4000 \(ok) | last=\(lastEvent())") }
        } else { say("HID | no Plain button in tree") }
        fixture.terminate()
        // B5: open suspended on an app already in ordinary background
        covLaunch(tab: "UIKit", bg: true)
        ctxLine("bg before reopen")
        say("HID | reopen suspended: \(PBHelper.fbsOpen("local.pokimcp.axfixture", optionKeys: ["FBSOpenApplicationOptionKeyActivateSuspended"]))")
        let t0 = Date(); var seen: Set<String> = []
        while Date().timeIntervalSince(t0) < 5 {
            let c = snap().map { PBHelper.contextId(ofSnapshot: $0) } ?? 0
            let k = "state \(fixture.state.rawValue) ctx \(c != 0 ? "nonzero" : "0") front \(settings.state.rawValue == 4 ? "settings" : "other")"
            if !seen.contains(k) { seen.insert(k); say("HID | t=\(String(format: "%.1f", Date().timeIntervalSince(t0))) \(k)") }
            usleep(100_000)
        }
        ctxLine("after reopen 5s")
        fixture.terminate()
    }
}
