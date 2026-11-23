import XCTest

extension SimFixtureTests {
    func freshWalk(_ tag: String) {
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        guard let app = PBHelper.axAppElement(pid) as AnyObject? else { say("WF | \(tag) | no app element"); return }
        var labels: [String] = []; let n = axCount(app, 0, &labels)
        let wb = axFind(app, "WebButton")
        say("WF | \(tag) | fresh app element walk count \(n) | WebButton \(wb != nil) | labels \(labels.prefix(8))")
        if let wb { let before = lastEvent(); let r = PBHelper.axPerform(wb, action: 2010); usleep(1_200_000); say("WF | \(tag) | press 2010 \(r) | before \(before) after \(lastEvent()) | label \(PBHelper.axLabel(wb))") }
        else {
            // find where it stops: the web view element and its children
            func findType(_ r: AnyObject, _ d: Int = 0) -> AnyObject? { var e: Int32 = 0; let t = PBHelper.axCopy(r, attr: 5003, err: &e); if "\(t ?? "")" == "58" { return r }; if d > 30 { return nil }; for k in axKids(r) { if let f = findType(k, d + 1) { return f } }; return nil }
            if let wv = findType(app) { var e: Int32 = 0; let k = PBHelper.axCopy(wv, attr: 5001, err: &e); say("WF | \(tag) | stops at webView element label '\(PBHelper.axLabel(wv))' | children err \(e) value \(String(describing: k).prefix(120))") } else { say("WF | \(tag) | no webView element in fresh walk") }
        }
    }
    func testWEBFRESH() {
        covLaunch(tab: "Web", bg: false); _ = fixture.buttons["WebButton"].waitForExistence(timeout: 20)
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        background = true; _ = PBHelper.requestBackgroundAssertion(forPID: pid); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(3)
        freshWalk("web tab visible then bg"); fixture.terminate()
        covLaunch(tab: "Web", bg: false); _ = fixture.buttons["WebButton"].waitForExistence(timeout: 20)
        fixture.tabBars.buttons["UIKit"].tap(); sleep(1)
        let pid2 = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        background = true; _ = PBHelper.requestBackgroundAssertion(forPID: pid2); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(3)
        freshWalk("web shown once, other tab, then bg"); fixture.terminate()
        covLaunch(tab: "UIKit", bg: true)
        freshWalk("web never shown")
        fixture.terminate()
    }
}
