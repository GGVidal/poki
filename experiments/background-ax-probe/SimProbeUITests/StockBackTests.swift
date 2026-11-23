import XCTest

extension SimFixtureTests {
    func navInfo(_ s: XCUIElementSnapshot?) -> String {
        guard let s else { return "no snap" }
        var bars: [String] = []; var back = "-"
        func w(_ e: XCUIElementSnapshot) {
            if e.elementType == .navigationBar {
                bars.append(e.identifier)
                if back == "-", let b = e.children.first(where: { $0.elementType == .button }) { back = b.label }
            }
            e.children.forEach(w)
        }
        w(s); return "bars \(bars) back \"\(back)\""
    }
    func stockCase(_ bid: String) {
        let app = XCUIApplication(bundleIdentifier: bid)
        app.launch(); sleep(3)
        let rootInfo = navInfo(try? app.snapshot())
        let targets: [String: [String]] = ["com.apple.MobileAddressBook": ["Kate Bell", "John Appleseed", "Anna Haro"], "com.apple.DocumentsApp": ["On My iPhone", "Recently Deleted"], "com.apple.reminders": ["Reminders", "Today", "Scheduled", "All"]]
        var tapped = "none"
        for t in targets[bid] ?? [] { let e = app.staticTexts[t].firstMatch; if e.waitForExistence(timeout: 2) && e.isHittable { e.tap(); tapped = t; break } }
        if tapped == "none" { let cell = app.cells.firstMatch; if cell.waitForExistence(timeout: 3) { cell.tap(); tapped = "first cell" } }
        if tapped == "none" {
            let labels = ((try? app.snapshot()).map { s -> [String] in var o: [String] = []; func w(_ e: XCUIElementSnapshot) { if !e.label.isEmpty { o.append(e.label) }; e.children.forEach(w) }; w(s); return o } ?? []).prefix(12)
            say("STOCK | \(bid) | no row to tap | root \(rootInfo) | labels \(Array(labels))"); app.terminate(); return }
        sleep(2)
        let before = navInfo(try? app.snapshot())
        if before == rootInfo { say("STOCK | \(bid) | tap did not push (\(tapped)) | \(before)"); app.terminate(); return }
        let pid = (app.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        _ = PBHelper.requestBackgroundAssertion(forPID: pid)
        settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(1)
        let bgSnap = try? app.snapshot()
        let stillDetail = navInfo(bgSnap)
        guard let bar = find(bgSnap, { $0.elementType == .navigationBar }) else { say("STOCK | \(bid) | no nav bar in background snapshot | \(stillDetail)"); app.terminate(); return }
        var err: NSString?
        let r = PBHelper.pressSnapshot(bar, action: 2013, value: nil, error: &err) ? "ok" : "fail(\(String(describing: err).prefix(60)))"
        sleep(2); let t2 = navInfo(try? app.snapshot())
        var dres = "no snap"; var dt = 0.0
        if let a = try? app.snapshot() {
            let t0 = Date()
            dres = PBHelper.daemonParamAttribute(95005, onSnapshot: a, parameter: ["AXAuditClippingTest": ["AXAuditShouldRunTestOption": true]] as NSDictionary)
            dt = Date().timeIntervalSince(t0)
        }
        sleep(1); let a1 = navInfo(try? app.snapshot()); sleep(4); let a5 = navInfo(try? app.snapshot())
        say("STOCK | \(bid) | tapped \(tapped) | before \(before) | bg \(stillDetail) | 2013 \(r) | +2s \(t2) | daemon \(String(format: "%.2f", dt)) s \(dres.prefix(110)) | +1s \(a1) | +5s \(a5) | front \(String(frontSummary().prefix(30))) | state \(app.state.rawValue)")
        app.terminate()
    }
    func testBACK_stock() {
        background = true
        for b in ["com.apple.MobileAddressBook", "com.apple.reminders", "com.apple.DocumentsApp"] { stockCase(b) }
    }

    func testWEB_background() {
        covLaunch(tab: "Web", bg: false); sleep(3)
        let fpid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        let appeared = fixture.buttons["WebButton"].waitForExistence(timeout: 20)
        var tree: [String] = []; if let r = snap() { func w(_ e: XCUIElementSnapshot) { if e.elementType == .webView || !e.label.isEmpty && e.label.hasPrefix("Web") { tree.append("\(e.elementType.rawValue):\(e.label)") }; e.children.forEach(w) }; w(r) }
        say("WEB | fg wait WebButton \(appeared) | web-ish elements \(tree.prefix(12))")
        let fs = snap(); let fb = find(fs) { $0.label == "WebButton" }
        say("WEB | fg WebButton \(fb.map { "\($0.frame)" } ?? "absent") | fg 2010 skipped")
        say("WEB | ready fixture pid \(fpid)")
        let path = "/tmp/bgax/webpids.txt"
        var pids: [Int32] = []
        for _ in 0..<60 { if let s = try? String(contentsOfFile: path, encoding: .utf8), s.contains("END") { pids = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int32($0) }; break }; usleep(500_000) }
        say("WEB | webkit pids \(pids)")
        var grants: [String] = ["fixture \(fpid)=\(PBHelper.requestBackgroundAssertion(forPID: fpid).map { "\($0)" } ?? "nil")"]
        for p in pids { grants.append("\(p)=\(PBHelper.requestBackgroundAssertion(forPID: p).map { "\($0)" } ?? "nil")") }
        say("WEB | assertions \(grants)")
        settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(5)
        let s = snap()
        let btn = find(s) { $0.label == "WebButton" }; let link = find(s) { $0.label == "WebLink" }
        say("WEB | bg snap \(s == nil ? "nil" : "ok") | WebButton \(btn.map { "\($0.frame)" } ?? "absent") | WebLink \(link.map { "\($0.frame)" } ?? "absent")")
        let before = lastEvent()
        let r = act(btn, 2010); sleep(2)
        say("WEB | 2010 on WebButton \(r.prefix(90)) | before \(before) | after \(lastEvent()) | front \(String(frontSummary().prefix(30)))")
        fixture.terminate()
    }
}
