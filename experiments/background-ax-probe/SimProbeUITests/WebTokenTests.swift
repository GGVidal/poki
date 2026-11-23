import XCTest

extension SimFixtureTests {
    func testWEBTOKEN() {
        covLaunch(tab: "Web", bg: false); _ = fixture.buttons["WebButton"].waitForExistence(timeout: 20)
        func dump(_ tag: String) {
            var found: [XCUIElementSnapshot] = []; func w(_ e: XCUIElementSnapshot) { if e.elementType == .webView || e.elementType == .other && e.children.contains(where: { $0.label == "WebButton" }) { found.append(e) }; e.children.forEach(w) }; if let s = snap() { w(s) }
            say("TOK | \(tag) | webView-ish elements \(found.count)")
            for e in found.prefix(2) { say("TOK | \(tag) | type \(e.elementType.rawValue) label '\(e.label)' | 2022 \(PBHelper.rawAttribute(2022, onSnapshot: e)) | 2023 \(PBHelper.rawAttribute(2023, onSnapshot: e)) | 2018 \(PBHelper.rawAttribute(2018, onSnapshot: e))") }
        }
        dump("fg")
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        background = true; _ = PBHelper.requestBackgroundAssertion(forPID: pid); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(3)
        dump("bg")
        fixture.terminate()
    }
}
