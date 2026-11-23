import XCTest

// RAW 81: SpringBoard's re-snapshot of a background scene (here forced by an appearance flip) runs
// -[UIWindowScene _prepareForResume] → contexts live → snapshot → _prepareForSuspend. Question: does an
// in-process press (focus-restored control, AX 4000) that is in flight across the flip land inside that window?
extension SimFixtureTests {
    func testSNAPWINDOW() {
        say("SW | FKA \(PBHelper.setFullKeyboardAccess(true))")
        let targets = ProcessInfo.processInfo.environment["SW_TARGETS"].map { $0.split(separator: ",").map(String.init) } ?? ["cov.switch"]
        for target in targets {
            covLaunch(tab: "UIKit", bg: true)
            let el = find(snap()) { $0.identifier == target }
            let f = fkaFocus(el)
            say("SW | \(target) | focus \(f) | start last=\(lastEvent())")
            var hits = 0
            for round in 1...(Int(ProcessInfo.processInfo.environment["SW_ROUNDS"] ?? "20") ?? 20) {
                let before = lastEvent()
                let stop = NSLock(); var running = true; var sent = 0
                let group = DispatchGroup()
                guard let shared = snap() else { say("SW | no snapshot"); continue }
                for _ in 0..<4 {
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        while true {
                            stop.lock(); let r = running; stop.unlock(); if !r { break }
                            var e: NSString?
                            _ = PBHelper.pressSnapshot(shared, action: 4000, value: nil, error: &e)
                            stop.lock(); sent += 1; stop.unlock()
                        }
                        group.leave()
                    }
                }
                usleep(200_000)
                XCUIDevice.shared.appearance = (round % 2 == 0) ? .light : .dark
                usleep(1_500_000)
                stop.lock(); running = false; stop.unlock(); group.wait()
                let after = lastEvent()
                if after != before { hits += 1 }
                let ctx = snap().map { PBHelper.contextId(ofSnapshot: $0) } ?? 0
                say("SW | \(target) | round \(round) | presses \(sent) | ctx now \(ctx) | before \(before) after \(after)")
            }
            say("SW | \(target) | HITS \(hits)/20 | front \(String(frontSummary().prefix(30)))")
            XCUIDevice.shared.appearance = .light
            fixture.terminate(); sleep(1)
        }
    }
}

extension SimFixtureTests {
    // (c) Presses in flight across the background-entry pass: does one fire with state=2 while the context is live?
    func testSNAPENTRY() {
        say("SE | FKA \(PBHelper.setFullKeyboardAccess(true))")
        let target = ProcessInfo.processInfo.environment["SW_TARGETS"] ?? "cov.switch"
        for round in 1...(Int(ProcessInfo.processInfo.environment["SW_ROUNDS"] ?? "5") ?? 5) {
            covLaunch(tab: "UIKit", bg: false)
            let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
            _ = PBHelper.requestBackgroundAssertion(forPID: pid)
            let f = fkaFocus(find(snap()) { $0.identifier == target })
            guard let shared = snap() else { continue }
            let lock = NSLock(); var running = true; var sent = 0
            let group = DispatchGroup()
            for _ in 0..<4 {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    while true {
                        lock.lock(); let r = running; lock.unlock(); if !r { break }
                        var e: NSString?; _ = PBHelper.pressSnapshot(shared, action: 4000, value: nil, error: &e)
                        lock.lock(); sent += 1; lock.unlock()
                    }
                    group.leave()
                }
            }
            usleep(300_000)
            say("SE | round \(round) | \(stamp()) activating Settings | focus \(f)")
            settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10)
            sleep(2)
            lock.lock(); running = false; lock.unlock(); group.wait()
            say("SE | round \(round) | presses \(sent) | last \(lastEvent())")
            fixture.terminate(); sleep(1)
        }
    }
}

