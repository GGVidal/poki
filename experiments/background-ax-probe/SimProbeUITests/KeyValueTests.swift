import XCTest

extension SimFixtureTests {
    func selTab() -> String { find(find(snap(), { $0.elementType == .tabBar }), { $0.elementType == .button && $0.isSelected })?.label ?? "none" }
    func state() -> String { "last=\(lastEvent()) | tab \(selTab()) | nav \(navTitle())" }
    func testKEYS_dump() {
        fixture.launchArguments = ["-coverage", "-dumpkeys"]; fixture.launch(); sleep(5)
        say("KEYSDUMP | done"); fixture.terminate()
    }
    func testKEYS_background() {
        let cmd = UInt(1 << 20), shift = UInt(1 << 17), ctrl = UInt(1 << 18)
        covLaunch(tab: "UIKit", bg: true)
        say("KEYBG | start | \(state())")
        for (name, k, m) in [("Cmd+1", "1", cmd), ("Cmd+2", "2", cmd), ("Cmd+3", "3", cmd), ("Ctrl+Tab", "\t", ctrl), ("Cmd+Shift+]", "]", cmd | shift), ("Cmd+Shift+[", "[", cmd | shift)] {
            let r = sendModKey(k, "modifierState", m); usleep(1_000_000)
            say("KEYBG | \(name) | \(r) | \(state())")
        }
        fixture.terminate()
        covLaunch(tab: "UIKit", presenter: "cov.push", bg: true)
        say("KEYBG | detail start | \(state())")
        for (name, k, m) in [("Cmd+[", "[", cmd), ("Cmd+Left", "UIKeyInputLeftArrow", cmd), ("Escape", "UIKeyInputEscape", UInt(0)), ("Cmd+.", ".", cmd)] {
            let r = sendModKey(k, "modifierState", m); usleep(1_000_000)
            say("KEYBG | \(name) | \(r) | \(state())")
        }
        if let a = snap() { say("KEYBG | kick \(PBHelper.daemonParamAttribute(95005, onSnapshot: a, parameter: ["AXAuditClippingTest": ["AXAuditShouldRunTestOption": true]] as NSDictionary).prefix(60))") }
        sleep(1); say("KEYBG | after kick | \(state())")
        fixture.terminate()
    }
    func testSETVALUE_background() {
        covLaunch(tab: "UIKit", bg: true)
        func el(_ id: String) -> XCUIElementSnapshot? { find(snap()) { $0.identifier == id } }
        func set(_ name: String, _ id: String, _ v: Any) {
            var err: NSString?
            let ok = PBHelper.setAttribute("XC_kAXXCAttributeValue", value: v, onSnapshot: el(id) as Any, error: &err)
            usleep(800_000)
            say("SETV | \(name) | \(ok ? "ok" : "fail") \(String(describing: err ?? "").prefix(90)) | last=\(lastEvent())")
        }
        set("switch \"1\"", "cov.switch", "1"); set("switch \"0\"", "cov.switch", "0"); set("switch NSNumber 1", "cov.switch", NSNumber(value: 1))
        set("stepper \"5\"", "cov.stepper", "5")
        if el("cov.slider") != nil { set("slider \"0.8\"", "cov.slider", "0.8") } else { say("SETV | slider | not on this screen") }
        set("field \"hello\"", "cov.field", "hello")
        if let a = snap() { say("SETV | kick \(PBHelper.daemonParamAttribute(95005, onSnapshot: a, parameter: ["AXAuditClippingTest": ["AXAuditShouldRunTestOption": true]] as NSDictionary).prefix(60))") }
        sleep(1)
        let vals = ["cov.switch", "cov.stepper", "cov.field"].map { "\($0)=\(String(describing: el($0)?.value ?? "nil"))" }
        say("SETV | after kick | last=\(lastEvent()) | \(vals)")
        fixture.terminate()
    }
}
