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

    func frontName() -> String {
        let apps: [(String, String)] = [("com.apple.Preferences", "Settings"), ("com.apple.mobilenotes", "Notes"), ("com.apple.calculator", "Calculator")]
        return apps.map { "\($0.1)=\(XCUIApplication(bundleIdentifier: $0.0).state.rawValue)" }.joined(separator: " ")
    }
    func calcDisplay(_ s: XCUIElementSnapshot) -> String {
        var v = ""
        func w(_ e: XCUIElementSnapshot) { if v.isEmpty, e.elementType == .textField || e.elementType == .staticText, e.label == "Edit field" { v = (e.value as? String) ?? "" }; e.children.forEach(w) }
        w(s); return v
    }

    // F: concurrency. The owner uses the handset (Settings, Notes) for 5 minutes while the probe
    // presses one digit every 10 s in the background Calculator and checks the display each time.
    func testF_concurrentUse() {
        target.launch()
        let pid = (target.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        if let s0 = try? target.snapshot(), let ac = publicKey(s0, "All Clear") ?? publicKey(s0, "Clear") { _ = PBHelper.pressSnapshot(ac, action: 2010, error: nil) }
        say("[F] assertion granted=\(String(describing: PBHelper.requestBackgroundAssertion(forPID: pid)))")
        settings.activate()
        _ = settings.wait(for: .runningForeground, timeout: 10)
        say("[F] START: owner may now use the phone (Settings / Notes). \(frontName())")
        var expected = ""
        var pass = 0, fail = 0
        let start = Date()
        var i = 0
        while Date().timeIntervalSince(start) < 300 {
            i += 1
            let digit = String((i % 9) + 1)
            let t0 = Date()
            guard let snap = try? target.snapshot(), let k = publicKey(snap, digit) else { fail += 1; say("[F] #\(i) snapshot/key failed | \(frontName())"); sleep(10); continue }
            var err: NSString?
            let ok = PBHelper.pressSnapshot(k, action: 2010, error: &err)
            usleep(500_000)
            let shown = (try? target.snapshot()).map(calcDisplay) ?? "nil"
            if ok { expected += digit }
            if expected.count > 9 { // keep the number short: clear and restart
                if let s2 = try? target.snapshot(), let c = publicKey(s2, "Clear") ?? publicKey(s2, "All Clear") { _ = PBHelper.pressSnapshot(c, action: 2010, error: nil) }
                expected = ""
            }
            let match = shown.replacingOccurrences(of: ",", with: "") == expected || (expected.isEmpty)
            if ok && (shown.replacingOccurrences(of: ",", with: "").hasSuffix(digit)) { pass += 1 } else { fail += 1 }
            say("[F] #\(i) +\(Int(Date().timeIntervalSince(start)))s press \(digit) ok=\(ok) err=\(err ?? "nil") display=\(shown) expected=\(expected) match=\(match) in \(Int(Date().timeIntervalSince(t0)*1000)) ms | \(frontName())")
            sleep(10)
        }
        say("[F] END: presses verified=\(pass) failed=\(fail) | \(frontName())")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.lifetime = .keepAlways; add(shot)
    }

    // G: generality, each its own test. Target Settings in the background, Notes in front.
    func testGa_navigationInBackgroundSettings() {
        let notes = XCUIApplication(bundleIdentifier: "com.apple.mobilenotes")
        settings.launch()
        let pid = (settings.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        say("[Ga] assertion granted=\(String(describing: PBHelper.requestBackgroundAssertion(forPID: pid)))")
        notes.activate(); _ = notes.wait(for: .runningForeground, timeout: 10)
        func labels(_ s: XCUIElementSnapshot) -> [String] { var o: [String] = []; func w(_ e: XCUIElementSnapshot) { if !e.label.isEmpty { o.append(e.label) }; e.children.forEach(w) }; w(s); return o }
        func cell(_ s: XCUIElementSnapshot, _ label: String) -> XCUIElementSnapshot? {
            if (s.elementType == .cell || s.elementType == .button || s.elementType == .staticText) && s.label == label { return s }
            for c in s.children { if let h = cell(c, label) { return h } }; return nil
        }
        for step in ["General", "About"] {
            guard let snap = try? settings.snapshot() else { say("[Ga] snapshot failed"); return }
            guard let c = cell(snap, step) else { say("[Ga] '\(step)' not found; visible: \(labels(snap).prefix(25))"); return }
            var err: NSString?
            let ok = PBHelper.pressSnapshot(c, action: 2010, error: &err)
            sleep(2)
            let after = (try? settings.snapshot()).map { labels($0).prefix(20).joined(separator: " / ") } ?? "nil"
            say("[Ga] press '\(step)' ok=\(ok) err=\(err ?? "nil") -> \(after) | \(frontName())")
        }
    }

    func testGb_textEntryInBackgroundSettings() {
        let notes = XCUIApplication(bundleIdentifier: "com.apple.mobilenotes")
        settings.launch()
        let pid = (settings.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        say("[Gb] assertion granted=\(String(describing: PBHelper.requestBackgroundAssertion(forPID: pid)))")
        notes.activate(); _ = notes.wait(for: .runningForeground, timeout: 10)
        func field(_ s: XCUIElementSnapshot) -> XCUIElementSnapshot? {
            if s.elementType == .searchField || s.elementType == .textField { return s }
            for c in s.children { if let h = field(c) { return h } }; return nil
        }
        guard let snap = try? settings.snapshot(), let f = field(snap) else { say("[Gb] no text field in background Settings"); return }
        for name in ["AXValue", "XC_kAXXCAttributeValue", "2006", "AXValueAttribute"] {
            var err: NSString?
            let ok = PBHelper.setAttribute(name, value: "wifi" as NSString, onSnapshot: f, error: &err)
            sleep(1)
            let v = (try? settings.snapshot()).flatMap { field($0)?.value as? String } ?? "nil"
            say("[Gb] setAttribute(\(name)) ok=\(ok) err=\(err ?? "nil") field value now=\(v) | \(frontName())")
        }
    }

    func testGc_scrollInBackgroundSettings() {
        let notes = XCUIApplication(bundleIdentifier: "com.apple.mobilenotes")
        settings.launch()
        let pid = (settings.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        say("[Gc] assertion granted=\(String(describing: PBHelper.requestBackgroundAssertion(forPID: pid)))")
        notes.activate(); _ = notes.wait(for: .runningForeground, timeout: 10)
        func labels(_ s: XCUIElementSnapshot) -> [String] { var o: [String] = []; func w(_ e: XCUIElementSnapshot) { if e.elementType == .cell || e.elementType == .staticText, !e.label.isEmpty { o.append(e.label) }; e.children.forEach(w) }; w(s); return o }
        func scrollable(_ s: XCUIElementSnapshot) -> XCUIElementSnapshot? {
            if s.elementType == .table || s.elementType == .collectionView || s.elementType == .scrollView { return s }
            for c in s.children { if let h = scrollable(c) { return h } }; return nil
        }
        guard let snap = try? settings.snapshot(), let list = scrollable(snap) else { say("[Gc] no scrollable list"); return }
        say("[Gc] before: \(labels(snap).count) labels, last=\(labels(snap).suffix(3))")
        // AXRuntime scroll actions (hypothesis numbering): 2007 scroll-to-visible, 2008/2009 increment/decrement, 2018-2021 page scroll.
        for action in [2018, 2019, 2020, 2021, 2008] {
            var err: NSString?
            let ok = PBHelper.pressSnapshot(list, action: action, error: &err)
            usleep(800_000)
            let a = (try? settings.snapshot()).map(labels) ?? []
            say("[Gc] action \(action) ok=\(ok) err=\(err ?? "nil") labels=\(a.count) last=\(a.suffix(3)) | \(frontName())")
        }
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
