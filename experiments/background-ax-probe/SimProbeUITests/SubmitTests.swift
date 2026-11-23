import XCTest

extension SimFixtureTests {
    func testSUBMIT() {
        covLaunch(tab: "UIKit", bg: true)
        for (name, id) in [("field", "cov.field"), ("search", "cov.search")] {
            guard let f = find(snap(), { $0.identifier == id }) else { say("SUB | \(name) not found"); continue }
            var err: NSString?
            for v in ["abc\n", "abc\r"] {
                let before = lastEvent()
                let ok = PBHelper.setAttribute("XC_kAXXCAttributeValue", value: v, onSnapshot: f, error: &err); usleep(900_000)
                say("SUB | \(name) | set value ending \(v == "abc\n" ? "\\n" : "\\r") via testmanagerd → \(ok) | before \(before) after \(lastEvent())")
            }
            for aid in [2010, 2011, 2054] { let before = lastEvent(); var e: NSString?; let ok = PBHelper.pressSnapshot(f, action: aid, value: nil, error: &e); usleep(900_000); say("SUB | \(name) | \(aid) via testmanagerd → \(ok) | before \(before) after \(lastEvent())") }
            var e2: Int32 = 0; let ca = (PBHelper.axRef(f) as AnyObject?).flatMap { PBHelper.axCopy($0, attr: 2036, err: &e2) as? [Any] } ?? []
            say("SUB | \(name) | custom actions \(ca.count)")
        }
        fixture.terminate()
    }
}
