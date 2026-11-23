import XCTest

extension SimFixtureTests {
    func testATTACHED() {
        background = true
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        say("ATT | fixture state \(fixture.state.rawValue) pid \(pid) | front \(String(frontSummary().prefix(20)))")
        if pid > 0 { _ = PBHelper.requestBackgroundAssertion(forPID: pid) }
        var tree: XCUIElementSnapshot? = nil
        for _ in 0..<15 { tree = snap(); if all(tree).count > 5 { break }; sleep(1) }
        let n = all(tree).count
        guard let app = tree else { say("ATT | no tree"); return }
        let t0 = Date(); var lastNZ = -1.0; var first = "?"
        while Date().timeIntervalSince(t0) < 10 { let r = PBHelper.rawAttribute(2021, onSnapshot: app); if first == "?" { first = r }; if r.hasPrefix("err 0 ") && r != "err 0 0" { lastNZ = Date().timeIntervalSince(t0) }; usleep(100_000) }
        say("ATT | elements \(n) | context first read '\(first)' | last non-zero at \(String(format: "%.1f", lastNZ)) s over 10 s")
        for (name, pick) in [("UIButton target", { (e: XCUIElementSnapshot) in e.identifier == "cov.target" }), ("switch", { (e: XCUIElementSnapshot) in e.identifier == "cov.switch" }), ("first cell", { (e: XCUIElementSnapshot) in e.elementType == .cell }), ("tab Lists", { (e: XCUIElementSnapshot) in e.elementType == .button && e.label == "Lists" })] {
            let e = find(snap(), pick); let before = lastEvent()
            let r = e == nil ? "not found" : act(e, 2010); usleep(1_000_000)
            say("ATT | \(name) | 2010 \(r.prefix(60)) | before \(before) after \(lastEvent())")
        }
        say("ATT | front \(String(frontSummary().prefix(20))) | state \(fixture.state.rawValue)")
    }
}
