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

    // E: public XCTest snapshot of the background app (fast in D), then AXPress by element.
    func describe(_ s: XCUIElementSnapshot) -> String {
        var out: [String] = []
        func w(_ e: XCUIElementSnapshot) {
            if e.elementType != .button, e.elementType != .other || !(e.label.isEmpty) {
                let v = (e.value as? String) ?? ""
                if !e.label.isEmpty || !v.isEmpty { out.append("\(e.elementType.rawValue):\(e.label)|\(v)") }
            }
            e.children.forEach(w)
        }
        w(s); return out.joined(separator: ", ")
    }
    func publicKey(_ s: XCUIElementSnapshot, _ label: String) -> XCUIElementSnapshot? {
        if (s.elementType == .button || s.elementType == .key) && s.label == label { return s }
        for c in s.children { if let h = publicKey(c, label) { return h } }
        return nil
    }
    func countPublic(_ s: XCUIElementSnapshot) -> Int { 1 + s.children.map(countPublic).reduce(0, +) }

    func testE_publicSnapshotAndPress() {
        target.launch()
        let pid = (target.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        if let fg = try? target.snapshot() { say("[E] foreground: elements=\(countPublic(fg)) [\(describe(fg))] | \(front())") }
        say("[E] assertion granted=\(String(describing: PBHelper.requestBackgroundAssertion(forPID: pid)))")
        settings.activate()
        _ = settings.wait(for: .runningForeground, timeout: 10)
        let start = Date()
        for (i, m) in [1.0, 5, 30, 120].enumerated() {
            let wait = m - Date().timeIntervalSince(start); if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
            let t0 = Date()
            guard let snap = try? target.snapshot() else { say("[E] +\(Int(m))s public snapshot failed | \(front())"); continue }
            var line = "+\(Int(m))s snapshot elements=\(countPublic(snap)) in \(Int(Date().timeIntervalSince(t0)*1000)) ms before=[\(describe(snap))]"
            let digit = ["7", "8", "9", "4"][i]
            if let k = publicKey(snap, digit), let obj = k as AnyObject as? NSObject {
                var err: NSString?
                let ok = PBHelper.pressSnapshot(obj, action: 2010, error: &err)
                usleep(800_000)
                let after = (try? target.snapshot()).map(describe) ?? "nil"
                line += " | AXPress(\(digit)) ok=\(ok) err=\(err ?? "nil") after=[\(after)]"
            } else { line += " | key \(digit) not found" }
            say("[E] \(line) | \(front())")
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.lifetime = .keepAlways; add(shot)
        say("[E] end: \(front())")
        target.activate(); sleep(1)
        if let v = try? target.snapshot() { say("[E] verification (foreground, one-off): [\(describe(v))]") }
    }

    // D: reads on the main thread (helper on caller thread, and XCTest's public snapshot),
    // foreground first as a control, then background with the assertion held.
    func testD_mainThreadReads() {
        target.launch()
        let pid = (target.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        func read(_ tag: String) -> NSObject? {
            var st: NSString?
            let t0 = Date()
            let h = PBHelper.snapshotOnCaller(forPID: pid, status: &st) as? NSObject
            let hm = Int(Date().timeIntervalSince(t0) * 1000)
            let t1 = Date()
            let pub = try? target.snapshot()
            let pm = Int(Date().timeIntervalSince(t1) * 1000)
            var n = 0; if let pub { func w(_ e: XCUIElementSnapshot) { n += 1; e.children.forEach(w) }; w(pub) }
            say("[D] \(tag): helper(main)=\(st ?? "nil") elements=\(h.map(count) ?? -1) in \(hm) ms display=[\(h.map(display) ?? "")] | public snapshot elements=\(pub == nil ? -1 : n) in \(pm) ms | \(front())")
            return h ?? (pub as? NSObject)
        }
        _ = read("foreground")
        say("[D] assertion granted=\(String(describing: PBHelper.requestBackgroundAssertion(forPID: pid)))")
        settings.activate()
        _ = settings.wait(for: .runningForeground, timeout: 10)
        for m: UInt32 in [1, 4, 25] {
            sleep(m)
            guard let root = read("background +\(m)s") else { continue }
            if let seven = key(root, "7") {
                var err: NSString?
                let ok = PBHelper.pressSnapshot(seven, action: 2010, error: &err)
                usleep(700_000)
                var st: NSString?
                let after = (PBHelper.snapshotOnCaller(forPID: pid, status: &st) as? NSObject).map(display) ?? "helper \(st ?? "nil")"
                say("[D] AXPress(7) ok=\(ok) err=\(err ?? "nil") display_after=[\(after)] | \(front())")
            } else { say("[D] key 7 not found in background tree") }
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.lifetime = .keepAlways; add(shot)
        say("[D] end: \(front())")
        target.activate(); sleep(1)
        _ = read("verification (foreground, one-off)")
    }

    // C: assertion taken while Calculator is still frontmost, then Settings to the front.
    func testC_assertionBeforeBackgrounding() {
        target.launch()
        let pid = (target.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        var st: NSString?
        let fg = PBHelper.snapshot(forPID: pid, depth: 40, timeout: 8, status: &st) as? NSObject
        say("[C] foreground read: \(st ?? "nil") elements=\(fg.map(count) ?? -1) display=[\(fg.map(display) ?? "")]")
        let heldSeven = fg.flatMap { key($0, "7") }
        say("[C] assertion (foreground) granted=\(String(describing: PBHelper.requestBackgroundAssertion(forPID: pid)))")
        settings.activate()
        _ = settings.wait(for: .runningForeground, timeout: 10)
        let start = Date()
        for m in [1.0, 5, 30, 120] {
            let wait = m - Date().timeIntervalSince(start); if wait > 0 { usleep(UInt32(wait * 1_000_000)) }
            var s1: NSString?, s2: NSString?
            let shallow = PBHelper.snapshot(forPID: pid, depth: 1, timeout: 4, status: &s1) as? NSObject
            let full = PBHelper.snapshot(forPID: pid, depth: 40, timeout: 8, status: &s2) as? NSObject
            var line = "t+\(Int(m))s shallow=\(s1 ?? "nil")(\(shallow.map(count) ?? -1)) full=\(s2 ?? "nil")(\(full.map(count) ?? -1))"
            if let full, let seven = key(full, "7") {
                var err: NSString?
                let ok = PBHelper.pressSnapshot(seven, action: 2010, error: &err)
                usleep(700_000)
                var s3: NSString?
                let after = (PBHelper.snapshot(forPID: pid, depth: 40, timeout: 8, status: &s3) as? NSObject).map(display) ?? "snapshot \(s3 ?? "nil")"
                line += " before=[\(display(full))] AXPress(7) ok=\(ok) err=\(err ?? "nil") after=[\(after)]"
            }
            if let heldSeven {
                var err: NSString?
                let ok = PBHelper.pressSnapshot(heldSeven, action: 2010, error: &err)
                line += " | held-element AXPress(7) ok=\(ok) err=\(err ?? "nil")"
            }
            say("[C] \(line) | \(front())")
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.lifetime = .keepAlways; add(shot)
        say("[C] end: \(front())")
        target.activate(); sleep(1)
        let labels = (try? target.snapshot()).map { s -> String in var o: [String] = []; func w(_ e: XCUIElementSnapshot) { if e.elementType == .staticText { o.append(e.label) }; e.children.forEach(w) }; w(s); return o.joined(separator: ",") } ?? "nil"
        say("[C] verification (foreground, one-off): static texts=[\(labels)]")
    }
}
