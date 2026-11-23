import XCTest

extension SimFixtureTests {
    func daemonCustom(_ name: String, _ e: XCUIElementSnapshot?, _ want: String) {
        guard let e else { say("DR | \(name) | not found"); return }
        var err: NSString?
        let r = PBHelper.daemonAttributes(["XC_kAXXCAttributeCustomActions"], onSnapshot: e, error: &err)
        let dict = r as? [String: Any]; let list = dict?.values.first as? [Any] ?? []
        let names = list.map { (($0 as? [String: Any])?["CustomActionName"] as? String) ?? "?" }
        say("DR | \(name) | daemon fetch customActions err '\(err ?? "")' keys \(dict.map { Array($0.keys) } ?? []) | names \(names)")
        guard let a = list.first(where: { (($0 as? [String: Any])?["CustomActionName"] as? String) == want }) else { return }
        for (form, v) in [("dict", a as AnyObject), ("name", want as NSString as AnyObject)] {
            let before = lastEvent(); var e2: NSString?
            let ok = PBHelper.pressSnapshot(e, action: 2021, value: v, error: &e2); usleep(1_000_000)
            say("DR | \(name) | 2021 via testmanagerd value=\(form) → \(ok) err '\(String(describing: e2 ?? "").prefix(80))' | before \(before) after \(lastEvent())")
            if lastEvent() != before { break }
        }
    }
    func dAct(_ name: String, _ e: XCUIElementSnapshot?, _ id: Int) {
        guard let e else { say("DR | \(name) | not found"); return }
        let before = lastEvent(); var err: NSString?
        let ok = PBHelper.pressSnapshot(e, action: id, value: nil, error: &err); usleep(1_000_000)
        say("DR | \(name) | \(id) via testmanagerd → \(ok) | before \(before) after \(lastEvent())")
    }
    func testDAEMONROUTE() {
        covLaunch(tab: "Lists", bg: true)
        let rows = find(snap(), { $0.identifier == "cov.table" })?.children.filter { $0.elementType == .cell } ?? []
        daemonCustom("table row 0 swipe", rows.first, "Flag")
        daemonCustom("table row 1 detail", rows.count > 1 ? rows[1] : nil, "More Info")
        let cells = find(snap(), { $0.identifier == "cov.collection" })?.children.filter { $0.elementType == .cell } ?? []
        daemonCustom("list cell 1 detail", cells.count > 1 ? cells[1] : nil, "More Info")
        fixture.terminate()
        covLaunch(tab: "UIKit", bg: true)
        dAct("stepper inc", find(snap()) { $0.identifier == "cov.stepper" }, 2004)
        dAct("page control inc", find(snap()) { $0.identifier == "cov.page" }, 2004)
        var err: NSString?
        let f = find(snap()) { $0.identifier == "cov.field" }
        say("DR | field set value via testmanagerd \(f.map { PBHelper.setAttribute("XC_kAXXCAttributeValue", value: "hi tmd", onSnapshot: $0, error: &err) } ?? false) err '\(err ?? "")' | value now \(String(describing: find(snap()) { $0.identifier == "cov.field" }?.value ?? "nil"))")
        fixture.terminate()
        covLaunch(tab: "SwiftUI", bg: true)
        dAct("SUIButton", find(snap()) { $0.identifier == "sui.button" }, 2010)
        dAct("SUIToggle", find(snap()) { $0.identifier == "sui.toggle" }, 2010)
        dAct("SUISegment P2", find(find(snap()) { $0.identifier == "sui.segment" }) { $0.label == "P2" }, 2010)
        dAct("SUISlider inc", find(snap()) { $0.identifier == "sui.slider" }, 2004)
        say("DR | front \(String(frontSummary().prefix(25)))")
        fixture.terminate()
    }
}
