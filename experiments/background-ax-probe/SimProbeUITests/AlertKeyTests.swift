import XCTest

extension SimFixtureTests {
    func alertCase(_ presenter: String, _ tag: String) {
        covLaunch(tab: "UIKit", presenter: presenter, bg: true)
        say("AK | \(tag) | alert buttons in tree \(labels(snap()) { $0.label.hasPrefix("Alert") })")
        for (name, k) in [("Return", "\r"), ("Escape", "UIKeyInputEscape")] { let b = lastEvent(); let r = sendKey(k); usleep(900_000); say("AK | \(tag) | 2034 \(name) \(r) | before \(b) after \(lastEvent())") }
        for l in ["AlertOK", "AlertOther", "AlertCancel"] { if let e = find(snap(), { $0.label == l }) { let b = lastEvent(); let r = act(e, 2010); usleep(900_000); say("AK | \(tag) | 2010 \(l) \(r.prefix(30)) | before \(b) after \(lastEvent())"); break } }
        fixture.terminate()
    }
    func testALERTKEYS() { alertCase("cov.alert", "alert"); alertCase("cov.sheet", "sheet") }
}

extension SimFixtureTests {
    func alertPress(_ presenter: String, _ label: String) {
        covLaunch(tab: "UIKit", presenter: presenter, bg: true)
        let e = find(snap(), { $0.label == label }); let b = lastEvent(); let r = e == nil ? "not found" : act(e, 2010); usleep(900_000)
        say("AK2 | \(presenter) | 2010 \(label) \(r.prefix(30)) | before \(b) after \(lastEvent()) | still up \(find(snap(), { $0.label == label }) != nil)")
        fixture.terminate()
    }
    func testALERTPRESS() { for l in ["AlertOK", "AlertOther", "AlertCancel"] { alertPress("cov.alert", l) }; for l in ["AlertOK", "AlertOther"] { alertPress("cov.sheet", l) } }
}
