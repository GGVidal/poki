import XCTest

// R8 (simulator only): can an XCTest session read and act on an app that is running but not
// frontmost, without bringing it forward? Every observation is printed with a "PROBE" prefix.
final class BackgroundProbeTests: XCTestCase {
    let fixture = XCUIApplication(bundleIdentifier: "local.pokimcp.axprobe.fixture")
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    func say(_ s: String) { print("PROBE \(Date().timeIntervalSince1970) \(s)") }

    func stateName(_ s: XCUIApplication.State) -> String {
        switch s {
        case .unknown: return "unknown"
        case .notRunning: return "notRunning"
        case .runningBackgroundSuspended: return "runningBackgroundSuspended"
        case .runningBackground: return "runningBackground"
        case .runningForeground: return "runningForeground"
        @unknown default: return "raw\(s.rawValue)"
        }
    }

    func testBackgroundReadAndAct() throws {
        fixture.launch()
        fixture.buttons["Increment"].tap()
        say("foreground counter=\(fixture.staticTexts["counter"].label) state=\(stateName(fixture.state))")

        settings.activate()
        _ = settings.wait(for: .runningForeground, timeout: 10)
        sleep(3)
        say("after Settings activate: fixture state=\(stateName(fixture.state)) settings state=\(stateName(settings.state))")

        // 1. Read the background app without activating it.
        let start = Date()
        do {
            let snap = try fixture.snapshot()
            func count(_ e: XCUIElementSnapshot) -> Int { 1 + e.children.map(count).reduce(0, +) }
            func labels(_ e: XCUIElementSnapshot) -> [String] { [e.identifier + "=" + e.label] + e.children.flatMap(labels) }
            say("background snapshot: \(count(snap)) elements in \(Int(Date().timeIntervalSince(start) * 1000)) ms; frame=\(snap.frame)")
            say("background labels: \(labels(snap).filter { $0 != "=" }.prefix(30))")
        } catch {
            say("background snapshot error: \(error)")
        }
        say("after snapshot: fixture state=\(stateName(fixture.state)) settings state=\(stateName(settings.state))")

        // 2. Query-based read (what WDA and Poki use for element lookup).
        let counter = fixture.staticTexts["counter"]
        say("background counter exists=\(counter.exists) label=\(counter.exists ? counter.label : "-")")
        say("after query: fixture state=\(stateName(fixture.state)) settings state=\(stateName(settings.state))")

        // 3. Action on the background app's element. XCTest taps are synthesized touches, so this also
        //    records whether the touch lands on Settings (crossover) or XCTest refuses or activates.
        let button = fixture.buttons["Increment"]
        if button.exists {
            button.tap()
            say("background tap issued; fixture state=\(stateName(fixture.state)) settings state=\(stateName(settings.state))")
        } else {
            say("background button not found; no tap")
        }
        sleep(1)

        // 4. Verification step only: bring the fixture forward once and read the counter.
        fixture.activate()
        _ = fixture.wait(for: .runningForeground, timeout: 10)
        say("verification: counter=\(fixture.staticTexts["counter"].label) state=\(stateName(fixture.state))")
    }
}
