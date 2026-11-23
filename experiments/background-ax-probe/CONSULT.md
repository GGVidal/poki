# Consultation request: operating touch-only UIKit controls in a background iOS app

## Goal

We're building an iPhone agent that, with the user's consent, operates another app while that app stays in the
background and the user keeps using a different app in front. The background app must never be brought forward,
not even briefly. We drive it from an XCTest UI-test runner and the system's `testmanagerd`. That is Apple's
supported automation channel, and it works on a real device with developer mode.

We need these to work in the background: plain UIKit buttons, switches, table and collection rows, tab bar items,
menus, and web pages. We're asking for routes we haven't tried, or a reason one of our closed routes isn't really closed.

## Environment

- iOS 27.3 (simulator runtime 27.3, iPhone 17 Pro; also a physical iPhone 17 Pro on 27.3, used sparingly).
- Xcode with XCTest. The runner talks to `testmanagerd` through `XCTRunnerDaemonSession.daemonProxy`.
- The target is our own test app (UIKit plus SwiftUI plus WKWebView). The approach must later work on apps we don't control.
- Constraints: no jailbreak, no entitlements a normal developer can't get, no foreground round trips, and no
  synthesized screen touches. Those would land on the front app.

## What already works in the background (other app in front)

- **Keeping the app alive:** `_XCT_requestBackgroundAssertionForPID:reply:` keeps the target running (not suspended).
  XCTest snapshots and accessibility actions keep working.
- **Navigation back:** action 2013 (escape) on the navigation bar is accepted, but the pop is held as a deferred
  transition until a layout pass. Reading parameterized attribute 95005 (the in-app accessibility audit) with
  `{"AXAuditClippingTest": {"AXAuditShouldRunTestOption": true}}` forces that layout pass and releases the pop.
  On the phone, this only works through testmanagerd's `_XCT_fetchParameterizedAttributeForElement:attributes:parameter:reply:`
  (NSNumber attribute). The runner's own direct AX call is refused there ("Permission denied" looking up
  `com.apple.iphone.axserver`). Confirmed on the physical phone.
- **Controls with their own accessibility activation:**
  - UIBarButtonItem: UINavigationBar's accessibility calls the item's action directly.
  - UISegmentedControl, UIPageControl, UISlider and UIStepper: increment and decrement.
  - Text field: setting the value works.
  - Scrolling: actions 2003, 2006 and 2007.
- **SwiftUI:** Button, Toggle, segmented Picker, Stepper, Slider, NavigationLink, and alert buttons, via 2010 or 2004.
  SwiftUI implements accessibility activation itself.
- **Web pages (simulator only so far):** take a web element's AXUIElement while the page is visible and keep it. After
  backgrounding, the runner's direct `AXUIElementCopyAttributeValue` and `AXElement performAction:withValue:` on it
  still work. We can walk the whole page tree (85 elements), press buttons, toggle checkboxes, and press elements
  created after capture. It stays alive for at least 2 minutes. The same press through testmanagerd fails with
  `kAXErrorServerNotFound`. Fresh snapshots no longer include the page, because the host's `AXRemoteElement`
  is built with the WKContentView's window context id, which is 0 in the background.

## What doesn't work, and why we think so

1. **Plain UIButton, UISwitch, UITableViewCell, UICollectionViewCell, UITabBarButton, and SwiftUI tap gestures.**
   UIKit has no accessibility activation for them. 2010 returns `kAXErrorFailure` even in the foreground. VoiceOver,
   Switch Control and FKA all fall back to a touch (`-[AXElement press]` = activate, otherwise a touch at the
   activation point). The in-app touch helper `-[NSObject(AccessibilityActivation) _keyboardActivate]` builds an
   IOHID digitizer event carrying the window's context id and enqueues it in-process.
