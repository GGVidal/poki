import XCTest

extension SimFixtureTests {
    func webCached(kick: Bool) {
        covLaunch(tab: "Web", bg: false)
        _ = fixture.buttons["WebButton"].waitForExistence(timeout: 20)
        guard let b = find(snap(), { $0.label == "WebButton" }) else { say("WEBC | no WebButton fg"); return }
        let el = (b as AnyObject).value(forKey: "accessibilityElement")
        say("WEBC | fg element \(String(describing: el).prefix(160)) | ctx \(PBHelper.contextId(ofSnapshot: b)) | raw label \(PBHelper.rawAttribute(2001, onSnapshot: b))")
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        say("WEBC | ready")
        var wpids: [Int32] = []
        for _ in 0..<60 { if let t = try? String(contentsOfFile: "/tmp/bgax/webpids.txt", encoding: .utf8), t.contains("END") { wpids = t.split(whereSeparator: { !$0.isNumber }).compactMap { Int32($0) }; break }; usleep(500_000) }
        background = true; _ = PBHelper.requestBackgroundAssertion(forPID: pid)
        say("WEBC | web pid assertions \(wpids.map { "\($0)=\(PBHelper.requestBackgroundAssertion(forPID: $0) ?? -1)" })")
        settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(3)
        if kick { say("WEBC | kick \(kickNow())"); usleep(800_000) }
        say("WEBC | bg cached label \(PBHelper.rawAttribute(2001, onSnapshot: b)) | ctx \(PBHelper.contextId(ofSnapshot: b))")
        let before = lastEvent(); var e: NSString?
        let ok = PBHelper.pressSnapshot(b, action: 2010, value: nil, error: &e); usleep(1_500_000)
        say("WEBC | bg cached 2010 \(ok ? "ok" : "fail \(String(describing: e ?? "").prefix(90))") | before \(before) after \(lastEvent()) | label now \(PBHelper.rawAttribute(2001, onSnapshot: b)) | front \(String(frontSummary().prefix(25)))")
        let before2 = lastEvent(); let d = PBHelper.directAction(2010, value: nil, onSnapshot: b); usleep(1_500_000)
        say("WEBC | bg cached direct AXUIElementPerformAction 2010 \(d) | before \(before2) after \(lastEvent()) | label now \(PBHelper.rawAttribute(2001, onSnapshot: b)) | front \(String(frontSummary().prefix(25)))")
        fixture.activate(); sleep(2)
        say("WEBC | end fg read: \(labels(snap()) { $0.label.hasPrefix("WebButton") }) | last=\(lastEvent())")
        fixture.terminate()
    }
    func testWEBCACHED() { webCached(kick: false); webCached(kick: true) }
    func testWEBCACHED_awake() { webCached(kick: true) }
}
