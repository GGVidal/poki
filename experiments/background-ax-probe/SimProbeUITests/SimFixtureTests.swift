import XCTest

// Simulator only, against our own logging fixture. Maps AX action numbers to UIKit entry points and
// measures, per control type, whether an accessibility action reaches the handler with the fixture
// in the background (Settings in front) versus the foreground.
final class SimFixtureTests: XCTestCase {
    let fixture = XCUIApplication(bundleIdentifier: "local.pokimcp.axfixture")
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    var background = true

    func say(_ s: String) { print("SIMPROBE \(background ? "BG" : "FG") \(s)") }
    func snap() -> XCUIElementSnapshot? { try? fixture.snapshot() }
    func find(_ s: XCUIElementSnapshot?, _ match: (XCUIElementSnapshot) -> Bool) -> XCUIElementSnapshot? {
        guard let s else { return nil }
        if match(s) { return s }
        for c in s.children { if let h = find(c, match) { return h } }
        return nil
    }
    func lastEvent() -> String { (find(snap()) { $0.identifier == "lastEvent" }?.value as? String) ?? (find(snap()) { $0.identifier == "lastEvent" }?.label ?? "nil") }
    func navTitle() -> String { find(snap()) { $0.elementType == .navigationBar }?.identifier ?? "nil" }
    func act(_ e: XCUIElementSnapshot?, _ id: Int) -> String {
        guard let e else { return "element not found" }
        var err: NSString?
        let ok = PBHelper.pressSnapshot(e, action: id, error: &err)
        return ok ? "ok" : "fail(\((err ?? "") as String).prefix(60))"
    }

