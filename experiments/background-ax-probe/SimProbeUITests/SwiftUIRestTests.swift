import XCTest

extension SimFixtureTests {
    func labels(_ s: XCUIElementSnapshot?, _ pred: (XCUIElementSnapshot) -> Bool) -> [String] { var o: [String] = []; func w(_ e: XCUIElementSnapshot) { if pred(e) { o.append("\(e.elementType.rawValue):\(e.label.isEmpty ? e.identifier : e.label)") }; e.children.forEach(w) }; if let s { w(s) }; return o }
    func testSUIREST_background() {
        covLaunch(tab: "SwiftUI", bg: true)
        tryCtl("SUITapRow", 2010) { s in self.find(s) { $0.identifier == "sui.taprow" } }
        // scroll the list down
        if let list = find(snap(), { $0.elementType == .collectionView || $0.elementType == .table }) {
            var e: NSString?; say("SUIR | scroll 2019 \(PBHelper.pressSnapshot(list, action: 2019, value: nil, error: &e) ? "ok" : "fail")"); usleep(800_000); _ = kickNow(); usleep(500_000)
        }
        say("SUIR | after scroll ids \(labels(snap()) { $0.identifier.hasPrefix("sui.") || $0.label.hasPrefix("Inner") }.prefix(20))")
        tryCtl("SUILink", 2010) { s in self.find(s) { $0.identifier == "sui.link" } }
        say("SUIR | nav bars \(labels(snap()) { $0.elementType == .navigationBar })")
        tryCtl("InnerTabB", 2010) { s in self.find(s) { $0.label == "InnerTabB" } }
        fixture.terminate()
        covLaunch(tab: "SwiftUI", bg: true)
        tryCtl("SUIShowAlert", 2010) { s in self.find(s) { $0.identifier == "sui.alert" } }
        _ = kickNow(); usleep(800_000)
        say("SUIR | alert tree \(labels(snap()) { $0.label.hasPrefix("SUIAlert") })")
        tryCtl("SUIAlertOK", 2010) { s in self.find(s) { $0.label == "SUIAlertOK" } }
        fixture.terminate()
        covLaunch(tab: "SwiftUI", bg: true)
        tryCtl("SUIMenu", 2010) { s in self.find(s) { $0.identifier == "sui.menu" } }
        _ = kickNow(); usleep(800_000)
        say("SUIR | menu tree \(labels(snap()) { $0.label.contains("SUIMenu") })")
        tryCtl("SUIMenuItem", 2010) { s in self.find(s) { $0.label == "SUIMenuItem" } }
        tryCtl("SUIShowSheet", 2010) { s in self.find(s) { $0.identifier == "sui.sheet" } }
        _ = kickNow(); usleep(800_000)
        tryCtl("SUISheetButton", 2010) { s in self.find(s) { $0.identifier == "sui.sheetbutton" } }
        say("SUIR | front \(String(frontSummary().prefix(30)))")
        fixture.terminate()
    }
}
