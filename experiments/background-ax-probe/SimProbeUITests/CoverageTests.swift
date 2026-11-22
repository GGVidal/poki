import XCTest

// Coverage table: every control of the fixture's -coverage mode, read and activate in foreground and background.
// Background = Settings in front, fixture kept running by testmanagerd's background assertion.
extension SimFixtureTests {
    struct CovRow { let name: String; let find: (XCUIElementSnapshot) -> Bool; let actions: [String] }
    struct CovGroup { let tab: String; let presenter: String?; let rows: [CovRow] }

    func id(_ s: String) -> (XCUIElementSnapshot) -> Bool { { $0.identifier == s } }
    func lbl(_ s: String, _ t: XCUIElement.ElementType? = nil) -> (XCUIElementSnapshot) -> Bool { { $0.label == s && (t == nil || $0.elementType == t!) } }

    var covGroups: [CovGroup] {
        let tap = ["2010", "2036"]
        let adj = ["2004", "2010"]
        let toggle = ["2010", "fka-right"]
        let text = ["set+2054", "set+key-return"]
        return [
            CovGroup(tab: "UIKit", presenter: nil, rows: [
                CovRow(name: "UIButton Configuration + primaryAction", find: id("cov.configured"), actions: tap + ["fka-space"]),
                CovRow(name: "UIButton addAction(UIAction)", find: id("cov.uiaction"), actions: tap),
                CovRow(name: "UIButton target-action", find: id("cov.target"), actions: tap),
                CovRow(name: "UISwitch", find: id("cov.switch"), actions: toggle),
                CovRow(name: "UIStepper", find: id("cov.stepper"), actions: adj + ["fka-stepper"]),
                CovRow(name: "UIPageControl", find: id("cov.page"), actions: adj),
                CovRow(name: "UIDatePicker (compact)", find: id("cov.date"), actions: adj),
                CovRow(name: "UIPickerView", find: { $0.elementType == .pickerWheel }, actions: adj),
                CovRow(name: "UISearchBar Return", find: id("cov.search"), actions: text),
                CovRow(name: "UITextField Return", find: id("cov.field"), actions: text),
                CovRow(name: "UIButton menu (open)", find: id("cov.menu"), actions: tap),
                CovRow(name: "UIBarButtonItem (primaryAction)", find: id("cov.baritem"), actions: tap),
                CovRow(name: "Push button (nav)", find: id("cov.push"), actions: tap),
                CovRow(name: "Tab bar: Lists tab (UITab)", find: lbl("Lists", .button), actions: tap),
            ]),
            CovGroup(tab: "UIKit", presenter: "cov.alert", rows: [CovRow(name: "UIAlertController alert button", find: lbl("AlertOK"), actions: tap)]),
            CovGroup(tab: "UIKit", presenter: "cov.sheet", rows: [CovRow(name: "UIAlertController action sheet row", find: lbl("AlertOther"), actions: tap)]),
            CovGroup(tab: "UIKit", presenter: "cov.menu", rows: [CovRow(name: "UIMenu item (button menu)", find: lbl("MenuItemA"), actions: tap)]),
            CovGroup(tab: "UIKit", presenter: "cov.push", rows: [
                CovRow(name: "Nav bar item on pushed VC (target-action)", find: id("cov.detailitem"), actions: tap),
                CovRow(name: "Nav back button", find: { $0.elementType == .button && $0.label == "UIKit" }, actions: tap + ["2013"]),
            ]),
            CovGroup(tab: "Lists", presenter: nil, rows: [
                CovRow(name: "UICollectionViewListCell select", find: lbl("ListCell 0"), actions: tap),
                CovRow(name: "UICollectionViewListCell detail accessory", find: { $0.elementType == .button && $0.label.contains("More Info") || $0.label.contains("Detail") }, actions: tap),
                CovRow(name: "UITableViewCell (content configuration)", find: { $0.label.hasPrefix("TableCell 0") }, actions: tap),
            ]),
            CovGroup(tab: "SwiftUI", presenter: nil, rows: [
                CovRow(name: "SwiftUI Button", find: id("sui.button"), actions: tap),
                CovRow(name: "SwiftUI Toggle", find: id("sui.toggle"), actions: toggle),
                CovRow(name: "SwiftUI Stepper", find: id("sui.stepper"), actions: adj),
                CovRow(name: "SwiftUI Slider", find: id("sui.slider"), actions: adj),
                CovRow(name: "SwiftUI segmented Picker (P1)", find: lbl("P1", .button), actions: tap),
                CovRow(name: "SwiftUI TextField onSubmit", find: id("sui.field"), actions: text),
                CovRow(name: "SwiftUI NavigationLink row", find: id("sui.link"), actions: tap),
                CovRow(name: "SwiftUI TabView tab", find: lbl("InnerTabB", .button), actions: tap),
            ]),
            CovGroup(tab: "SwiftUI", presenter: nil, rows: [CovRow(name: "SwiftUI menu Picker (open)", find: id("sui.menupicker"), actions: tap)]),
            CovGroup(tab: "SwiftUI", presenter: nil, rows: [CovRow(name: "SwiftUI Menu (open)", find: { $0.label == "SUIMenu" }, actions: tap)]),
            CovGroup(tab: "SwiftUI", presenter: "sui.sheet", rows: [CovRow(name: "SwiftUI sheet button", find: id("sui.sheetbutton"), actions: tap)]),
            CovGroup(tab: "SwiftUI", presenter: "sui.alert", rows: [CovRow(name: "SwiftUI alert button", find: lbl("SUIAlertOK"), actions: tap)]),
            CovGroup(tab: "SwiftUI", presenter: "sui.menu", rows: [CovRow(name: "SwiftUI Menu item", find: lbl("SUIMenuItem"), actions: tap)]),
            CovGroup(tab: "Web", presenter: nil, rows: [
                CovRow(name: "WKWebView link", find: lbl("WebLink", .link), actions: tap),
                CovRow(name: "WKWebView button", find: lbl("WebButton", .button), actions: tap),
                CovRow(name: "WKWebView checkbox", find: { $0.label == "WebCheck" && ($0.elementType == .checkBox || $0.elementType == .switch) }, actions: tap),
                CovRow(name: "WKWebView text input", find: { $0.elementType == .textField }, actions: text),
                CovRow(name: "WKWebView submit", find: lbl("WebSubmit", .button), actions: tap),
            ]),
            CovGroup(tab: "UIKit", presenter: nil, rows: [CovRow(name: "Context menu (open, 2059)", find: id("cov.context"), actions: ["2059"])]),
        ]
    }

