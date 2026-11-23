import XCTest

extension SimFixtureTests {
    func testIPADSTAGE() {
        let s = settings; s.launch(); sleep(2)
        s.staticTexts["Multitasking & Gestures"].firstMatch.tap(); sleep(2)
        let all = labels(try? s.snapshot()) { [.button, .staticText, .switch, .cell].contains($0.elementType) }
        let idx = all.firstIndex { $0.contains("Multitasking") } ?? 0
        say("IPS | after open: \(all.dropFirst(idx).prefix(30))")
        for name in ["Stage Manager", "Windowed Apps", "Windowed apps"] {
            let e = s.buttons[name].firstMatch.exists ? s.buttons[name].firstMatch : s.staticTexts[name].firstMatch
            if e.exists { e.tap(); sleep(2); say("IPS | tapped \(name) → \(labels(try? s.snapshot()) { [.button, .staticText, .switch, .cell].contains($0.elementType) }.suffix(20))"); break }
        }
        sleep(3)
        for sc in XCUIScreen.screens { let id = (sc.value(forKey: "displayID") as? NSNumber)?.intValue ?? -1; let att = XCTAttachment(screenshot: sc.screenshot()); att.lifetime = .keepAlways; add(att); say("IPS | screen \(id) captured") }
    }
}
