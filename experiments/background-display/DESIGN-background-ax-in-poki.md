# Design note: background accessibility through Poki's in-process XCTest session

Status: reading only. Nothing here is built or run. Running it needs the owner's yes,
first in the simulator, then separately for a phone build. Base read: `dev/test-build-047`
at 478b9ed2, `native/ios-app/Poki/Native/InProcess.m`.

## What Poki already has

`InProcess.m` already talks to testmanagerd the way this needs:

- `[NSClassFromString(@"XCTRunnerDaemonSession") sharedSession]` -> `-daemonProxy`, then calls
  `_XCT_*` methods on the proxy directly: `_XCT_launchApplicationWithBundleID:arguments:environment:completion:`,
  `_XCT_terminateApplicationWithBundleID:completion:`, `_XCT_synthesizeEvent:implicitConfirmationInterval:completion:`,
  `_XCT_requestScreenshotOfScreenWithID:withRect:uti:compressionQuality:withReply:`,
  `_XCT_requestBundleIDForPID:reply:`.
- `-[XCUIDevice accessibilityInterface]` (an `XCAXClient_iOS`), and
  `PKRequestSnapshotWithin(seconds, ax, element, maxDepth, maxNodes, &code)` around
  `requestSnapshotForElement:attributes:parameters:error:`, with a per-pid hang guard.
- What it lacks: it only picks elements from `activeApplications` / `systemApplication`
  (on-screen apps), and it never acts by accessibility. Actions are synthesized touches.

## What would be added (about 60 lines in `InProcess.m`, no new entitlements)

1. **Keep the target running.** On the same daemon proxy:
   `- (void)_XCT_requestBackgroundAssertionForPID:(int)pid reply:(void (^)(BOOL))reply;`
   Type encoding in Xcode 27.3 XCTestCore: `v28@0:8i16@?<v@?B>20`. testmanagerd turns it into
   `BKSProcessAssertion(pid, flags 11, reason 7)` (LOG.md section B). This is the same call
   `-[XCUIApplicationProcess acquireBackgroundAssertion]` makes for a UI test's own app.
2. **Address the background app without the screen.** Build its application element from the pid:
   `+[XCAccessibilityElement elementWithProcessIdentifier:]` (XCTAutomationSupport and XCUIAutomation
   both export it). Read it with the existing `PKRequestSnapshotWithin(...)`. The snapshot carries
   child `accessibilityElement`s.
3. **Act by element, not coordinate.** Either on the AX client:
   `-[XCAXClient_iOS performAction:onElement:value:error:]` (in XCUIAutomation 27.3), or on the
   daemon proxy: `_XCT_performAccessibilityAction:onElement:withValue:reply:`. The action is AXPress
   (2010 in AXRuntime numbering, to be confirmed by the probe). Values via `_XCT_setAttribute:value:element:reply:`.
4. **Read back** with a fresh snapshot of the same element. Nothing is drawn, the handset front app is
   untouched, and no touch is synthesized.

New MCP surface (sketch): `background_read(bundle_id|pid)`, `background_press(pid, element_ref)`,
`background_set_value(pid, element_ref, text)`, each refusing if the handset's front app changed
during the call.

## Identity and constraints

- The target is the original installed app, addressed by pid/bundle id. Nothing is copied, re-signed,
  injected or instrumented. No debugger.
- A testmanagerd process assertion is visible to the system (RunningBoard). The app sees that it is
  still running in the background, the same as during any UI test.
- Needs Poki's existing UI-automation setup (Developer Mode, UI Automation enabled), which Poki
  already requires.

## Open questions the simulator probe answers first

- Does a background app's in-process accessibility server answer snapshot requests when kept running
  by the assertion, and how fast (the probe reads at +2/+15/+40 s)?
- Does AXPress through `performAction:onElement:value:error:` change state in a non-frontmost app?
  (The audit service's press did nothing even in the foreground. This is a different path.)
- Does iOS revoke or limit the assertion (time limit, thermal, memory) on a phone?
