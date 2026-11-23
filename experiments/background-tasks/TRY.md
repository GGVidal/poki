# Background tasks prototype (issue #656), Poki Lab only

Experimental. It builds only into Poki Lab (`nz.zheha.poki.lab`, `native/ios-app/project-lab.yml`,
compile flag `POKI_EXPERIMENTS`). Poki's alpha and beta projects never compile it.

## Build Poki Lab for the simulator

```bash
xcodegen generate --spec native/ios-app/project-lab.yml
xcodebuild build -project native/ios-app/PokiLab.xcodeproj -scheme Poki -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/sim-lab CODE_SIGNING_ALLOWED=NO ARCHS=arm64
```

The app is `build/sim-lab/Build/Products/Debug-iphonesimulator/Poki.app`. The simulator build needs
`native/launcher/target/aarch64-apple-ios-sim/release/libpoki_launcher.a` (copy it from a checkout
that has built it) and `native/ios-app/scripts/make-assets.sh` run once.

## The switch

General › Testing Options › Experiments › Work in the Background. It is off by default. While it is
on, agents get a `background` tool next to `look` and `do`.

## The probe (no model, runs the tool as an agent would)

Install Poki Lab and the fixture (`experiments/background-ax-probe`, target AXFixture, bundle
`local.pokimcp.axfixture`) on a booted simulator, then:

```bash
X="$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer"
SIMCTL_CHILD_POKI_SIMULATOR_DEVELOPER_DIR="$X" SIMCTL_CHILD_DYLD_FRAMEWORK_PATH="$X/Library/Frameworks:$X/Library/PrivateFrameworks" SIMCTL_CHILD_DYLD_LIBRARY_PATH="$X/usr/lib" xcrun simctl launch booted nz.zheha.poki.lab -pokiInProcess background
```

It turns the switch on for the run. Results go to Poki Lab's `Documents/inprocess-probe.json`
(one entry per step, `"step": "verify"` entries carry PASS or FAIL). On a fresh simulator the first
launch can fail at prepare while testmanagerd starts; launch again.

## What the answers say

- `done_in_background`: the step ran and the app's tree changed, with the app kept behind the one in front.
- `needs_front`: the step did not take effect in the background. Nothing changed, so the agent does it with the normal `do {app, actions}`, which brings the app forward. It is never retried in the background.
- An error line: the tree was not read (the app was never seen in front this session, or it quit). Use `look` and `do`.

## Simulator result (Nov 23 2026, iPhone 17 Pro, iOS 27.3)

With Settings in front the whole run and 0 foreground jumps during the background steps:

Works in the background
- Reading the app's elements (about 0.1 s)
- Back on a navigation stack
- Setting a text field's value (does not submit)
- Scrolling a list by a page
- Alert and action sheet buttons, and Escape to cancel them
- Controls that have an accessibility action: SwiftUI Button and Toggle, bar button items, custom accessibility activate, swipe actions and More Info (custom actions)

Falls back to the front (`needs_front`)
- Plain UIButton, UISwitch, UIStepper, tab bar items, row selection, menus, tap gestures, submitting text

## Known limits

- A push started in the background shows its new screen in the tree but stays mid-transition until the app comes forward, so a back right after a background push answers `needs_front`. Back from a screen reached in front works.
- Poki needs to have seen the app in front once this session (its pid comes from Poki's own reads).
- Only measured in the simulator in Poki Lab. The same testmanagerd route answered on the phone in the earlier probe runs, but Poki Lab itself has not run on the phone.
