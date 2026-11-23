import XCTest

extension SimFixtureTests {
    func stackCase(_ name: String, bg: Bool, _ id: String) {
        covLaunch(tab: "UIKit", bg: bg)
        let r = act(find(snap()) { $0.identifier == id }, 2010); usleep(1_500_000)
        say("STACKT | \(name) | \(bg ? "bg" : "fg") | 2010 \(r.prefix(80)) | last=\(lastEvent())")
        fixture.terminate()
    }
    func testSTACK_background() { stackCase("baritem", bg: true, "cov.baritem") }
    func testSTACK_foreground() {
        stackCase("target", bg: false, "cov.target")
        stackCase("configured", bg: false, "cov.configured")
        stackCase("baritem", bg: false, "cov.baritem")
    }
}
