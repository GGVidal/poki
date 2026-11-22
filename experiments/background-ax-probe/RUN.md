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
