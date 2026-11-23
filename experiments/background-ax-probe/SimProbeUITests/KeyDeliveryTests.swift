import XCTest

extension SimFixtureTests {
    func stamp() -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f.string(from: Date()) }
    func keySeries(_ tag: String) {
        for k in ["a", "\r", " ", "\t", "UIKeyInputEscape", "UIKeyInputDownArrow"] {
            let before = lastEvent(); let r = sendKey(k); usleep(600_000)
            say("KD | \(tag) | \(stamp()) key \(k.replacingOccurrences(of: "\r", with: "Return").replacingOccurrences(of: "\t", with: "Tab").replacingOccurrences(of: " ", with: "Space")) \(r) | before \(before) after \(lastEvent())")
        }
    }
    func testKEYDELIVERY() {
        covLaunch(tab: "UIKit", bg: false); keySeries("fg no responder"); fixture.terminate()
        covLaunch(tab: "UIKit", bg: true); keySeries("bg no responder"); fixture.terminate()
        // text field first responder in foreground, then background
        covLaunch(tab: "UIKit", bg: false)
        fixture.textFields["cov.field"].firstMatch.tap(); sleep(1)
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        background = true; _ = PBHelper.requestBackgroundAssertion(forPID: pid); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(2)
        say("KD | field fr→bg | \(stamp()) start | value \(String(describing: find(snap()) { $0.identifier == "cov.field" }?.value ?? "nil"))")
        for k in ["x", "y", "\r"] { let before = lastEvent(); let r = sendKey(k); usleep(700_000); say("KD | field fr→bg | \(stamp()) key \(k == "\r" ? "Return" : k) \(r) | before \(before) after \(lastEvent()) | value \(String(describing: find(snap()) { $0.identifier == "cov.field" }?.value ?? "nil"))") }
        fixture.terminate()
        // first responder via setter 3002 in background
        covLaunch(tab: "UIKit", bg: true)
        var err: NSString?
        if let f = find(snap(), { $0.identifier == "cov.field" }) { say("KD | field 3002 bg | set focused \(PBHelper.setAttribute("XC_kAXXCAttributeFocused", value: true, onSnapshot: f, error: &err)) \(String(describing: err ?? "").prefix(60))") }
        for k in ["q", "\r"] { let before = lastEvent(); let r = sendKey(k); usleep(700_000); say("KD | field 3002 bg | \(stamp()) key \(k == "\r" ? "Return" : k) \(r) | before \(before) after \(lastEvent()) | value \(String(describing: find(snap()) { $0.identifier == "cov.field" }?.value ?? "nil"))") }
        fixture.terminate()
    }
}
