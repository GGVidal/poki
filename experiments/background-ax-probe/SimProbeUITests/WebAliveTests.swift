import XCTest

extension SimFixtureTests {
    func testWEBALIVE() {
        covLaunch(tab: "Web", bg: false)
        _ = fixture.buttons["WebButton"].waitForExistence(timeout: 20)
        guard let bs = find(snap(), { $0.label == "WebButton" }), let b = PBHelper.axRef(bs) as AnyObject? else { say("WA | no button"); return }
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        say("WA | ready")
        var wpids: [Int32] = []
        for _ in 0..<60 { if let t = try? String(contentsOfFile: "/tmp/bgax/webpids.txt", encoding: .utf8), t.contains("END") { wpids = t.split(whereSeparator: { !$0.isNumber }).compactMap { Int32($0) }; break }; usleep(500_000) }
        background = true; _ = PBHelper.requestBackgroundAssertion(forPID: pid); for p in wpids { _ = PBHelper.requestBackgroundAssertion(forPID: p) }
        settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(3)
        let t0 = Date()
        for wait in [0, 30, 60, 120] {
            while Date().timeIntervalSince(t0) < Double(wait) { usleep(500_000) }
            let before = lastEvent(); let r = PBHelper.axPerform(b, action: 2010); usleep(1_000_000)
            let st = (wpids.first.map { p -> String in var info = kinfo_proc(); var size = MemoryLayout<kinfo_proc>.stride; var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, p]; sysctl(&mib, 4, &info, &size, nil, 0); return "stat \(info.kp_proc.p_stat)" }) ?? "-"
            say("WA | t=\(wait)s 2010 \(r) | label \(PBHelper.axLabel(b)) | before \(before) after \(lastEvent()) | webcontent \(st) | fixture state \(fixture.state.rawValue)")
        }
        say("WA | front \(String(frontSummary().prefix(25)))")
        fixture.terminate()
    }
}
