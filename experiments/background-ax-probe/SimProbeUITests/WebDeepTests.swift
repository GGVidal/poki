import XCTest

extension SimFixtureTests {
    func axKids(_ r: AnyObject) -> [AnyObject] { var e: Int32 = 0; return (PBHelper.axCopy(r, attr: 5001, err: &e) as? [AnyObject]) ?? [] }
    func axFind(_ r: AnyObject, _ label: String, _ depth: Int = 0) -> AnyObject? {
        if PBHelper.axLabel(r) == label { return r }; if depth > 30 { return nil }
        for k in axKids(r) { if let f = axFind(k, label, depth + 1) { return f } }; return nil
    }
    func axCount(_ r: AnyObject, _ depth: Int = 0, _ labels: inout [String]) -> Int {
        let l = PBHelper.axLabel(r); if !l.hasPrefix("(err") && !l.isEmpty && labels.count < 14 { labels.append(l) }
        if depth > 30 { return 1 }; return 1 + axKids(r).reduce(0) { $0 + axCount($1, depth + 1, &labels) }
    }
    func testWEBDEEP() {
        covLaunch(tab: "Web", bg: false)
        _ = fixture.buttons["WebButton"].waitForExistence(timeout: 20)
        guard let bs = find(snap(), { $0.label == "WebButton" }), let b = PBHelper.axRef(bs) as AnyObject? else { say("WD | no button"); return }
        // walk up to the top of the web process tree
        var root: AnyObject = b; var up = 0
        while up < 40 { var e: Int32 = 0; guard let p = PBHelper.axCopy(root, attr: 5002, err: &e) as AnyObject?, CFGetTypeID(p) == CFGetTypeID(b) else { break }; root = p; up += 1 }
        var l0: [String] = []; say("WD | fg root up \(up) label '\(PBHelper.axLabel(root))' count \(axCount(root, 0, &l0)) labels \(l0)")
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        say("WD | ready")
        var wpids: [Int32] = []
        for _ in 0..<60 { if let t = try? String(contentsOfFile: "/tmp/bgax/webpids.txt", encoding: .utf8), t.contains("END") { wpids = t.split(whereSeparator: { !$0.isNumber }).compactMap { Int32($0) }; break }; usleep(500_000) }
        background = true; _ = PBHelper.requestBackgroundAssertion(forPID: pid); for p in wpids { _ = PBHelper.requestBackgroundAssertion(forPID: p) }
        settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(3)
        var l1: [String] = []; say("WD | bg root count \(axCount(root, 0, &l1)) labels \(l1)")
        func press(_ name: String, _ label: String) {
            guard let e = axFind(root, label) else { say("WD | \(name) not found from root"); return }
            let before = lastEvent(); let r = PBHelper.axPerform(e, action: 2010); usleep(1_200_000)
            say("WD | \(name) 2010 \(r) | before \(before) after \(lastEvent()) | label now \(PBHelper.axLabel(e))")
        }
        press("WebButton", "WebButton")
        press("WebCheck", "WebCheck")
        if let inp = axFind(root, "WebInput") { let r = PBHelper.axSet(inp, attr: 2006, value: "hello web" as NSString); usleep(800_000); var e: Int32 = 0; say("WD | WebInput set 2006 \(r) | value now \(String(describing: PBHelper.axCopy(inp, attr: 2006, err: &e))) | last \(lastEvent())") } else { say("WD | WebInput not found") }
        press("AddButton", "AddButton"); sleep(1)
        press("NewButton (created after capture)", "NewButton")
        // testmanagerd routes on the cached element (B2)
        var err: NSString?
        say("WD | tmd setAttribute value on WebInput \(PBHelper.setAttribute("XC_kAXXCAttributeValue", value: "via tmd", onSnapshot: bs, error: &err)) \(String(describing: err ?? "").prefix(80))")
        say("WD | tmd 95003 on WebButton \(PBHelper.daemonParamAttribute(95003, onSnapshot: bs, parameter: NSValue(range: NSRange(location: 0, length: 5))).prefix(90))")
        say("WD | after 60 s wait..."); sleep(60)
        press("WebButton +60s", "WebButton clicked 1")
        press("Page2Link", "Page2Link"); sleep(2)
        var l2: [String] = []; say("WD | after link: root count \(axCount(root, 0, &l2)) labels \(l2.prefix(6)) | root label '\(PBHelper.axLabel(root))'")
        say("WD | front \(String(frontSummary().prefix(25)))")
        fixture.activate(); sleep(2); say("WD | end fg: \(labels(snap()) { $0.label.hasPrefix("Web") || $0.label.hasPrefix("New") || $0.label.hasPrefix("Page2") })")
        fixture.terminate()
    }
}
