import XCTest

extension SimFixtureTests {
    func testWEBFORM() {
        covLaunch(tab: "Web", bg: false)
        _ = fixture.buttons["WebButton"].waitForExistence(timeout: 20)
        guard let bs = find(snap(), { $0.label == "WebButton" }), let b = PBHelper.axRef(bs) as AnyObject? else { say("WFM | no button"); return }
        var root: AnyObject = b
        for _ in 0..<40 { var e: Int32 = 0; guard let p = PBHelper.axCopy(root, attr: 5002, err: &e) as AnyObject?, CFGetTypeID(p) == CFGetTypeID(b) else { break }; root = p }
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        background = true; _ = PBHelper.requestBackgroundAssertion(forPID: pid)
        settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(3)
        func val(_ e: AnyObject) -> String { var x: Int32 = 0; return String(describing: PBHelper.axCopy(e, attr: 2006, err: &x) ?? "nil(\(x))") }
        if let inp = axFind(root, "WebInput") {
            let f = PBHelper.axPerform(inp, action: 2010); usleep(600_000)
            let s = PBHelper.axSet(inp, attr: 2006, value: "hello web" as NSString); usleep(800_000)
            say("WFM | input: 2010 \(f), set 2006 \(s) | value \(val(inp)) | last \(lastEvent())")
            for ch in ["a", "b", "c"] { _ = sendKey(ch) }; usleep(800_000)
            say("WFM | input after keys a,b,c via 2034 | value \(val(inp)) | last \(lastEvent())")
        } else { say("WFM | WebInput not found") }
        if let sub = axFind(root, "WebSubmit") { let r = PBHelper.axPerform(sub, action: 2010); usleep(1_000_000); say("WFM | WebSubmit 2010 \(r) | last \(lastEvent())") }
        if let sel = axFind(root, "WebSelect") {
            let s = PBHelper.axSet(sel, attr: 2006, value: "S1" as NSString); usleep(800_000)
            say("WFM | select set 2006 S1 \(s) | value \(val(sel)) | last \(lastEvent())")
            let r = PBHelper.axPerform(sel, action: 2010); usleep(1_000_000)
            say("WFM | select 2010 \(r) | value \(val(sel)) | last \(lastEvent()) | S1 option present \(axFind(root, "S1") != nil)")
            if let o = axFind(root, "S1") { let r2 = PBHelper.axPerform(o, action: 2010); usleep(1_000_000); say("WFM | option S1 2010 \(r2) | select value \(val(sel)) | last \(lastEvent())") }
        } else { say("WFM | WebSelect not found") }
        if let end = axFind(root, "end") { let r = PBHelper.axPerform(end, action: 2003); usleep(1_500_000); say("WFM | scrollToVisible 2003 on 'end' \(r) | last \(lastEvent())") } else { say("WFM | 'end' not found") }
        if let l = axFind(root, "Page2Link") {
            let r = PBHelper.axPerform(l, action: 2010); sleep(3)
            var labels: [String] = []; let n = axCount(root, 0, &labels)
            say("WFM | Page2Link 2010 \(r) | last \(lastEvent()) | old root count \(n) labels \(labels.prefix(5)) | Page2Button via old root \(axFind(root, "Page2Button") != nil)")
        } else { say("WFM | Page2Link not found") }
        say("WFM | front \(String(frontSummary().prefix(25)))")
        fixture.terminate()
    }
    func menuCase(_ bg: Bool) {
        covLaunch(tab: "SwiftUI", bg: bg)
        let r = act(find(snap()) { $0.identifier == "sui.menu" }, 2010); usleep(800_000); if bg { _ = kickNow(); usleep(500_000) }
        let items = labels(snap()) { $0.label.hasSuffix(" item") }
        say("WFM | menu \(bg ? "bg" : "fg") | open 2010 \(r.prefix(20)) | items \(items)")
        let k = sendKey("b"); usleep(800_000)
        let sel = labels(snap()) { $0.label.hasSuffix(" item") && ($0.isSelected || $0.hasFocus) }
        say("WFM | menu \(bg ? "bg" : "fg") | key b \(k) | selected/focused \(sel) | last \(lastEvent())")
        let ret = sendKey("\r"); usleep(1_000_000); if bg { _ = kickNow(); usleep(500_000) }
        say("WFM | menu \(bg ? "bg" : "fg") | Return \(ret) | last \(lastEvent()) | items now \(labels(snap()) { $0.label.hasSuffix(" item") })")
        fixture.terminate()
    }
    func testMENUTYPE() { menuCase(false); menuCase(true) }
}
