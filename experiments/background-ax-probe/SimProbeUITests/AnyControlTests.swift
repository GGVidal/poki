import XCTest

extension SimFixtureTests {
    func kickNow() -> String {
        guard let a = snap() else { return "no app" }
        return String(PBHelper.daemonParamAttribute(95005, onSnapshot: a, parameter: ["AXAuditClippingTest": ["AXAuditShouldRunTestOption": true]] as NSDictionary).prefix(30))
    }
    func tryCtl(_ name: String, _ id: Int, _ pick: (XCUIElementSnapshot?) -> XCUIElementSnapshot?) {
        let e = pick(snap())
        let before = lastEvent()
        let r = e == nil ? "not found" : act(e, id); usleep(800_000)
        let mid = lastEvent(); _ = kickNow(); usleep(800_000)
        say("ANY | \(name) | \(id) \(r.prefix(40)) | before \(before) | after press \(mid == before ? "no change" : mid) | after kick \(lastEvent() == mid ? "no change" : lastEvent()) | nav \(navTitle())")
    }
    func testANY_swiftui_background() {
        covLaunch(tab: "SwiftUI", bg: true)
        tryCtl("SUIButton", 2010) { s in self.find(s) { $0.identifier == "sui.button" } }
        tryCtl("SUIToggle", 2010) { s in self.find(s) { $0.identifier == "sui.toggle" } }
        tryCtl("SUISegment P1", 2010) { s in self.find(self.find(s) { $0.identifier == "sui.segment" }) { $0.label == "P1" } }
        tryCtl("SUIStepper inc", 2004) { s in self.find(s) { $0.identifier == "sui.stepper" } }
        tryCtl("SUISlider inc", 2004) { s in self.find(s) { $0.identifier == "sui.slider" } }
        tryCtl("SUIMenu", 2010) { s in self.find(s) { $0.identifier == "sui.menu" } }
        tryCtl("InnerTabB", 2010) { s in self.find(s) { $0.label == "InnerTabB" } }
        tryCtl("SUIAlert button", 2010) { s in self.find(s) { $0.identifier == "sui.alert" } }
        tryCtl("SUILink", 2010) { s in self.find(s) { $0.identifier == "sui.link" } }
        say("ANY | front \(String(frontSummary().prefix(30)))")
        fixture.terminate()
    }
    func testANY_uikit_customactions() {
        covLaunch(tab: "UIKit", bg: true)
        for id in ["cov.menu", "cov.configured", "cov.target", "cov.switch", "cov.context"] {
            let e = find(snap()) { $0.identifier == id }
            say("ANY | custom actions \(id) | \(e.map { PBHelper.rawAttribute(2036, onSnapshot: $0) } ?? "not found")")
        }
        fixture.terminate()
        covLaunch(tab: "Lists", bg: true)
        var cells: [XCUIElementSnapshot] = []; func w(_ e: XCUIElementSnapshot) { if e.elementType == .cell { cells.append(e) }; e.children.forEach(w) }; if let s = snap() { w(s) }
        for (i, c) in cells.prefix(3).enumerated() { say("ANY | custom actions cell \(i) '\(c.label)' | \(PBHelper.rawAttribute(2036, onSnapshot: c))") }
        if let tb = find(snap(), { $0.elementType == .tabBar }) { for b in tb.children.prefix(2) { say("ANY | custom actions tab '\(b.label)' | \(PBHelper.rawAttribute(2036, onSnapshot: b))") } }
        fixture.terminate()
    }
    func testANY_web_kick() {
        covLaunch(tab: "Web", bg: false)
        _ = fixture.buttons["WebButton"].waitForExistence(timeout: 20)
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        background = true; _ = PBHelper.requestBackgroundAssertion(forPID: pid); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(3)
        say("ANY | web bg before kick | WebButton \(find(snap()) { $0.label == "WebButton" } != nil)")
        say("ANY | web kick \(kickNow())"); sleep(2)
        let b = find(snap()) { $0.label == "WebButton" }
        say("ANY | web bg after kick | WebButton \(b != nil)")
        if b != nil { tryCtl("WebButton", 2010) { s in self.find(s) { $0.label == "WebButton" } } }
        fixture.terminate()
    }
}
