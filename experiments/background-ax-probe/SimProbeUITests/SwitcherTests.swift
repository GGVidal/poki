import XCTest

extension SimFixtureTests {
    func sampleCtx(_ tag: String, _ secs: Double, _ app: XCUIElementSnapshot) -> Int {
        let t0 = Date(); var last = ""; var nz = 0; var fired = false
        while Date().timeIntervalSince(t0) < secs {
            let r = PBHelper.rawAttribute(2021, onSnapshot: app)
            if r != last { say("SW | \(tag) t=\(String(format: "%.2f", Date().timeIntervalSince(t0))) 2021 \(r)"); last = r }
            if r.hasPrefix("err 0 ") && r != "err 0 0" {
                nz += 1
                if !fired, let b = find(snap(), { $0.identifier == "cov.target" }) {
                    fired = true; let before = lastEvent(); let f = fkaFocus(b); var e: NSString?
                    let ok = PBHelper.pressSnapshot(app, action: 4000, value: nil, error: &e); usleep(400_000)
                    say("SW | \(tag) press in window: focus \(f) 4000 \(ok) | before \(before) after \(lastEvent()) | fixture state \(fixture.state.rawValue)")
                }
            }
            usleep(50_000)
        }
        return nz
    }
    func testSWITCHER_background() {
        covLaunch(tab: "UIKit", bg: true)
        guard let app = snap() else { return }
        _ = sampleCtx("baseline", 2, app)
        // (a) app switcher: home, then swipe up and hold from the bottom on springboard
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home); sleep(1)
        let start = sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995)); let mid = sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: mid, withVelocity: 300, thenHoldForDuration: 1.0)
        say("SW | switcher opened? front \(String(frontSummary().prefix(30))) | fixture state \(fixture.state.rawValue)")
        let nzA = sampleCtx("switcher", 5, app)
        XCUIDevice.shared.press(.home); sleep(1); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10)
        say("SW | (a) nonzero samples \(nzA)")
        // (b) appearance is driven from the host; here (c) rotation
        XCUIDevice.shared.orientation = .landscapeLeft
        let nzC = sampleCtx("rotate", 3, app)
        XCUIDevice.shared.orientation = .portrait; _ = sampleCtx("rotate back", 2, app)
        say("SW | (c) nonzero samples \(nzC) | front \(String(frontSummary().prefix(30))) | fixture state \(fixture.state.rawValue) | last=\(lastEvent())")
        fixture.terminate()
    }
}
