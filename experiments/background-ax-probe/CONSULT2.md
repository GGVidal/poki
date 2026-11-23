# Consultation request 2: background iOS app control, after the first round of advice

This follows our first request: operating controls in an iOS app that stays in the background while the user uses
another app in front. The setup, constraints and closed routes from that request still hold:

- iOS 27.3 (simulator, and a physical iPhone 17 Pro).
- We drive the target from an XCTest runner and testmanagerd.
- No jailbreak, no unobtainable entitlements, and the target is never brought forward.
- No synthesized screen touches. They land on the front app.

Below is what we learned since, and the questions that are now open.

## New facts

### Web content (simulator)
- **Kept handle works.** A WKWebView element's AXUIElement, taken while the page was visible and kept, still works after the
  host is backgrounded. Through it the runner's direct AX calls can:
  - walk the whole page (85 elements);
  - press buttons and toggle checkboxes;
  - press buttons the page created after capture.

  Presses fired at 0, 30, 60 and 120 s. The element's pid is the WebContent process. The host's context id is 0.
- **Without a kept handle, the page is unreachable.** A walk from a fresh app element in the background stops at the host:
  - the page never appears;
  - the reason is that the host's `AXRemoteElement` is built with `initWithUUID:andRemotePid:andContextId:` using the WKContentView's context id, which is 0.
- **Navigation kills the handle.** After a link navigates, the kept root no longer reaches the new document.
- **These failed through the kept handle:**
  - setting a `<select>` value (accepted, unchanged);
  - pressing the select (fails, no options exposed);
  - scrollToVisible 2003 (accepted, page didn't scroll).
- **Text input is unresolved.** Setting value 2006 on an `<input>` returned success, but the value stayed empty and no input event fired.
- **testmanagerd can't reach it.** The same press through testmanagerd's perform-action fails with kAXErrorServerNotFound after 30 retries.
  `setAttribute:value:element:` fails with error 12. A parameterized read timed out. One run lost its XCTest authorization after those calls.

### The broker (`com.apple.accessibility.axAuditDaemon.remoteAXService`, read from AccessibilityPlatformTranslation)
- **Action table.** `-[AXPTranslator_iOS processActionRequest:]` maps actionType to a fixed native action.

  | actionType | Native action |
  | - | - |
  | 1 | 2005 decrement |
  | 2 | 2013 escape |
  | 3 | 2004 increment |
  | 4 | custom action 2021 (identifier from parameters) |
  | 5 | `-[AXElement press]` |
  | 6–9 | 2006, 2008, 2009, 2068 |
  | 10 | 2031 |
  | 11 | `scrollToVisible` |
  | 12–17 | 2007, 2051, 2025 (crashes apps), 2011, 2019, 2020 |

  There's no plain 2010 and no arbitrary action id.
- **What `-[AXElement press]` does (AXRuntime 27.3).**
  1. If `canPerformActivate`, it calls `_performActivate` and stops on success.
  2. Otherwise, if `visiblePoint` is (-1,-1), it sends `performAXAction:2010`.
  3. Otherwise it calls `simulateTapWithFingerIndex:withPoint:centerPoint`, a real touch on the front app.

  So press is safe only for elements whose activation succeeds: web, SwiftUI, bar items.
- **Our existing reader.** Our product already reads phone screens through this broker from the Mac over the developer tunnel (DTX, no XCTest).
  It reads any process's tree by pid (requestType 1 with `{pid}`, then 2), including WebContent processes, whose pids it learns from screen hit tests.
  It has never sent actions.

### SwiftUI and UIKit (simulator)
- **SwiftUI works in the background.** Button, Toggle, segmented Picker, Stepper, Slider, NavigationLink, showing an alert and pressing its buttons.
- **Not working:**
  - a SwiftUI Text row with only `onTapGesture`;
  - SwiftUI Menu items (the menu opens and its items appear, but 2010 on an item fails);
  - menu type-select via key events: typing a letter then Return through action 2034 doesn't select or run an item, even in the foreground.
- **Plain UIKit is unchanged.** UIButton, UISwitch, table rows and tab bar items have no accessibility activation, and the background window has no CAContext.
  In the simulator we sampled the context id every 0.05–0.3 s through the app switcher, rotation, dark mode and other system changes. It never became non-zero.
  A hidden launch via FBSSystemService from the runner was refused ("Request is not trusted").

## Questions

1. **Reaching a never-visible or navigated page.** WebKit registers UI-process tokens (UUID and pid) and the web process creates
   `WKAccessibilityWebPageObject` eagerly. Is there an authorized way to get the web process's AX root without the host's
   context-derived bridge? For example: AXUIElement for the WebContent pid's application element, a known object id for the page
   object, the broker's requestType 1 with the WebContent pid, or an AX notification payload that carries the remote element.
2. **Is the broker allowed to act on a background process on device?** Does requestType 1 or 7 apply a frontmost-app or
   current-apps filter (we suspect something like the audit's "Invalid target app" check), and what does error 17 mean in this stack?
3. **Web form controls through AX alone.** For WebCore's iOS wrapper, which attributes or actions set an `<input>`'s value with
   real input/change events, choose a `<select>` option, or scroll the page? For example `_accessibilitySetValue:`, inserting text
   2055, text operations 2012, increment and decrement on a select. Setting 2006 returned success with no effect.
4. **Why testmanagerd says "server not found" for a WebContent element.** Which lookup in `_performWithRetries:untilAXServerFound:`
   fails for a non-app pid? Is there a testmanagerd selector that takes the element with the host application separately?
5. **Plain UIKit controls, again.** Given the facts above, is there any external caller into `sendActionsForControlEvents:`, a
   table's `_userSelectRowAtPendingSelectionIndexPath:` or a tab bar's selection that doesn't need a touch? Or any authorized way
   to keep or recreate a background window's CAContext, such as a scene setting a developer service can set, an automation
   mode, or an assistive-technology client mode?
6. **SwiftUI menu items.** Why does activation fail on a presented SwiftUI Menu item, while SwiftUI Buttons elsewhere activate?
   Is there an attribute, custom action or escape path that runs the item's action?

## Evidence

The repo is branch `dev/background-ax-probe`, folder `experiments/background-ax-probe`:

- `RUN.md`: logs and disassembly notes.
- `SimProbeUITests/*.swift`: the tests.
- `axbroker/PLAN.md`: the phone plan.
