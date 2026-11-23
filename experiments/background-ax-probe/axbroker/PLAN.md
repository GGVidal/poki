# Phone test plan: web press through axauditd's remoteAXService (not run; needs the owner's yes)

## What the broker can do, from Apple's code (simulator runtime 27.3)

### actionType map

`-[AXPTranslator_iOS processActionRequest:]` maps `actionType` to a native action:

| actionType | native action |
| - | - |
| 1 | 2005 decrement |
| 2 | 2013 escape |
| 3 | 2004 increment |
| 4 | 2021 custom action (identifier from `request.parameters`) |
| 5 | `-[AXElement press]` |
| 6 | 2006 |
| 7 | 2008 |
| 8 | 2009 |
| 9 | 2068 scroll to top |
| 10 | 2031 |
| 11 | `scrollToVisible` |
| 12 | 2007 |
| 13 | 2051 |
| 14 | 2025 (crashes apps: never send) |
| 15 | 2011 |
| 16 | 2019 |
| 17 | 2020 |
| out of range | the same path as actionType 4 |

There's no actionType that sends a plain 2010 without the press fallback.

### What `-[AXElement press]` does (AXRuntime)

1. If `canPerformActivate`, it calls `_performActivate`. On success it stops there.
2. Otherwise it reads `visiblePoint`:
   - (-1, -1): `performAXAction:2010`.
   - Anything else: `simulateTapWithFingerIndex:1 withPoint:centerPoint`, a real touch on screen that lands on the front app.

So a press is safe only if activation succeeds. Web elements and SwiftUI buttons activate themselves; plain UIKit controls don't, and must never get actionType 5.

## What Poki's client does today

- `native/launcher/src/ax_direct.rs`, from the Mac over the developer tunnel (RSD + DTX).
- `application(pid)` sends requestType 1 with `parameters = {pid}` and keeps the reply's archive objects whole.
- `snapshot()` sends requestType 2.
- `tree_of(pid)` reads any process by pid, including a WebContent pid.
- WebContent pids are learned from hit tests (requestType 6) at screen points, and `learn_host` maps them to the host app.
- Every request carries `actionType 0`. Nothing sends actions yet.

### Minimal change for an action

Add `act(objects, token, action_type, parameters)`. It mirrors `application()`, with:

- `requestType 7` and `actionType N`;
- `translation` set to the element token kept verbatim from the snapshot archive, with every object it refers to;
- `parameters` only for the custom-action case.

Read `resultData` (a boxed bool) from the reply.

## Phone steps (each one needs approval)

1. Install the fixture `local.pokimcp.axfixture` and a blank app of our own with a non-interactive screen, so a stray tap does nothing. Use the existing signing overrides, nothing committed.
2. Open the fixture on the Web tab once, then bring the blank app to the front.
3. Hold the testmanagerd background assertion on the fixture and on its WebContent pid. The pid comes from the broker's hit test while the page is visible, or from the process list.
4. Through the broker (Mac side, developer tunnel):
   1. requestType 1 with the WebContent pid, then requestType 2, then find "WebButton".
   2. Read its label with requestType 5.
   3. Send actionType 5 (press) once. Web activation succeeds in the simulator, so there should be no tap. The blank app in front absorbs any stray tap.
   4. Read the label again. Expect "WebButton clicked 1".
5. Control: nav bar Back with actionType 2 (escape), then the audit kick. That's the known working route.
6. Record throughout: the fixture's context id is 0, the blank app stays frontmost, and the fixture's state stays background.
7. Cold case: relaunch the fixture without ever showing the Web tab (the page then doesn't exist; expected nothing). Then a variant where the fixture creates the web view at launch while hidden, looked up by WebContent pid.
8. Uninstall both apps and confirm.

Phone-side actions, in full: install 2 apps; launch the fixture; tap the fixture's Web tab once (setup, foreground); launch the blank app; background assertions; broker reads; at most 2 web presses; 1 escape; uninstall 2 apps. No settings changed.

## Update (RAW 61): two phone runs

### Run 1: XCTest/testmanagerd route only, no broker
Everything goes through testmanagerd, since the runner's direct AX is refused on the phone. All of these are verified in the simulator through testmanagerd:
- Custom actions: fetch them with `attributesForElement:attributes:` on `XC_kAXXCAttributeCustomActions`, then call `performAction:onElement:value:` with action 2021 and the action dictionary returned by that fetch as the value:
  - table row swipe "Flag" fired;
  - table row "More Info" fired (`accessoryButtonTapped`);
  - list cell "More Info" fired (the detail handler).
- SwiftUI Button, Toggle and segmented Picker with 2010, and the Slider with 2004.
- UIPageControl with 2004.
- Text field: `setAttribute` with `XC_kAXXCAttributeValue`.
- UIKit UIStepper with 2004 returned true but no handler ran, so it's excluded.

Phone-side actions:
1. Install the fixture and runner (signing overrides only).
2. Launch the fixture normally and open the Lists tab (setup, foreground).
3. Bring Settings or our blank app to the front.
4. Take the background assertion.
5. Send the actions above, once each, plus the back button (2013 and the audit kick) as a control.
6. Read the counters back.
7. Uninstall both apps.

### Run 2: broker, read-only first
Uses Poki's existing reader (`native/launcher/src/ax_direct.rs`), from the Mac over the developer tunnel.
1. Show the fixture's Web tab with page A, then put Settings or the blank app in front.
2. Hold background assertions on the fixture and its WebContent pid.
3. Run a type-1 lookup of the WebContent pid, then a type-2 snapshot. Look for page A's marker.
4. The fixture navigates to page B by itself after a timer (our own fixture). No press.
5. Take a fresh type-2 snapshot and check whether B's marker appears. Note whether the WebContent pid changed.
6. No broker press in this run. A later press run needs the owner's separate yes.

Rules: never send a broker press to a plain UIKit control, and records omit pairing material, tokens and device identifiers.