    func covAct(_ e: XCUIElementSnapshot, _ a: String) -> String {
        var err: NSString?
        switch a {
        case "2010", "2036", "2004", "2013":
            return PBHelper.pressSnapshot(e, action: Int(a)!, value: nil, error: &err) ? "ok" : "fail"
        case "2059":
            let f = e.frame; let p = NSValue(cgPoint: CGPoint(x: f.midX, y: f.midY))
            return PBHelper.pressSnapshot(e, action: 2059, value: p, error: &err) ? "ok" : "fail"
        case "set+2054", "set+key-return":
            let s = PBHelper.setAttribute("XC_kAXXCAttributeValue", value: "hello" as NSString, onSnapshot: e, error: &err) ? "ok" : "fail"
            usleep(300_000)
            if a == "set+2054" { var e2: NSString?; return "set \(s), 2054 " + (PBHelper.pressSnapshot(e, action: 2054, value: nil, error: &e2) ? "ok" : "fail") }
            return "set \(s), Return " + sendKey("\r")
        case "fka-right", "fka-space", "fka-stepper":
            guard let app = snap() else { return "no app" }
            let sid = (find(snap()) { $0.identifier == "sceneId" }?.value as? String) ?? ""
            _ = PBHelper.pressSnapshot(app, action: 5305, value: NSNumber(value: true), error: &err)
            if !sid.isEmpty { _ = PBHelper.pressSnapshot(app, action: 5310, value: sid as NSString, error: &err) }
            usleep(500_000)
            let f = PBHelper.pressSnapshot(e, action: 2044, value: nil, error: &err) ? "ok" : "fail"; usleep(600_000)
            return "focus \(f), key " + sendKey(a == "fka-space" ? " " : "UIKeyInputRightArrow")
        default: return "?"
        }
    }

    func runCoverage(_ bg: Bool) {
        background = bg
        for g in covGroups {
            usleep(500_000)
            fixture.launchArguments = ["-coverage", "-FullKeyboardAccessUsesSimulatedKeyboardForAutomation", "YES"]
            fixture.launch()
            let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
            if g.tab != "UIKit" { fixture.tabBars.buttons[g.tab].tap(); sleep(1) }
            if let p = g.presenter { fixture.descendants(matching: .any)[p].firstMatch.tap(); sleep(1) }
            if g.tab == "Web" { sleep(3) }
            if bg { _ = PBHelper.requestBackgroundAssertion(forPID: pid); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(1) }
            let fb = bg ? String(frontSummary().prefix(40)) : "-"
            for r in g.rows {
                guard let e = find(snap(), r.find) else { say("COV | \(r.name) | read: NOT FOUND"); continue }
                var tried: [String] = []; var fired = "none"
                for a in r.actions {
                    guard let e2 = find(snap(), r.find) ?? Optional(e) else { break }
                    let before = lastEvent(); let res = covAct(e2, a); usleep(1_200_000)
                    let after = lastEvent()
                    tried.append("\(a): \(res)")
                    if after != before { fired = "\(a) → \(after)"; break }
                }
                say("COV | \(r.name) | read: ok (\(e.elementType.rawValue)) | fired: \(fired) | tried: \(tried.joined(separator: "; "))")
            }
            if bg { say("COV | front check \(g.tab)/\(g.presenter ?? "-") | before: \(fb) | after: \(String(frontSummary().prefix(40)))") }
        }
    }
    func testCOV_foreground() { runCoverage(false) }
    func testCOV_background() { runCoverage(true) }
}