extension SimFixtureTests {
    // Candidate triggers for an on-demand resume/suspend bracket of a background scene. Detector: fixture's
    // "FIXLOG bracket" lines (swizzled _prepareForResume/_prepareForSuspend). Each candidate once, marked by time.
    func testTRIGGERS() {
        covLaunch(tab: "UIKit", bg: false)
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        _ = PBHelper.requestBackgroundAssertion(forPID: pid)
        settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(3)
        func mark(_ s: String) { say("TR | \(stamp()) | \(s)"); }
        mark("orientation landscape"); XCUIDevice.shared.orientation = .landscapeLeft; sleep(3)
        mark("orientation portrait"); XCUIDevice.shared.orientation = .portrait; sleep(3)
        mark("fixture snapshot read"); _ = snap(); sleep(2)
        mark("screenshot of main screen"); _ = XCUIScreen.main.screenshot(); sleep(2)
        mark("fixture screenshot (element)"); _ = fixture.screenshot(); sleep(2)
        mark("second bg assertion"); _ = PBHelper.requestBackgroundAssertion(forPID: pid); sleep(2)
        mark("hidden open ActivateSuspended \(PBHelper.fbsOpen("local.pokimcp.axfixture", optionKeys: ["__ActivateSuspended"]).prefix(60))"); sleep(3)
        mark("home button"); XCUIDevice.shared.press(.home); sleep(3)
        mark("settings re-activate"); settings.activate(); sleep(3)
        mark("siri lock?"); sleep(1)
        mark("done | last \(lastEvent())")
        fixture.terminate()
    }
}

extension SimFixtureTests {
    // 2045 orb gesture (in-process recognizer simulation) on the context-menu target, front then background.
    func testORB() {
        for bg in [false, true] {
            covLaunch(tab: "UIKit", bg: bg)
            for v: NSNumber? in [nil, 1, 2, 3] {
                guard let el = find(snap(), { $0.identifier == "cov.context" }) else { say("ORB | no target"); break }
                let b = lastEvent(); var e: NSString?
                let ok = PBHelper.pressSnapshot(el, action: 2045, value: v, error: &e); sleep(1)
                let item = find(snap()) { $0.label == "CtxItem" } != nil
                say("ORB | bg \(bg) | 2045 value \(v.map { "\($0)" } ?? "nil") \(ok ? "ok" : "fail \(e ?? "")") | before \(b) after \(lastEvent()) | menu item visible \(item)")
                if item, let it = find(snap(), { $0.label == "CtxItem" }) {
                    let b2 = lastEvent(); let ok2 = PBHelper.pressSnapshot(it, action: 2010, value: nil, error: &e); sleep(1)
                    say("ORB | bg \(bg) | 2010 on CtxItem \(ok2) | before \(b2) after \(lastEvent())")
                }
            }
            fixture.terminate(); sleep(1)
        }
    }
}

extension SimFixtureTests {
    // RAW 77/78 leftovers, each once, fixture in background (assertion), Settings in front.
    func testLEFTOVERS() {
        func t(_ name: String, _ e: XCUIElementSnapshot?, _ id: Int, _ v: Any? = nil) {
            guard let e else { say("LO | \(name) | not found"); return }
            let b = lastEvent(); var err: NSString?
            let ok = PBHelper.pressSnapshot(e, action: id, value: v, error: &err); usleep(900_000)
            say("LO | \(name) | \(id) \(ok ? "ok" : "fail") | before \(b) after \(lastEvent())")
        }
        // compact date picker
        covLaunch(tab: "UIKit", bg: true)
        t("compact date 2010", find(snap()) { $0.identifier == "cov.date" }, 2010)
        t("compact date 2004", find(snap()) { $0.identifier == "cov.date" }, 2004)
        fixture.terminate(); sleep(1)
        // destructive + text field alert, presented in front, acted on in background
        covLaunch(tab: "UIKit", presenter: "cov.alert2", bg: true)
        t("alert field set 2006", find(snap()) { $0.identifier == "cov.alertfield" }, 2006, "bgtext" as NSString)
        t("alert Delete (destructive) 2010", find(snap()) { $0.label == "AlertDelete" }, 2010)
        fixture.terminate(); sleep(1)
        covLaunch(tab: "UIKit", presenter: "cov.alert2", bg: true)
        t("alert field set 2006", find(snap()) { $0.identifier == "cov.alertfield" }, 2006, "bgtext2" as NSString)
        t("alert Submit 2010", find(snap()) { $0.label == "AlertSubmit" }, 2010)
        fixture.terminate(); sleep(1)
        // action sheet dismiss by escape (dimming view)
        covLaunch(tab: "UIKit", presenter: "cov.sheet", bg: true)
        t("sheet escape 2013 on app", snap(), 2013)
        say("LO | sheet still up \(find(snap()) { $0.label == "AlertOK" } != nil)")
        t("sheet Cancel 2010", find(snap()) { $0.label == "AlertCancel" }, 2010)
        fixture.terminate(); sleep(1)
        // UIKit segmented control (default, non-coverage UI)
        background = true; fixture.launchArguments = []; fixture.launch(); sleep(2)
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        _ = PBHelper.requestBackgroundAssertion(forPID: pid); settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(1)
        let seg = find(snap()) { $0.elementType == .segmentedControl }
        t("UISegmentedControl 2004", seg, 2004)
        t("UISegmentedControl segment Two 2010", find(seg) { $0.label == "Two" }, 2010)
        fixture.terminate()
    }
}

