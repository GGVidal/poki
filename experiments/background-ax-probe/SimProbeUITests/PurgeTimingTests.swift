import XCTest

extension SimFixtureTests {
    func testPURGETIMING() {
        for i in 1...5 {
            for withAssert in [true, false] {
                background = false; fixture.launchArguments = ["-coverage"]; fixture.launch(); sleep(2)
                let pid = (fixture.value(forKey: "processID") as? NSNumber)?.int32Value ?? -1
                if withAssert { _ = PBHelper.requestBackgroundAssertion(forPID: pid) }
                say("PT | run \(i) assert \(withAssert) | \(stamp()) activating Settings")
                settings.activate(); _ = settings.wait(for: .runningForeground, timeout: 10); sleep(4)
                fixture.terminate(); sleep(1)
            }
        }
    }
}
