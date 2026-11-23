import XCTest

extension SimFixtureTests {
    func testBUTTONVARIANTS() {
        covLaunch(tab: "UIKit", bg: true)
        for (name, id) in [("configured (Configuration + primaryAction)", "cov.configured"), ("addAction primaryActionTriggered", "cov.uiaction"), ("addTarget touchUpInside", "cov.target"), ("menu button", "cov.menu"), ("Push detail (addAction)", "cov.push")] {
            let e = find(snap()) { $0.identifier == id }; let b = lastEvent(); var err: NSString?
            let ok = e.map { PBHelper.pressSnapshot($0, action: 2010, value: nil, error: &err) } ?? false; usleep(900_000)
            say("BV | \(name) | 2010 via testmanagerd \(ok) | before \(b) after \(lastEvent())")
        }
        fixture.terminate()
    }
}
