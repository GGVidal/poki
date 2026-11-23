import XCTest

extension SimFixtureTests {
    // Holds the fixture in the background while the host script fires outside events; samples the context id every 0.3 s for 90 s.
    func testOUTSIDE_sample() {
        covLaunch(tab: "UIKit", bg: true)
        say("OUT | ready")
        let t0 = Date(); var last: UInt32 = 99; var nonzero = 0
        while Date().timeIntervalSince(t0) < 90 {
            let c = snap().map { PBHelper.contextId(ofSnapshot: $0) } ?? 0
            if c != last { say("OUT | t=\(String(format: "%.1f", Date().timeIntervalSince(t0))) ctx \(c)"); last = c }
            if c != 0 {
                nonzero += 1
                if nonzero == 1, let b = find(snap(), { $0.identifier == "cov.target" }), let app = snap() {
                    let f = fkaFocus(b); var e: NSString?; let ok = PBHelper.pressSnapshot(app, action: 4000, value: nil, error: &e); usleep(500_000)
                    say("OUT | press during ctx: focus \(f) 4000 \(ok) last=\(lastEvent())")
                }
            }
            usleep(300_000)
        }
        say("OUT | done nonzero samples \(nonzero) last=\(lastEvent())")
        fixture.terminate()
    }
}
