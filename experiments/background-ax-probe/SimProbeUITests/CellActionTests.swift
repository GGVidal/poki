import XCTest

extension SimFixtureTests {
    func testCELLACTIONS() {
        covLaunch(tab: "Lists", bg: true)
        var cells: [XCUIElementSnapshot] = []; func w(_ e: XCUIElementSnapshot) { if e.elementType == .cell { cells.append(e) }; e.children.forEach(w) }; if let s = snap() { w(s) }
        say("CELL | cells \(cells.map { $0.label })")
        for c in cells {
            guard let r = PBHelper.axRef(c) as AnyObject? else { continue }
            var e: Int32 = 0
            let ca = PBHelper.axCopy(r, attr: 2036, err: &e)
            let names: [String] = (ca as? [Any])?.compactMap { a -> String? in if let d = a as? [String: Any] { return (d["CustomActionName"] ?? d["name"] ?? d.description) as? String ?? "\(d)" }; return "\(a)" } ?? []
            say("CELL | '\(c.label)' | 2036 err \(e) | \(names.count) actions \(names.map { String($0.prefix(40)) })")
            for a in (ca as? [Any]) ?? [] {
                let before = lastEvent()
                let ok = PBHelper.axPerformValue(r, action: 2021, value: a as AnyObject); usleep(1_000_000)
                say("CELL | '\(c.label)' | 2021 with item \(String(describing: a).replacingOccurrences(of: "\n", with: " ").prefix(70)) → \(ok) | before \(before) after \(lastEvent())")
            }
        }
        if let sw = cells.first(where: { $0.label.hasPrefix("TableCell 0") }), let r = PBHelper.axRef(sw) as AnyObject? {
            let before = lastEvent(); let ok = PBHelper.axPerform(r, action: 2010); usleep(1_000_000)
            say("CELL | switch-accessory cell 2010 \(ok) | before \(before) after \(lastEvent())")
        }
        say("CELL | front \(String(frontSummary().prefix(25)))")
        fixture.terminate()
    }
}
