import XCTest

extension SimFixtureTests {
    func webDump(_ tag: String, _ pids: [Int32]) {
        for p in pids {
            var st: NSString?
            let s = PBHelper.snapshot(forPID: p, timeout: 8, status: &st)
            var n = 0, wb = false; func w(_ e: AnyObject) { n += 1; if (e.value(forKey: "label") as? String) == "WebButton" { wb = true }; for c in (e.value(forKey: "children") as? [AnyObject]) ?? [] { w(c) } }
            if let s { w(s as AnyObject) }
            say("WEBPID | \(tag) | pid \(p) | \(s == nil ? "nil" : String(describing: type(of: s!))) | status \(st ?? "-") | elements \(n) | WebButton \(wb)")
        }
    }
    func testWEBPID() {
        covLaunch(tab: "Web", bg: false)
        _ = fixture.buttons["WebButton"].waitForExistence(timeout: 20)
        let fpid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        say("WEBPID | ready fixture pid \(fpid)")
        var pids: [Int32] = []
        for _ in 0..<60 { if let s = try? String(contentsOfFile: "/tmp/bgax/webpids.txt", encoding: .utf8), s.contains("END") { pids = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int32($0) }; break }; usleep(500_000) }
        say("WEBPID | pids \(pids)")
        webDump("fg", pids)
        background = true
        _ = PBHelper.requestBackgroundAssertion(forPID: fpid); for p in pids { _ = PBHelper.requestBackgroundAssertion(forPID: p) }
        settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(3)
        webDump("bg", pids)
        fixture.terminate()
    }
}