    func start(background bg: Bool) {
        background = bg
        fixture.launch()
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        if bg {
            say("assertion granted=\(String(describing: PBHelper.requestBackgroundAssertion(forPID: pid)))")
            settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10)
        }
        say("start fixture=\(fixture.state.rawValue) settings=\(settings.state.rawValue)")
    }

    func control(_ name: String, _ element: XCUIElementSnapshot?, _ id: Int, wait: UInt32 = 1) {
        let before = lastEvent()
        let r = act(element, id)
        sleep(wait)
        let after = lastEvent()
        say("CONTROL | \(name) | action \(id) | \(r) | handler: \(after == before ? "none" : after) | fixture=\(fixture.state.rawValue)")
    }

    func mapActions() {
        for id in (2001...2040) where id != 2025 {  // 2025 crashes the app (UIAccessibility _accessibilityAnnouncementComplete: nil dictionary)
            guard fixture.state == .runningBackground || fixture.state == .runningForeground else { say("MAP | fixture not running before \(id) (state \(fixture.state.rawValue))"); start(background: background); continue }
            let before = lastEvent()
            let r = act(find(snap()) { $0.identifier == "probeTarget" }, id)
            usleep(400_000)
            let after = fixture.state == .runningBackground || fixture.state == .runningForeground ? lastEvent() : "fixture died (state \(fixture.state.rawValue))"
            say("MAP | \(id) | \(r) | \(after == before ? "no entry point" : after)")
        }
    }

    func controls() {
        func byLabel(_ l: String, _ types: [XCUIElement.ElementType] = []) -> XCUIElementSnapshot? { find(snap()) { $0.label == l && (types.isEmpty || types.contains($0.elementType)) } }
        control("UIButton", byLabel("Plain button", [.button]), 2010)
        control("UISwitch", byLabel("Switch", [.switch]), 2010)
        control("UISegmentedControl segment", byLabel("Two", [.button]), 2010)
        control("UISlider increment", byLabel("Slider", [.slider]), 2004)
        let field = find(snap()) { $0.identifier == "field" }
        if let field { var err: NSString?; let ok = PBHelper.setAttribute("XC_kAXXCAttributeValue", value: "abc" as NSString, onSnapshot: field, error: &err); sleep(1); say("CONTROL | UITextField set value | XC_kAXXCAttributeValue | \(ok ? "ok" : "fail") | handler: \(lastEvent()) | value=\((find(snap()) { $0.identifier == "field" }?.value as? String) ?? "nil")") }
        control("UITableView cell", byLabel("Row 3", [.cell, .staticText]), 2010)
        let table = find(snap()) { $0.identifier == "bigTable" }
        control("UITableView page down (2006)", table, 2006)
        control("Custom action via ProbeTarget (2010)", find(snap()) { $0.identifier == "probeTarget" }, 2010)
        // alert
        control("Show alert button", byLabel("Show alert", [.button]), 2010, wait: 2)
        control("Alert OK button", byLabel("OK", [.button]), 2010, wait: 2)
        // sheet
        control("Show sheet button", byLabel("Show sheet", [.button]), 2010, wait: 2)
        control("Sheet Close (UIBarButtonItem in nav bar)", byLabel("Close", [.button]), 2010, wait: 2)
        // tab bar (bar button press moved to the push timing below: it pushes level 2)
        control("UITabBarController tab 'Second'", byLabel("Second", [.button]), 2010, wait: 2)
        control("UITabBarController tab 'Controls'", byLabel("Controls", [.button]), 2010, wait: 2)
        // navigation push timing (push triggered by the bar button item, which works in the background)
        let t0 = Date()
        _ = act(byLabel("Bar", [.button]), 2010)
        var seen = -1.0
        while Date().timeIntervalSince(t0) < 90 { if navTitle() == "Level 2" { seen = Date().timeIntervalSince(t0); break }; usleep(500_000) }
        say("TIMING | push level 2 | nav bar shows Level 2 after \(seen < 0 ? "never (90 s)" : String(format: "%.1f s", seen)) | last=\(lastEvent())")
        let t1 = Date()
        _ = act(byLabel("Activate push", [.button, .staticText, .other]), 2010)
        var seen3 = -1.0
        while Date().timeIntervalSince(t1) < 90 { if navTitle() == "Level 3" { seen3 = Date().timeIntervalSince(t1); break }; usleep(500_000) }
        say("TIMING | push level 3 | after \(seen3 < 0 ? "never (90 s)" : String(format: "%.1f s", seen3)) | last=\(lastEvent())")
        control("Back button (UINavigationBar)", find(snap()) { $0.elementType == .button && $0.label == "Level 2" }, 2010, wait: 3)
        say("after back nav=\(navTitle())")
        for (n, e) in [("app", snap()), ("navbar", find(snap()) { $0.elementType == .navigationBar }), ("content element", find(snap()) { $0.label == "Activate push" || $0.label == "Push level 3" })] {
            let before = navTitle()
            let r = act(e, 2013)
            sleep(3)
            say("ESCAPE | 2013 on \(n) | \(r) | nav \(before) -> \(navTitle()) | last=\(lastEvent())")
        }
        // SwiftUI
        control("UITabBarController tab 'SwiftUI'", byLabel("SwiftUI", [.button]), 2010, wait: 2)
        control("SwiftUI Button", byLabel("SwiftUI button", [.button]), 2010)
        control("SwiftUI NavigationLink", byLabel("SwiftUI detail", [.button, .cell]), 2010, wait: 3)
        control("SwiftUI TabView tab 'Inner B'", byLabel("Inner B", [.button]), 2010, wait: 2)
    }

    // K: novel routes for controls whose plain activate fails in the background.
    func tryAll(_ name: String, _ locate: () -> XCUIElementSnapshot?) {
        for id in (2001...2040) where id != 2025 && id != 2011 {
            guard fixture.state == .runningBackground || fixture.state == .runningForeground else { say("K | \(name) | fixture died before \(id)"); return }
            let before = lastEvent()
            let r = act(locate(), id)
            usleep(500_000)
            let after = lastEvent()
            if after != before { say("K | \(name) | action \(id) | \(r) | HANDLER: \(after)") }
        }
        say("K | \(name) | sweep done")
    }
    func setAttr(_ name: String, _ e: XCUIElementSnapshot?, _ attr: String, _ value: AnyObject) {
        guard let e else { say("K | \(name) | not found"); return }
        let before = lastEvent()
        var err: NSString?
        let ok = PBHelper.setAttribute(attr, value: value, onSnapshot: e, error: &err)
        usleep(800_000)
        let after = lastEvent()
        say("K | \(name) | setAttribute \(attr)=\(value) | \(ok ? "ok" : "fail \((err ?? "") as String)".prefix(90)) | handler: \(after == before ? "none" : after)")
    }
    func testNovelRoutes() {
        start(background: true)
        func byLabel(_ l: String, _ types: [XCUIElement.ElementType] = []) -> XCUIElementSnapshot? { find(snap()) { $0.label == l && (types.isEmpty || types.contains($0.elementType)) } }
        // value / selection setters
        setAttr("UISwitch", byLabel("Switch", [.switch]), "XC_kAXXCAttributeValue", "1" as NSString)
        setAttr("UISwitch", byLabel("Switch", [.switch]), "XC_kAXXCAttributeValue", NSNumber(value: 1))
        setAttr("UISwitch", byLabel("Switch", [.switch]), "XC_kAXXCAttributeSelected", NSNumber(value: true))
        setAttr("Table cell", byLabel("Row 3", [.cell]), "XC_kAXXCAttributeSelected", NSNumber(value: true))
        setAttr("Tab 'Second'", byLabel("Second", [.button]), "XC_kAXXCAttributeSelected", NSNumber(value: true))
        setAttr("UIButton", byLabel("Plain button", [.button]), "XC_kAXXCAttributeSelected", NSNumber(value: true))
        // focus then activate
        for (n, l, t) in [("UIButton", "Plain button", XCUIElement.ElementType.button), ("UISwitch", "Switch", .switch), ("Table cell", "Row 3", .cell), ("Tab 'Second'", "Second", .button)] {
            setAttr("\(n) focus", byLabel(l, [t]), "XC_kAXXCAttributeIsElementFocused", NSNumber(value: true))
            let before = lastEvent(); let r = act(byLabel(l, [t]), 2010); usleep(700_000)
            say("K | \(n) | focus then 2010 | \(r.prefix(60)) | handler: \(lastEvent() == before ? "none" : lastEvent())")
        }
        // containers
        let tabBar = find(snap()) { $0.elementType == .tabBar }
        for id in [2004, 2005] { let before = lastEvent(); let r = act(tabBar, id); sleep(1); say("K | tab bar container | \(id) | \(r.prefix(60)) | handler: \(lastEvent() == before ? "none" : lastEvent())") }
        // sweep remaining ids on each failing control
        tryAll("UIButton", { byLabel("Plain button", [.button]) })
        tryAll("UISwitch", { byLabel("Switch", [.switch]) })
        tryAll("Table cell", { byLabel("Row 3", [.cell]) })
        tryAll("Tab 'Second'", { byLabel("Second", [.button]) })
    }

    // P: explicit-context touch. Context id is captured while the fixture is in front.
    func testP_contextAddressedTap() {
        background = false
        say("P hand types: \(PBHelper.handTypeNames())")
        fixture.launch()
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        guard let button = find(snap(), { $0.label == "Plain button" && $0.elementType == .button }) else { say("P no button"); return }
        let ctx = PBHelper.contextId(ofSnapshot: button)
        let center = CGPoint(x: button.frame.midX, y: button.frame.midY)
        say("P fixture pid=\(pid) button center=\(center) contextId(fg)=\(ctx)")
        say("P assertion granted=\(String(describing: PBHelper.requestBackgroundAssertion(forPID: pid)))")
        background = true
        settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10)
        let bgCtx = find(snap(), { $0.label == "Plain button" && $0.elementType == .button }).map { PBHelper.contextId(ofSnapshot: $0) } ?? 0
        say("P contextId(bg, via AXElement)=\(bgCtx)")
        // hand type pairs to try are printed above; the defaults below are replaced after reading them.
        for (down, up) in [(1, 6), (1, 2)] {
            for (label, c) in [("explicit context", ctx), ("no context", UInt32(0))] {
                let before = lastEvent(); let fb = frontSummary()
                let r = PBHelper.postTap(at: center, contextId: c, pid: pid, displayId: 1, down: Int32(down), up: Int32(up))
                sleep(2)
                say("P | types \(down)/\(up) | \(label) ctx=\(c) | \(r) | handler: \(lastEvent() == before ? "none" : lastEvent()) | front before: \(fb) | after: \(frontSummary())")
            }
        }
    }

    // L: the assistive-client route (AXElement press / simulateTap), fixture foreground then background.
    func frontSummary() -> String {
        guard let s = try? settings.snapshot() else { return "settings read failed" }
        var n = 0, labels: [String] = []
        func w(_ e: XCUIElementSnapshot) { n += 1; if labels.count < 4, !e.label.isEmpty { labels.append(e.label) }; e.children.forEach(w) }
        w(s); return "settings elements=\(n) nav=\(find(s) { $0.elementType == .navigationBar }?.identifier ?? "nil") first=\(labels)"
    }
    func routeTest(_ bg: Bool) {
        start(background: bg)
        func byLabel(_ l: String, _ types: [XCUIElement.ElementType]) -> XCUIElementSnapshot? { find(snap()) { $0.label == l && types.contains($0.elementType) } }
        let targets: [(String, () -> XCUIElementSnapshot?)] = [
            ("UIButton", { byLabel("Plain button", [.button]) }), ("UISwitch", { byLabel("Switch", [.switch]) }),
            ("Table cell", { self.find(self.snap()) { $0.elementType == .cell && $0.label.hasPrefix("Row ") } }), ("Tab 'Second'", { byLabel("Second", [.button]) })]
        for (name, locate) in targets {
            for route in ["press", "tap"] {
                let before = lastEvent(); let fb = bg ? frontSummary() : "-"
                let shot1 = XCUIScreen.main.screenshot().pngRepresentation.count
                let r = locate().map { PBHelper.axElementRoute(route, onSnapshot: $0) } ?? "not found"
                sleep(2)
                let after = lastEvent(); let fa = bg ? frontSummary() : "-"
                let shot2 = XCUIScreen.main.screenshot().pngRepresentation.count
                say("L | \(name) | \(route) | \(r) | handler: \(after == before ? "none" : after) | front before: \(fb) | after: \(fa) | screen bytes \(shot1)->\(shot2) | fixture=\(fixture.state.rawValue)")
                if name == "Tab 'Second'" && after != before, let back = byLabel("Controls", [.button]) { _ = PBHelper.axElementRoute("tap", onSnapshot: back); sleep(2) }
            }
        }
    }
    func testL_foreground() { routeTest(false) }
    func testL_background() { routeTest(true) }

    // For the lldb trace: attach to an already running fixture (no launch), press three elements.
    func testPressForTrace() {
        background = false
        fixture.activate()
        sleep(20)  // time for lldb to attach
        func byLabel(_ l: String, _ types: [XCUIElement.ElementType]) -> XCUIElementSnapshot? { find(snap()) { $0.label == l && types.contains($0.elementType) } }
        say("TRACE press UIButton: \(act(byLabel("Plain button", [.button]), 2010).prefix(80))")
        sleep(2)
        say("TRACE press ProbeTarget: \(act(find(snap()) { $0.identifier == "probeTarget" }, 2010).prefix(80))")
        sleep(2)
        say("TRACE press UISwitch: \(act(byLabel("Switch", [.switch]), 2010).prefix(80))")
        sleep(5)
    }

    func testBackground() { start(background: true); controls() }
    func testBackgroundMap() { start(background: true); mapActions() }
    func testForeground() { start(background: false); controls() }
}