2. **The window has no render context in the background.** On scene suspend, `-[UIWindowScene _prepareForSuspend]` →
   `-[_UIContextBinder purgeContextsWithPurgeAction:afterPurgeAction:]` disposes the window's CAContext. The context id
   becomes 0, and `_UIEventHIDUIWindowForHIDEvent` drops any event whose context id doesn't resolve. Teardown is
   skipped only if one of these is set:
   - the binder's `contextManagementPolicy` ≠ 0, via `-[UIWindowScene _setKeepContextAssociationInBackground:]`;
   - `-[UIWindow keepContextInBackground]`;
   - `_alwaysGetsContexts`, true only for UIKit-internal window classes;
   - `+[UIWindow _setAllWindowsKeepContextInBackground:]`.

   When our own test app sets one of these on itself, the plain button fires in the background. In a normal app nothing
   sets them. No accessibility attribute or action, scene setting, launch option or user default reaches them.
   `-[UIWindowScene _permitContextCreationForBindingDescription:]` also allows contexts when the scene is
   active, activating or "suspended events only" (a deactivation reason UIKit sets itself), or responding to a lifecycle event.
3. **Things tried that left the context at 0** (sampled every 0.05–0.3 s):
   - silent push, dark/light mode, Dynamic Type change, increase contrast, memory warning, rotation, app switcher;
   - 5310/5313 FKA scene actions and every audit option;
   - snapshot refresh;
   - `FBSSystemService openApplication` with `__ActivateSuspended` from the runner: refused, "Request is not trusted".
4. **Focus plus keys:** the focus system is disabled when the scene isn't active, and 2044 (set native focus) is refused
   in the background. Action 2034 (key event) runs key commands in-process, but modifiers are dropped (only
   `unmodifiedInput` is used). Space or Return on a focused button selects nothing, even in the foreground.
5. **Covered states:** when the target is foreground-inactive (Control Center or app switcher over it), the context
   survives and the in-process tap works. But that covers the user's screen. Notification Center backgrounds the app.
6. **Menus:** a SwiftUI Menu opens in the background and its item appears in the tree, but 2010 on the item fails.
   Cells with context menus expose their actions as accessibility custom actions (performable with 2021), but
   UIButton.menu and UIBarButtonItem.menu don't.
7. **testmanagerd** can launch suspended (`FBSOpenApplicationOptionKeyActivateSuspended`). Only its
   `_XCTD_launchRemoteRunnerWithBundleID…` path does that; the XCTestSession API we have doesn't.
   `devicectl --no-activate` exists, but an app launched that way has never been foreground, so its context is presumably never created.

## Questions

1. Is there any supported or developer-reachable way to keep, or briefly recreate, a background app's window CAContext,
   so an in-process touch can land? Some lever in FrontBoard scene settings, RunningBoard, a debug or automation mode
   (`com.apple.dt` defaults, XCTest automation-mode flags, `DYLD_` or `MallocStackLogging`-style launch environment),
   or an assistive-technology mode?
2. Is there any path that calls `UIControl sendActionsForControlEvents:` or `performPrimaryAction`, or a table/collection
   delegate's `didSelect`, from outside the process without a touch? Accessibility, key commands, menu actions,
   drag and drop, Shortcuts/Intents, UIScene actions, state restoration, handoff, a URL scheme?
3. Could a touch be delivered in a context-free way? For example, routing the HID event by pid or scene identity rather
   than context id, or through an `XCSynthesizedEventRecord` with a display or scene target?
4. For web content on a real device: the runner's direct AX call to the app's `com.apple.iphone.axserver` is refused on the
   phone. Is the WebContent process's AX server reached through the same lookup, or through a port carried in the
   AXRemoteElement token (`setMachPort:`)? Can testmanagerd be made to address a WebContent pid? Its
   `_performWithRetries:untilAXServerFound:` says server not found.
5. Is there any other on-device trusted launcher or scene client a developer can use (Xcode/devicectl appservice,
   `XCTDRemoteAutomationSession`, Instruments), so an app can be launched or kept "foreground but not visible",
   for example on a virtual display or occluded?
6. Anything we've misread: a gate above that a normal developer can actually open, or an assumption that's wrong.

## Evidence

Detailed logs, the disassembly notes and the test code are in `experiments/background-ax-probe/RUN.md` and
`SimProbeUITests/*.swift` (branch `dev/background-ax-probe`, latest pushed commit f9a84b20; newer work is uncommitted).
