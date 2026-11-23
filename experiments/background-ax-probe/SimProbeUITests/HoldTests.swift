import XCTest

extension SimFixtureTests {
    func holdVariant(_ v: Int) {
        background = false; fixture.launchArguments = ["-coverage"]; fixture.launch(); sleep(2)
        guard let a0 = snap() else { say("HOLD | v\(v) | no app"); return }
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        if v == 2 { _ = PBHelper.requestBackgroundAssertion(forPID: pid) }
        let suiAlive = v == 5
        if suiAlive { fixture.tabBars.buttons["SwiftUI"].tap(); sleep(1) }
        let sui = suiAlive ? find(snap()) { $0.identifier == "sui.button" } : nil
        var stop = false
        if v == 3 || v == 5 { DispatchQueue.global().async { while !stop { if v == 3 { _ = PBHelper.rawAttribute(2001, onSnapshot: a0) } else if let s = sui { var e: NSString?; _ = PBHelper.pressSnapshot(s, action: 2010, value: nil, error: &e) }; usleep(100_000) } } }
        if v == 4 { DispatchQueue.global().async { _ = PBHelper.daemonParamAttribute(95005, onSnapshot: a0, parameter: ["AXAuditDynamicTextSupportTest": ["AXAuditShouldRunTestOption": true]] as NSDictionary) }; usleep(200_000) }
        let t0 = Date(); settings.activate()
        var last = "?"; var purgeAt = -1.0; var cameBack = false; var maxNonzero = 0.0
        while Date().timeIntervalSince(t0) < 60 {
            let r = PBHelper.rawAttribute(2021, onSnapshot: a0); let nz = r.hasPrefix("err 0 ") && r != "err 0 0"
            let t = Date().timeIntervalSince(t0)
            if nz { maxNonzero = t; if purgeAt >= 0 { cameBack = true } } else if purgeAt < 0 && last == "nz" { purgeAt = t }
            last = nz ? "nz" : "z"
            usleep(50_000)
        }
        stop = true
        say("HOLD | v\(v) | context last non-zero at \(String(format: "%.2f", maxNonzero)) s | purge seen at \(String(format: "%.2f", purgeAt)) s | came back \(cameBack) | front \(String(frontSummary().prefix(20)))")
        fixture.terminate(); sleep(1)
    }
    func testHOLDS() { for v in 1...5 { holdVariant(v) } }
}
