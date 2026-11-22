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

## Second round on the phone, 2026-11-22 03:59-04:13 ET: it works

Questioning the first round: its helper never read Calculator in the foreground either. Run C showed the
helper's own snapshot (`XCAccessibilityElement elementWithProcessIdentifier:` + `requestSnapshotForElement:...`)
times out even with Calculator frontmost, so the 03:44 "fail" was a probe bug, not iOS. Raw lines:
`device-run-results-2.txt`.

- **D (04:04):** the helper's call took 65 s and failed with `XCTFuture Code=1000 "Timed out while fetching snapshot from testmanagerd.."`, foreground and background alike. XCTest's public `XCUIApplication(bundleIdentifier:).snapshot()` of the same Calculator returned **44 elements in 82-91 ms, also in the background** (Calculator state 3, Settings 4).
- **E (04:06):** the public snapshot is live in the background at +1/+5/+30/+120 s (44 elements, 55-154 ms). Keys are element type 20 (`.key`), not buttons.
- First press attempt crashed in `-[XCAXClient_iOS performAction:onElement:value:error:]` (`objc_retain` of 0x7da = 2010): the action argument is an object. Type encoding `B48@0:8@"XCUIAccessibilityAction"16@"XCAccessibilityElement"24@32^@40`. Fixed with `[[XCUIAccessibilityAction alloc] initWithAXAction:2010]`.
- **E (04:10-04:12), with Settings frontmost the whole time** (state 4 at every mark, the end screenshot shows Settings, the status bar shows "◀ Calculator"):

| Mark | Calculator state | Snapshot | Action (by element) | Display read in the background |
| - | - | - | - | - |
| +1 s | 3 running background | 44 elements, 55 ms | AXPress "7" ok=true | 1 -> **7** |
| +5 s | 3 | 44, 64 ms | AXPress "8" ok=true | 7 -> **78** |
| +30 s | 3 | 44, 85 ms | AXPress "9" ok=true | 78 -> **789** |
| +120 s | 3 | 44, 90 ms | AXPress "4" ok=true | 789 -> **7,894** |
| verification (foreground, one-off) | 4 | | | **7,894** |

**Result: an unchanged, original Calculator, kept running in the background by testmanagerd's background
assertion, was read and operated by accessibility element (no touch, no coordinates, no screen) while
Settings stayed in front.** Mechanism: `_XCT_requestBackgroundAssertionForPID:reply:` +
`XCUIApplication(bundleIdentifier:).snapshot()` + `-[XCAXClient_iOS performAction:(XCUIAccessibilityAction)onElement:value:error:]`.
Still to test: concurrency with the owner using the handset, text entry, apps other than Calculator,
and how long the assertion lasts.

## Concurrency with the owner using the phone, 2026-11-22 04:20-04:26 ET

Raw lines: `device-run-concurrency.txt`. The owner used the handset for about 5 minutes (another app at
+11-65 s, Notes around +65-110 s, then Settings from +247 s) while the probe pressed one digit every
~10 s in the background Calculator by accessibility element and read the display back.

- **28 of 28 presses landed and were verified on the background display** (2 -> 23 -> ... -> 2,345,678,912,
  cleared by element, then 3 ... and 4 ... -> 45,678,912). Each press plus read-back: 660-880 ms.
- Calculator stayed `runningBackground` (3) throughout and never came forward. The owner reported
  nothing odd on the handset: no flicker, no Calculator appearing, no misdirected touches.

## Generality, background Settings with Notes in front, 04:26-04:27 ET

Raw lines: `device-run-generality.txt`.

| Test | Result |
| - | - |
| a) navigation | AXPress on the "General" cell in the background Settings **opened General** (the next read lists About, Software Update, iPhone Storage, ...). The "About" press returned ok, but the next read 2 s later still showed General: unresolved (wrong element matched, or the push had not finished). |
| b) text entry | `setAttribute:value:element:` with attribute `XC_kAXXCAttributeValue` **set the Settings search field to "wifi"**, read back in the background. `AXValue`, `2006` and `AXValueAttribute` gave `kAXErrorIllegalArgument`. |
| c) scrolling | My guessed action numbers did not scroll: 2018 returned ok with no change; 2019, 2020, 2021 and 2008 returned `kAXErrorFailure`. The correct scroll action ids still need finding. |

