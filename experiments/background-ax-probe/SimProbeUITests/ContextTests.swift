import XCTest

extension SimFixtureTests {
    func testCONTEXT_background() {
        func btn() -> XCUIElementSnapshot? { find(snap()) { $0.identifier == "cov.configured" } }
        func ctx(_ step: String) -> Bool {
            guard let app = snap() else { say("CTX | \(step) | no app"); return false }
            let c = PBHelper.contextId(ofSnapshot: app)
            let b = btn(); let r = b.map { PBHelper.rawAttribute(2021, onSnapshot: $0) } ?? "no button"
            let bc = b.map { PBHelper.contextId(ofSnapshot: $0) } ?? 0
            say("CTX | \(step) | app ctx \(c) | button ctx \(bc) | 2021 \(r) | last=\(lastEvent())")
            return c != 0 || bc != 0 || (r.hasPrefix("err 0") && !r.hasSuffix(" 0") && !r.hasSuffix("nil"))
        }
        func pressIfCtx(_ step: String, _ nz: Bool) {
            guard nz, background, let app = snap() else { return }
            let f = fkaFocus(btn()); var e: NSString?
            let ok = PBHelper.pressSnapshot(app, action: 4000, value: nil, error: &e); usleep(1_000_000)
            say("CTX | \(step) press | focus \(f) | 4000 \(ok ? "ok" : "fail") | last=\(lastEvent())")
        }
        func kick(_ name: String, _ d: NSDictionary) -> String {
            guard let a = snap() else { return "no app" }
            let t0 = Date(); let r = PBHelper.daemonParamAttribute(95005, onSnapshot: a, parameter: d)
            return "\(name) \(String(format: "%.2f", Date().timeIntervalSince(t0))) s \(r.prefix(70))"
        }
        let clip: NSDictionary = ["AXAuditClippingTest": ["AXAuditShouldRunTestOption": true]]
        covLaunch(tab: "UIKit", bg: false)
        _ = ctx("a foreground")
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        background = true
        _ = PBHelper.requestBackgroundAssertion(forPID: pid); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10)
        sleep(3); pressIfCtx("b", ctx("b bg +3s"))
        let sid = (find(snap()) { $0.identifier == "sceneId" }?.value as? String) ?? ""
        if let app = snap() { var e: NSString?; say("CTX | c 5310 '\(sid.prefix(40))' \(PBHelper.pressSnapshot(app, action: 5310, value: sid as NSString, error: &e) ? "ok" : "fail")") }
        usleep(800_000); pressIfCtx("c", ctx("c after 5310"))
        if let app = snap() { var e: NSString?; say("CTX | d 5313 \(PBHelper.pressSnapshot(app, action: 5313, value: nil, error: &e) ? "ok" : "fail")") }
        usleep(800_000); pressIfCtx("d", ctx("d after 5313"))
        say("CTX | e kick \(kick("clip", clip))"); usleep(800_000); pressIfCtx("e", ctx("e after kick"))
        // regardless: focus + 4000, then kick
        if let app = snap() {
            let f = fkaFocus(btn()); var e: NSString?
            let ok = PBHelper.pressSnapshot(app, action: 4000, value: nil, error: &e); usleep(800_000)
            say("CTX | e2 focus \(f) | 4000 \(ok ? "ok" : "fail") | last=\(lastEvent())")
            say("CTX | e2 kick \(kick("clip", clip))"); sleep(1); say("CTX | e2 after kick | last=\(lastEvent())")
        }
        if let app = snap() { say("CTX | f reads 5039 \(PBHelper.rawAttribute(5039, onSnapshot: app)) | 5009 \(PBHelper.rawAttribute(5009, onSnapshot: app))") }
        pressIfCtx("f", ctx("f after snap + 5039/5009"))
        say("CTX | g kick \(kick("contrast", ["AXAuditContrastDetectionTest": ["AXAuditShouldRunTestOption": true]]))"); usleep(800_000); pressIfCtx("g", ctx("g after contrast"))
        say("CTX | h kick \(kick("inaccessible", ["AXAuditInaccessibileElementTest": ["AXAuditShouldRunTestOption": true]]))"); usleep(800_000); pressIfCtx("h", ctx("h after inaccessible"))
        say("CTX | front \(String(frontSummary().prefix(40)))")
        fixture.terminate()
    }
}
