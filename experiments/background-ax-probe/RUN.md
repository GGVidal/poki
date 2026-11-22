# R8 probe (simulator only)

Not built or run until the owner approves an XCTest-family probe.

```bash
cd experiments/background-ax-probe
xcodegen generate
SIM=$(xcrun simctl create "AX probe" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro <iOS 27.3 runtime id>)
xcodebuild test -project BackgroundAXProbe.xcodeproj -scheme Probe -destination "id=$SIM" \
  -derivedDataPath .build/dd CODE_SIGNING_ALLOWED=NO \
  -only-testing:ProbeUITests/BackgroundAXActionTests | grep PROBE
xcrun simctl delete "$SIM"; rm -rf .build
```

Pass: snapshot ok at t+40s with Settings still `runningForeground` (4), `performAction ok=true`, the counter read in the background changes, and the verification counter matches.

## On-device run (iPhone18,1, iOS 27.3 24C5037i), 2026-11-22 03:44-03:51 ET

Owner approved the phone run. Target: the original Calculator. Handset front app: Settings throughout.
Only addition to the phone: the probe's XCTest runner (`com.zhehanz.bgaxprobe.uitests.xctrunner`),
uninstalled after the run. Raw lines: `device-run-results.txt`.

| Run | Mark | Assertion | Snapshot of background Calculator | AXPress "7" | Handset front |
| - | - | - | - | - | - |
| A (assertion) | grant | `_XCT_requestBackgroundAssertionForPID` -> granted (1) | | | Settings |
| A | +2 s, +15 s, +40 s, +120 s, +300 s | held | **timeout after 8 s** (every mark) | not reached | Settings |
| A | end | | Calculator state 3 (runningBackground, not suspended) | | Settings |
| B (control) | +2 s | none | timeout after 8 s | not reached | Settings |
| B | +15 s, +40 s | none | `Error Domain=com.apple.dt.xctest.automation-support.error Code=8 "Error getting main window kAXErrorServerNotFound"` | not reached | Settings |
| B | end | | Calculator state 2 (runningBackgroundSuspended) | | Settings |

Result: the background assertion works on the phone (Calculator stays running instead of being
suspended, and Settings keeps the foreground). But a running, non-frontmost app's accessibility
server does not answer snapshot requests (timeouts with the assertion; "server not found" once
suspended without it). Read and act by accessibility on a background app: **fail** on iOS 27.3.
