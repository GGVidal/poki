import XCTest

extension SimFixtureTests {
    func testIPADSCREENS() {
        say("IPD | XCUIScreen.screens \(XCUIScreen.screens.count) | ids \(XCUIScreen.screens.map { ($0.value(forKey: "displayID") as? NSNumber)?.intValue ?? -1 })")
        for s in XCUIScreen.screens { let img = s.screenshot(); say("IPD | screen \(String(describing: s.value(forKey: "displayID"))) shot \(img.image.size)") }
        let s = settings; s.launch(); sleep(3)
        // look for Stage Manager / windowing setting
        let multi = s.staticTexts["Multitasking & Gestures"]; say("IPD | Multitasking & Gestures visible \(multi.exists)")
        if multi.exists { multi.tap(); sleep(2); say("IPD | multitasking screen labels \(labels(try? s.snapshot()) { $0.elementType == .button || $0.elementType == .staticText || $0.elementType == .switch }.prefix(25))") }
    }
}