Notes stayed `runningForeground` (4) and Settings `runningBackground` (3) throughout.

## Round 3 on the phone, 2026-11-22 04:30-04:33 ET

Raw lines (third-party labels redacted): `device-run-round3.txt`. Action ids taken from XCUIAutomation 27.3,
not guessed: `+[XCUIAccessibilityAction scrollToVisibleAction]` = 2003, `incrementActionForPlatform:` = 2004,
`decrementActionForPlatform:` = 2005. 2006/2007 as page down/up were a hypothesis.

| Test | Result |
| - | - |
| H1 scroll, background Settings | 2006, 2007 and 2003 all returned ok=true, but the tree's first and last labels did not change. **No scrolling observed.** The tree may already hold the whole list (Settings' first list), so this does not separate "scroll ignored" from "nothing to scroll". Open. |
| H2 two-level navigation | General opened (nav bar "General", back button and About cell present at +2, +10, +30 s, so the first push completed). The About cell (type button) from a **fresh** read after 30 s returned ok=true, but the tree still showed General at +2 and +10 s. Hypothesis (a), a stale element, is ruled out. Open between (b) the second push not completing and (c) the cell needing another action. |
| H3 attach to a background-launched app | Calculator killed, then launched from the Mac with `devicectl device process launch --no-activate`. It never came to the front (state 2, then 3 once the assertion took). The test attached by bundle id without launching it: assertion granted, read 39-40 elements, **press 5 -> 5, press 5 -> 55**. **Poki does not need to flash the target forward.** |
| H4a LookUp (third-party) | Background read with Settings in front: 72 elements (word list, tab bar). The tab-switch press was not attempted: my filter found no button children in the tab bar. |
| H4b Notion (third-party, web-view heavy) | Background read with Settings in front: **354 elements, including the owner's page titles**. No tab bar found. No press. |

The probe runner was uninstalled after the run.

## Round 4 on the phone, 2026-11-22 04:35-04:37 ET

| Test | Result |
| - | - |
| Scrolling, background Settings root | **Works.** Action 2006 on the collection view (type 32): visible cells 11 -> 16, first cell frame y 168 -> -25, so the list moved down a page. 2007 moved it back up (first y 542). Scroll-to-visible (2003) on the last cell moved it again (first y -389). Round 3's "no change" was my probe comparing labels, which are empty on these cells. |
| Navigation, two levels | General opened (nav bar "General"). Pressing the "Settings" back button failed with `kAXErrorFailure`. **After waiting 60 s, the About row opened About** (nav bar "About"). In round 3 the same press after 30 s did not. Pressing About's non-actionable children failed with `kAXErrorFailure`. Working hypothesis: the first push's transition takes 30-60 s to finish in the background, and a second push waits for it. Not confirmed (no app-side logs). |
| Notes, two levels | Not tested: Notes was open on a note, with no cells to press. |
| LookUp tab switch | Tab items found under the tab bar (buttons with image children). AXPress failed with `kAXErrorFailure` on both an image and a tab button. Open. |

The probe runner was uninstalled after the run.

## Round 5 on the phone, 2026-11-22 04:41-04:47 ET: back and tab actions

- XCTest's `XCUIAccessibilityAction` descriptions on 27.3 carry no names (`AXAction:2000` ... `AXAction:2069`), and the phone's AXRuntime exports none of the likely `kAX...Action` symbols by name (dlsym found none). So no action name could be read from the binaries on this phone.
- A measured sweep of actions 2011-2040 on the background Settings General page (app element, navigation bar, "Settings" back button): ok=true for 2013-2016, 2018, 2022 and 2024, but **none popped back to the root** (nav bar stayed "General"). **Action 2025 on the app element crashed Settings** (crash log Preferences-2026-11-22-044517.ips).
- The same sweep on LookUp's "Collect" tab button and its tab bar: 2010 (press) failed, and nothing changed the selected tab. **Action 2025 crashed LookUp** (LookUp-2026-11-22-044659.ips). Increment/decrement on the tab bar: no change.
- Both apps relaunch normally. No data was created or changed. The probe runner was uninstalled.
- Conclusion: back buttons and tab bar buttons in a background app are not operable by AX action on 27.3 with the actions found. **Do not sweep unknown action numbers again: 2025 crashes apps.**
