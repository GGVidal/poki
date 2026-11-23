import XCTest

extension SimFixtureTests {
    func customActs(_ name: String, _ r: AnyObject) {
        var e: Int32 = 0; let ca = PBHelper.axCopy(r, attr: 2036, err: &e) as? [Any] ?? []
        let names = ca.map { a -> String in ((a as? [String: Any])?["CustomActionName"] as? String) ?? String(describing: a).prefix(30).description }
        say("MS | \(name) | 2036 err \(e) | \(names)")
        for a in ca { let before = lastEvent(); let ok = PBHelper.axPerformValue(r, action: 2021, value: a as AnyObject); usleep(900_000); say("MS | \(name) | 2021 '\(((a as? [String: Any])?["CustomActionName"] as? String) ?? "?")' → \(ok) | before \(before) after \(lastEvent())") }
    }
    func tryIds(_ name: String, _ r: AnyObject, _ ids: [Int]) {
        for id in ids { let before = lastEvent(); let ok = PBHelper.axPerform(r, action: id); usleep(900_000); say("MS | \(name) | \(id) → \(ok) | before \(before) after \(lastEvent())") }
    }
    func testMENUSWITCH() {
        covLaunch(tab: "Lists", bg: true)
        guard let tv = find(snap(), { $0.identifier == "cov.table" }) else { say("MS | no table"); return }
        let rows = tv.children.filter { $0.elementType == .cell }
        say("MS | table rows \(rows.count)")
        if let r0 = rows.first, let ref = PBHelper.axRef(r0) as AnyObject? {
            tryIds("row0 cell", ref, [2010, 2004, 2005]); customActs("row0 cell", ref)
            if let sw = find(r0, { $0.elementType == .switch }), let sref = PBHelper.axRef(sw) as AnyObject? { tryIds("row0 switch", sref, [2010, 2004, 2005]); customActs("row0 switch", sref) } else { say("MS | row0 switch element not found") }
        }
        if rows.count > 2, let ref = PBHelper.axRef(rows[2]) as AnyObject? { customActs("row2 cell (context menu)", ref) }
        if let cv = find(snap(), { $0.identifier == "cov.collection" }), let c2 = cv.children.filter({ $0.elementType == .cell }).dropFirst(2).first, let ref = PBHelper.axRef(c2) as AnyObject? {
            tryIds("list cell 2", ref, [2010]); customActs("list cell 2", ref)
            if let sw = find(c2, { $0.elementType == .switch }), let sref = PBHelper.axRef(sw) as AnyObject? { tryIds("list cell 2 switch", sref, [2010, 2004]) } else { say("MS | list cell 2 switch element not found") }
        }
        fixture.terminate()
        covLaunch(tab: "UIKit", bg: true)
        for id in ["cov.menu", "cov.barmenu"] { if let e = find(snap(), { $0.identifier == id }), let ref = PBHelper.axRef(e) as AnyObject? { customActs(id, ref) } else { say("MS | \(id) not found") } }
        if let bm = find(snap(), { $0.identifier == "cov.barmenu" }), let ref = PBHelper.axRef(bm) as AnyObject? {
            tryIds("BarMenu", ref, [2010]); _ = kickNow(); usleep(800_000)
            let items = labels(snap()) { $0.label.hasPrefix("BarMenu ") }
            say("MS | BarMenu items in tree after 2010 \(items)")
            if let two = find(snap(), { $0.label == "BarMenu Two" }), let tr = PBHelper.axRef(two) as AnyObject? { tryIds("BarMenu Two", tr, [2010]) }
        }
        say("MS | front \(String(frontSummary().prefix(25)))")
        fixture.terminate()
    }
}
