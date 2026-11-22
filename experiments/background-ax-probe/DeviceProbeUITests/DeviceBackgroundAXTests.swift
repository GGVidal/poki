import XCTest

// On-device probe: keep the original Calculator running in the background through
// testmanagerd's background assertion, then read it and press "7" by accessibility element
// (never by coordinate) while Settings stays frontmost. A = with assertion, B = control.
final class DeviceBackgroundAXTests: XCTestCase {
    let target = XCUIApplication(bundleIdentifier: "com.apple.calculator")
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    func say(_ s: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; f.timeZone = TimeZone(identifier: "America/New_York")
        print("PROBE \(f.string(from: Date())) \(s)")
    }
    func front() -> String { "settings=\(settings.state.rawValue) calculator=\(target.state.rawValue)" }

    func walk(_ s: NSObject, _ visit: (NSObject) -> Void) {
        visit(s)
        for c in ((try? s.value(forKey: "children")) as? [NSObject]) ?? [] { walk(c, visit) }
    }
    func str(_ e: NSObject, _ k: String) -> String { (e.value(forKey: k) as? String) ?? "" }
    func count(_ r: NSObject) -> Int { var n = 0; walk(r) { _ in n += 1 }; return n }
    func key(_ r: NSObject, _ label: String) -> NSObject? { var h: NSObject?; walk(r) { e in if h == nil, str(e, "label") == label { h = e } }; return h }
    // The result display: non-button elements that carry a label or value.
    func display(_ r: NSObject) -> String {
        var out: [String] = []
        walk(r) { e in
            let t = (e.value(forKey: "elementType") as? NSNumber)?.intValue ?? 0
            if t != 9 { let l = str(e, "label"), v = (e.value(forKey: "value") as? String) ?? ""; if !l.isEmpty || !v.isEmpty { out.append("\(l)|\(v)") } }
        }
        return out.joined(separator: ", ")
    }

    func run(assert: Bool) {
        let tag = assert ? "A" : "B"
        target.launch()
        let pid = (target.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        settings.activate()
        _ = settings.wait(for: .runningForeground, timeout: 10)
        say("[\(tag)] calculator pid=\(pid); \(front())")
        if assert { say("[\(tag)] background assertion granted=\(String(describing: PBHelper.requestBackgroundAssertion(forPID: pid)))") }
        let marks = assert ? [2, 15, 40, 120, 300] : [2, 15, 40]
        var t = 0
        for m in marks {
            sleep(UInt32(m - t)); t = m
            var status: NSString?
            guard let root = PBHelper.snapshot(forPID: pid, timeout: 8, status: &status) as? NSObject else {
                say("[\(tag)] t+\(m)s snapshot \(status ?? "nil"); \(front())"); continue
            }
            var line = "t+\(m)s snapshot ok elements=\(count(root)) display=[\(display(root))]"
            if let seven = key(root, "7") {
                var err: NSString?
                let ok = PBHelper.pressSnapshot(seven, action: 2010, error: &err)
                usleep(700_000)
                var s2: NSString?
                let after = (PBHelper.snapshot(forPID: pid, timeout: 8, status: &s2) as? NSObject).map(display) ?? "snapshot \(s2 ?? "nil")"
                line += " | AXPress(7) ok=\(ok) err=\(err ?? "nil") display_after=[\(after)]"
            } else { line += " | key 7 not found" }
            say("[\(tag)] \(line) | \(front())")
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.lifetime = .keepAlways; add(shot)
        say("[\(tag)] end: \(front())")
        target.activate(); sleep(1)
        let labels = (try? target.snapshot()).map { s -> String in var o: [String] = []; func w(_ e: XCUIElementSnapshot) { if e.elementType == .staticText { o.append(e.label) }; e.children.forEach(w) }; w(s); return o.joined(separator: ",") } ?? "nil"
        say("[\(tag)] verification (foreground, one-off): static texts=[\(labels)]")
    }

    func testA_withAssertion() { run(assert: true) }
    func testB_controlWithoutAssertion() { run(assert: false) }
}