extension SimFixtureTests {
    // What the in-process press (4000) needs, in the foreground: FKA setting, launch arg, focus via 2044 or 5308.
    func testPRESSNEEDS() {
        for (fka, arg) in [(false, false), (false, true), (true, false), (true, true)] {
            say("PN | FKA setting \(fka) \(PBHelper.setFullKeyboardAccess(fka)) | launch arg \(arg)")
            for how in ["none", "2044", "5308", "5305+5310+2044"] {
                background = false
                fixture.launchArguments = arg ? ["-coverage", "-FullKeyboardAccessUsesSimulatedKeyboardForAutomation", "YES"] : ["-coverage"]
                fixture.launch(); sleep(2)
                guard let app = snap(), let sw = find(app, { $0.identifier == "cov.switch" }) else { say("PN | no switch"); continue }
                var e: NSString?; var r = "-"
                switch how {
                case "2044": r = PBHelper.pressSnapshot(sw, action: 2044, value: nil, error: &e) ? "ok" : "fail"
                case "5308": r = PBHelper.pressSnapshot(app, action: 5308, value: NSNumber(value: true), error: &e) ? "app ok" : "app fail"
                    r += "/" + (PBHelper.pressSnapshot(sw, action: 5308, value: NSNumber(value: true), error: &e) ? "sw ok" : "sw fail")
                case "5305+5310+2044": r = fkaFocus(sw)
                default: break
                }
                usleep(500_000)
                let b = lastEvent(); let ok = PBHelper.pressSnapshot(snap() ?? app, action: 4000, value: nil, error: &e); usleep(800_000)
                say("PN | fka \(fka) arg \(arg) | focus \(how) \(r) | 4000 \(ok ? "ok" : "fail") | before \(b) after \(lastEvent())")
                fixture.terminate(); sleep(1)
            }
        }
        _ = PBHelper.setFullKeyboardAccess(false)
    }
}

extension SimFixtureTests {
    // Focus set only after backgrounding (inside the entry window), then press: never focused in front.
    func testSNAPENTRYFOCUS() {
        _ = PBHelper.setFullKeyboardAccess(true)
        for round in 1...5 {
            covLaunch(tab: "UIKit", bg: false)
            let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
            _ = PBHelper.requestBackgroundAssertion(forPID: pid)
            guard let shared = snap(), let sw = find(shared, { $0.identifier == "cov.switch" }) else { continue }
            let lock = NSLock(); var running = true; var go = false
            let group = DispatchGroup()
            for k in 0..<4 {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    while true {
                        lock.lock(); let r = running; let g = go; lock.unlock(); if !r { break }
                        if !g { usleep(2_000); continue }
                        var e: NSString?
                        if k % 2 == 0 { _ = PBHelper.pressSnapshot(sw, action: 2044, value: nil, error: &e) }
                        else { _ = PBHelper.pressSnapshot(shared, action: 4000, value: nil, error: &e) }
                    }
                    group.leave()
                }
            }
            say("SEF | round \(round) | \(stamp()) activating Settings (no focus set in front)")
            settings.activate(); lock.lock(); go = true; lock.unlock()
            _ = settings.wait(for: .runningForeground, timeout: 10); sleep(2)
            lock.lock(); running = false; lock.unlock(); group.wait()
            say("SEF | round \(round) | last \(lastEvent())")
            fixture.terminate(); sleep(1)
        }
        _ = PBHelper.setFullKeyboardAccess(false)
    }
}

