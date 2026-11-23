import XCTest

extension SimFixtureTests {
    func canAct(_ name: String, _ e: XCUIElementSnapshot?) {
        guard let e else { say("CA | \(name) | not found"); return }
        let before = lastEvent()
        let t0 = Date(); let r = PBHelper.daemonParamAttribute(95221, onSnapshot: e, parameter: NSNumber(value: 2010)); let dt = Date().timeIntervalSince(t0)
        var err: NSString?; let attrs = PBHelper.daemonAttributes(["XC_kAXXCAttributeUserTestingActions", "XC_kAXXCAttributeCustomActions", "XC_kAXXCAttributeTraits", "XC_kAXXCAttributeViewControllerClassName"], onSnapshot: e, error: &err) as? [String: Any] ?? [:]
        let ut = (attrs["XC_kAXXCAttributeUserTestingActions"] as? [Any])?.count ?? -1
        let ca = (attrs["XC_kAXXCAttributeCustomActions"] as? [Any])?.count ?? -1
        usleep(300_000)
        say("CA | \(name) | 95221(2010) \(String(format: "%.1f", dt)) s \(r.prefix(50)) | userTestingActions \(ut) customActions \(ca) traits \(attrs["XC_kAXXCAttributeTraits"] ?? "-") vc \(String(describing: attrs["XC_kAXXCAttributeViewControllerClassName"] ?? "-").prefix(40)) | handler \(lastEvent() == before ? "none" : lastEvent())")
    }
    func testCANACT() {
        covLaunch(tab: "UIKit", bg: true)
        canAct("UIButton target", find(snap()) { $0.identifier == "cov.target" })
        canAct("UISwitch", find(snap()) { $0.identifier == "cov.switch" })
        canAct("bar item", find(snap()) { $0.identifier == "cov.baritem" })
        canAct("tab item Lists", find(find(snap(), { $0.elementType == .tabBar })) { $0.label == "Lists" })
        fixture.terminate()
        covLaunch(tab: "Lists", bg: true)
        canAct("table row 1", find(snap(), { $0.identifier == "cov.table" })?.children.filter { $0.elementType == .cell }.dropFirst().first)
        fixture.terminate()
        covLaunch(tab: "SwiftUI", bg: true)
        canAct("SwiftUI Button", find(snap()) { $0.identifier == "sui.button" })
        canAct("SwiftUI segment P1", find(find(snap()) { $0.identifier == "sui.segment" }) { $0.label == "P1" })
        fixture.terminate()
    }
}
