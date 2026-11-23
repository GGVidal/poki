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