extension SimFixtureTests {
    // iPad sim, Windowed Apps: fixture window covered by Settings, fixture not key. Does it keep a live context, and do
    // in-process presses fire (FKA on), with chains and no time limit?
    func testIPADWINDOWED() {
        let s = settings; s.launch(); sleep(2)
        s.staticTexts["Multitasking & Gestures"].firstMatch.tap(); sleep(2)
        for name in ["Windowed Apps", "Windowed apps"] {
            let e = s.buttons[name].firstMatch.exists ? s.buttons[name].firstMatch : s.staticTexts[name].firstMatch
            if e.exists { e.tap(); sleep(2); say("IPW | selected \(name)"); break }
        }
        s.terminate(); sleep(1)
        say("IPW | FKA \(PBHelper.setFullKeyboardAccess(true))")
        background = true
        fixture.launchArguments = ["-coverage"]; fixture.launch(); sleep(2)
        let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        say("IPW | fixture frame \(fixture.frame)")
        s.launch(); _ = s.wait(for: .runningForeground, timeout: 10); sleep(2)
        // try to maximise Settings over the fixture: double-tap its top edge (window title area)
        let top = s.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)); top.doubleTap(); sleep(2)
        say("IPW | settings frame \(s.windows.firstMatch.frame) | fixture state \(fixture.state.rawValue) | settings state \(s.state.rawValue) | pid \(pid)")
        sleep(5)
        let ctx = snap().map { PBHelper.contextId(ofSnapshot: $0) } ?? 0
        say("IPW | +7 s fixture ctx \(ctx)")
        func press(_ id: String, _ what: String) {
            var e: NSString?
            let f = fkaFocus(find(snap()) { $0.identifier == id })
            let b = lastEvent(); let ok = snap().map { PBHelper.pressSnapshot($0, action: 4000, value: nil, error: &e) } ?? false; usleep(900_000)
            say("IPW | \(what) | focus \(f) | 4000 \(ok) | before \(b) after \(lastEvent()) | ctx \(snap().map { PBHelper.contextId(ofSnapshot: $0) } ?? 0)")
        }
        press("cov.switch", "switch")
        press("cov.configured", "button")
        press("cov.push", "push (chain step 1)")
        sleep(1)
        if let item = find(snap(), { $0.identifier == "cov.detailitem" }) { var e: NSString?; let b = lastEvent(); let ok = PBHelper.pressSnapshot(item, action: 2010, value: nil, error: &e); usleep(800_000); say("IPW | chain step 2 detail bar item 2010 \(ok) | before \(b) after \(lastEvent())") }
        // any-time AX action for comparison
        if let ba = find(snap(), { $0.identifier == "cov.baritem" }) { var e: NSString?; let b = lastEvent(); let ok = PBHelper.pressSnapshot(ba, action: 2010, value: nil, error: &e); usleep(800_000); say("IPW | bar item 2010 \(ok) | before \(b) after \(lastEvent())") }
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); att.lifetime = .keepAlways; add(att)
        say("IPW | front \(String(frontSummary().prefix(40))) | settings state \(s.state.rawValue)")
        _ = PBHelper.setFullKeyboardAccess(false)
        fixture.terminate()
    }
}

extension SimFixtureTests {
    // iPad sim, Windowed Apps: fixture window shrunk and moved so only a sliver shows beside Settings (front, key).
    func testIPADSLIVER() {
        let s = settings
        say("IPSL | FKA \(PBHelper.setFullKeyboardAccess(true))")
        func frames(_ tag: String) { let ff = fixture.state.rawValue >= 2 ? "\(fixture.windows.firstMatch.frame)" : "-"; say("IPSL | \(tag) | fixture \(ff) state \(fixture.state.rawValue) | settings \(s.windows.firstMatch.frame) state \(s.state.rawValue) | ctx \(fixture.state.rawValue >= 2 ? (snap().map { PBHelper.contextId(ofSnapshot: $0) } ?? 0) : 0)") }
        func drag(_ app: XCUIApplication, from a: CGVector, to b: CGVector) {
            let w = app.windows.firstMatch
            w.coordinate(withNormalizedOffset: a).press(forDuration: 0.6, thenDragTo: w.coordinate(withNormalizedOffset: b)); sleep(2)
        }
        // 1. Settings: shrink to ~75% width (bottom-right corner drag)
        s.launch(); sleep(2); drag(s, from: CGVector(dx: 0.995, dy: 0.995), to: CGVector(dx: 0.75, dy: 0.995)); frames("settings shrunk")
        // 2. fixture: shrink to ~35% width, then move right by its title area so its right part lies beyond Settings
        background = true; fixture.launchArguments = ["-coverage"]; fixture.launch(); sleep(2)
        drag(fixture, from: CGVector(dx: 0.995, dy: 0.995), to: CGVector(dx: 0.40, dy: 0.80)); frames("fixture shrunk")
        drag(fixture, from: CGVector(dx: 0.5, dy: 0.005), to: CGVector(dx: 1.6, dy: 0.005)); frames("fixture moved right")
        // 3. Settings front and key
        s.activate(); sleep(3); frames("settings front")
        func press(_ id: String, _ what: String) {
            var e: NSString?; let f = fkaFocus(find(snap()) { $0.identifier == id })
            let b = lastEvent(); let ok = snap().map { PBHelper.pressSnapshot($0, action: 4000, value: nil, error: &e) } ?? false; usleep(900_000)
            say("IPSL | \(what) | focus \(f) | 4000 \(ok) | before \(b) after \(lastEvent()) | settings state \(s.state.rawValue)")
        }
        for k in 0..<4 {
            press("cov.switch", "t+\(k*20)s switch")
            press("cov.configured", "t+\(k*20)s button")
            frames("t+\(k*20)s")
            sleep(15)
        }
        press("cov.push", "chain push")
        if let item = find(snap(), { $0.identifier == "cov.detailitem" }) { var e: NSString?; let b = lastEvent(); _ = PBHelper.pressSnapshot(item, action: 2010, value: nil, error: &e); usleep(800_000); say("IPSL | chain step 2 detail item 2010 | before \(b) after \(lastEvent())") }
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); att.lifetime = .keepAlways; add(att)
        frames("end")
        _ = PBHelper.setFullKeyboardAccess(false)
        fixture.terminate(); s.terminate()
    }
}

