import XCTest

extension SimFixtureTests {
    func ctxWatch(_ tag: String, _ secs: Double, _ during: (() -> Void)? = nil) {
        guard let a0 = snap() else { say("KL | \(tag) | no app"); return }
        let t0 = Date(); var lastNZ = -1.0; var samples = 0
        while Date().timeIntervalSince(t0) < secs {
            during?()
            let r = PBHelper.rawAttribute(2021, onSnapshot: a0); if r.hasPrefix("err 0 ") && r != "err 0 0" { lastNZ = Date().timeIntervalSince(t0) }
            samples += 1; usleep(50_000)
        }
        say("KL | \(tag) | samples \(samples) | last non-zero context at \(String(format: "%.2f", lastNZ)) s (−1 = never) | front \(String(frontSummary().prefix(18)))")
    }
    func testKEYLAUNCH() {
        let variants: [[String]] = [["-PPTFakeSuspendEvent", "NO"], ["-UIApplicationAutomaticSnapshotDefault", "NO"], ["-RemoteViewControllerSnapshotDelay", "60"], ["-SuspendedEventsOnly", "YES"]]
        for v in variants {
            background = true; fixture.launchArguments = ["-coverage"] + v; fixture.launch(); sleep(2)
            let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
            _ = PBHelper.requestBackgroundAssertion(forPID: pid); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10)
            ctxWatch("args \(v.joined(separator: " "))", 20)
            fixture.terminate(); sleep(1)
        }
        // screenshot of the background app while sampling
        background = true; fixture.launchArguments = ["-coverage"]; fixture.launch(); sleep(2)
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        _ = PBHelper.requestBackgroundAssertion(forPID: pid); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10)
        var shots = 0
        ctxWatch("app.screenshot() each sample", 15) { _ = self.fixture.screenshot(); shots += 1 }
        say("KL | screenshots taken \(shots)")
        fixture.terminate()
    }
}
