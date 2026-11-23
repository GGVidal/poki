import XCTest

// Read-only: no accessibility actions. Phase "bg" reads the app as it is in the background;
// phase "fwd" brings it to the front for a few seconds, returns to Settings, then reads it in the background.
extension SimFixtureTests {
    func testREADAPP() {
        let env = ProcessInfo.processInfo.environment
        let bid = env["PROBE_BUNDLE"] ?? "local.pokimcp.axfixture"
        let phase = env["PROBE_PHASE"] ?? "bg"
        let app = XCUIApplication(bundleIdentifier: bid)
        background = true
        if phase == "fwd" { app.activate(); sleep(5); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(2) }
        let pid = (app.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        if pid > 0 { _ = PBHelper.requestBackgroundAssertion(forPID: pid) }
        var tree: XCUIElementSnapshot? = nil
        for _ in 0..<15 { tree = try? app.snapshot(); if all(tree).count > 5 { break }; sleep(1) }
        let els = all(tree)
        let labeled = els.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        func k(_ t: XCUIElement.ElementType) -> (Int, Int) { let a = els.filter { $0.elementType == t }; return (a.count, a.filter { !$0.label.isEmpty }.count) }
        let b = k(.button), t = k(.staticText), c = k(.cell), f = (k(.textField).0 + k(.searchField).0, k(.textField).1 + k(.searchField).1), im = k(.image)
        say("READ | #\(env["PROBE_INDEX"] ?? "?") \(phase) | state \(app.state.rawValue) front \(settings.state == .runningForeground ? "Settings" : "other") | total \(els.count) labeled \(labeled.count) | buttons \(b.1)/\(b.0) texts \(t.1)/\(t.0) cells \(c.1)/\(c.0) fields \(f.1)/\(f.0) images \(im.1)/\(im.0)")
        var seen = Set<String>(); var outline: [String] = []
        for e in labeled { let l = String(e.label.replacingOccurrences(of: "\n", with: " ").prefix(40)); if seen.insert(l).inserted { outline.append("[\(["button": "B", "staticText": "T", "cell": "C", "image": "I", "textField": "F", "searchField": "F", "link": "L"]["\(e.elementType)"] ?? "\(e.elementType.rawValue)")] \(l)") }; if outline.count >= 30 { break } }
        say("OUTLINE | #\(env["PROBE_INDEX"] ?? "?") \(phase) | " + outline.joined(separator: " · "))
    }
}
