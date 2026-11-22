import XCTest

// R8b (simulator only, NOT BUILT until the owner approves): keep a background app running
// through testmanagerd's background assertion, then read and act on it by accessibility
// element, never by screen coordinate, while Settings stays frontmost.
//
// Private XCTest calls used (names from Xcode 27.3 XCUIAutomation exports, reached by
// selector so nothing private is linked):
//   -[XCUIApplication applicationProcess]                 (if present)
//   -[XCUIApplicationProcess acquireBackgroundAssertion]  -> _XCT_requestBackgroundAssertionForPID:reply:
//   -[XCUIDevice accessibilityInterface]                  -> XCAXClient_iOS
//   -[XCAXClient_iOS performAction:onElement:value:error:] -> _XCT_performAccessibilityAction:onElement:withValue:reply:
//   -[XCUIElementSnapshot accessibilityElement]
final class BackgroundAXActionTests: XCTestCase {
    let fixture = XCUIApplication(bundleIdentifier: "local.pokimcp.axprobe.fixture")
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    static let axPress: Int = 2010  // AXPress action id used by AXRuntime (hypothesis; logged if refused)

    func say(_ s: String) { print("PROBE \(Date().timeIntervalSince1970) \(s)") }

    func call(_ target: NSObject, _ name: String) -> AnyObject? {
        let sel = NSSelectorFromString(name)
        guard target.responds(to: sel) else { say("no selector \(name) on \(type(of: target))"); return nil }
        return target.perform(sel)?.takeUnretainedValue()
    }

    func testBackgroundAssertionThenElementAction() throws {
        fixture.launch()
        let before = fixture.staticTexts["counter"].label
        settings.activate()
        _ = settings.wait(for: .runningForeground, timeout: 10)
        say("fixture state=\(fixture.state.rawValue) settings state=\(settings.state.rawValue) counter(before)=\(before)")

        // 1. Background assertion on the fixture's process.
        if let process = call(fixture, "applicationProcess") as? NSObject {
            _ = call(process, "acquireBackgroundAssertion")
            say("acquireBackgroundAssertion sent for \(process)")
        }

        // 2. Wait past the normal suspension grace, then read without activating.
        for delay in [2, 15, 40] {
            sleep(UInt32(delay == 2 ? 2 : (delay == 15 ? 13 : 25)))
            let t0 = Date()
            let snap = try? fixture.snapshot()
            say("t+\(delay)s snapshot ok=\(snap != nil) children=\(snap?.children.count ?? -1) in \(Int(Date().timeIntervalSince(t0) * 1000)) ms; fixture state=\(fixture.state.rawValue) settings state=\(settings.state.rawValue)")
        }

        // 3. Accessibility action on the Increment button by element.
        guard let device = XCUIDevice.shared as NSObject?,
              let ax = call(device, "accessibilityInterface") as? NSObject,
              let buttonSnap = try? fixture.buttons["Increment"].snapshot() as? NSObject,
              let element = call(buttonSnap, "accessibilityElement") else {
            say("could not resolve accessibility interface or element"); return
        }
        let sel = NSSelectorFromString("performAction:onElement:value:error:")
        typealias Fn = @convention(c) (AnyObject, Selector, Int, AnyObject, AnyObject?, UnsafeMutablePointer<NSError?>?) -> Bool
        var error: NSError?
        let ok = unsafeBitCast(ax.method(for: sel), to: Fn.self)(ax, sel, Self.axPress, element, nil, &error)
        say("performAction AXPress ok=\(ok) error=\(String(describing: error)); settings state=\(settings.state.rawValue)")
        sleep(1)
        let after = try? fixture.staticTexts["counter"].snapshot().label
        say("counter(after, read in background)=\(after ?? "nil")")

        // 4. Verification only: bring the fixture forward once.
        fixture.activate()
        say("verification counter=\(fixture.staticTexts["counter"].label)")
    }
}