// RAW 76: cross-toolkit fixtures (Flutter, React Native, Compose) through the any-time AX route, in background.
final class ToolkitTests: XCTestCase {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    var app: XCUIApplication!
    func say(_ s: String) { print("SIMPROBE TK \(s)") }
    func snap() -> XCUIElementSnapshot? { try? app.snapshot() }
    func all(_ s: XCUIElementSnapshot?) -> [XCUIElementSnapshot] { guard let s else { return [] }; return [s] + s.children.flatMap { all($0) } }
    func find(_ label: String) -> XCUIElementSnapshot? {
        if label.hasPrefix("type"), let t = UInt(label.dropFirst(4)) { return all(snap()).first { $0.elementType.rawValue == t } }
        return all(snap()).first { ($0.label == label || $0.identifier == label) && $0.elementType != .staticText } ?? all(snap()).first { $0.label == label || $0.identifier == label }
    }
    func findPrefix(_ p: String) -> XCUIElementSnapshot? { all(snap()).first { $0.label.hasPrefix(p) } }
    func last() -> String { let e = all(snap()).first { $0.identifier == "lastEvent" || $0.label.hasPrefix("last ") }; return e.map { $0.label.isEmpty ? (($0.value as? String) ?? "") : $0.label } ?? "nil" }
    func act(_ e: XCUIElementSnapshot?, _ id: Int, _ v: Any? = nil) -> String {
        guard let e else { return "not found" }; var err: NSString?
        return PBHelper.pressSnapshot(e, action: id, value: v, error: &err) ? "ok" : "fail"
    }
    func testTOOLKIT() {
        let env = ProcessInfo.processInfo.environment
        app = XCUIApplication(bundleIdentifier: env["TK_BUNDLE"] ?? "local.pokimcp.flutterfix")
        app.launch(); sleep(3)
        say("tree FG: \(all(snap()).map { "\($0.elementType.rawValue):\($0.label)|\($0.identifier)" }.filter { !$0.hasSuffix(":|") }.prefix(60))")
        let pid = (app.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
        _ = PBHelper.requestBackgroundAssertion(forPID: pid)
        settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(2)
        say("tree BG: \(all(snap()).count) elements, last=\(last())")
        // controls: "label:action[:value]" separated by ;
        for spec in (env["TK_CONTROLS"] ?? "").split(separator: ";").map(String.init) {
            let p = spec.split(separator: ":").map(String.init); guard p.count >= 2, let id = Int(p[1]) else { continue }
            var hits = 0; var res = ""
            for _ in 0..<5 {
                let b = last(); let e = p[0].hasSuffix("*") ? findPrefix(String(p[0].dropLast())) : find(p[0])
                res = act(e, id, p.count > 2 ? p[2] as NSString : nil); usleep(700_000)
                if last() != b { hits += 1 }
                if p.count > 3, p[3] == "back" { _ = act(snap(), 2013); usleep(700_000) }
            }
            say("CTL | \(p[0]) | \(id) | last result \(res) | fired \(hits)/5 | now \(last())")
        }
        // chain: row → detail unique button → back
        if let row = env["TK_ROW"], let det = env["TK_DETAIL"] {
            for i in 1...3 {
                let b = last(); let r1 = act(find(row), 2010); sleep(2)
                let d = find(det); let b2 = last(); let r2 = act(d, 2010); usleep(900_000)
                let r3 = act(snap(), 2013); sleep(1)
                say("CHAIN \(i) | row 2010 \(r1) (\(b) -> \(b2)) | detail found \(d != nil) 2010 \(r2) -> \(last()) | back 2013 \(r3) | row visible again \(find(row) != nil)")
            }
        }
        say("front \(settings.state.rawValue) app \(app.state.rawValue)")
        app.terminate()
    }
}
