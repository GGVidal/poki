# iPad workspace: morning status, Nov 23 2026, 7 am ET

Experimental (issue #689). Poki Lab build only (`native/ios-app/project-lab.yml`, bundle id
`nz.zheha.poki.lab`). Nothing here reaches alpha, beta, pre-alpha or a release, and there is no pull
request into `main`.

## Real iPad, Nov 23 2026, 9:30 to 9:57 am ET (Mac Studio)

iPad Pro 13-inch (M5), iPadOS 27.0. Poki Lab (`project-lab-device.yml`, bundle `nz.zheha.poki.lab`)
installed from the Mac Studio at 9:34 am ET; never an alpha or beta build.

- **Virtual display.** The CoreDevice display service gives display 3 "Wireless", 1920x1088. A screen
  mirroring icon appears in the status bar. Captures of it are solid black (max pixel 0) in every case
  below, and Display & Brightness shows no section for it.
- **Software keyboard.** CoreDevice's own keyboard capability types text but does not count as a
  hardware keyboard. A generic boot keyboard made with UniversalHID `createService(properties:)`
  (page 1, usage 6) does count (the Hardware Keyboard row appears and the on-screen keyboard hides),
  but its reports never take effect.
- **Software mouse.** CoreDevice's pointer capability is refused on iPadOS 27.0. A generic relative
  boot mouse through `createService` (page 1, usage 2) makes Trackpad & Mouse appear in Settings, but
  its reports never move anything and no cursor shows. UniversalHID's strings ("no active virtual
  service; dropping events", `HIDVirtualServicePool.enabledDeviceTypes`) suggest the services are
  published but never activated, and the CoreDevice protocol has no enable call.
- **Stage Manager** turned on, display recreated after both generic devices existed: still black.
- **Display kinds.** CoreDevice 699.2 offers virtual external, virtual secondary, and two mirrored
  kinds. External 1920x1088, secondary 1920x1088 and external 2560x1440 all came up as display 3,
  type wireless, black, with no Settings section.
- **Check Displays inside Poki Lab (10:09 am ET).** Settings rows made reachable on device in
  41b2458f (Agents, Experimental). Result: testmanagerd lists display 3 (1920x1088, not main) but
  returns no picture (pictureBytes 0). UIKit has one UIScreen only (main, 1376x1032 points) and one
  application scene session, so display 3 is not exposed to apps and no external display scene role
  exists.
- **Conclusion.** iPadOS does not treat CoreDevice's virtual display as a real display: no UIScreen,
  no picture, no Settings section, black even with Stage Manager and generic HID devices present.
  Wireless displays appear to be mirror only on iPadOS. A wired display or an HDMI dummy plug is the
  only known route to an extended desktop, and the LabDisplay layer still needs one to be tested.
  SpringBoard's own log line for display 3 is unread (needs the owner's `sudo log collect`).
- **Why it mirrors (iPad log, 10:00 am ET).** The CoreDevice display is a FigVirtualDisplay
  (AirPlay machinery). backboardd tags it "(AirPlay)", sees MirroringMode 0, and clones the LCD to it.
  SpringBoardFoundation `-[SBExternalDisplayDefaults displaySupportsExtendedDisplayMode:]` lets a
  display that is not wired extend only when the SpringBoard default `allowWirelessDisplays` is YES
  (internal prototype setting; see also `SBExtendedDisplayOverrideSupportForAirPlayAndDontFileRadars`).
  No Developer setting, profile key, feature flag or devicectl command sets it. Writing it would be a
  system modification and was not done.
- **AirPlay to the Mac Studio (10:14 am ET)** behaves the same: display 4, 3840x2160, wireless,
  mirrored, no UIScreen, no picture.
- **HID.** dtuhidd decodes UniversalHID's own KeyboardReport/PointerReport types by report id and
  drops boot-protocol reports; sending those types is the next HID step.
- **Earlier reading.** Keyboard and pointer presence is not enough; the virtual display itself may be
  the wall. Next: the display service's other modes and options, SpringBoard's log for display 3, and
  whether Poki Lab sees a UIScreen or scene session for display 3 so it could put its own window there.

## Works, shown on simulators

- **iPhone to iPad link through your relay.** Two Poki Lab simulators on the Mac (iPad as host,
  iPhone as client) and the relay Worker under `wrangler dev` with a throwaway secret, 6:53 am ET.
  The relay log shows the whole path: iPad WebSocket 101, then from the iPhone register 201,
  authorize 302 after Poki on the iPad asked for consent, token 200, MCP initialize 200 and 202.
  Then `status` answered in 25.7 s (the first call, which includes starting the iPad's automation
  session), `look` in 3.2 s, and `status` again in 0.3 s, all on one MCP session.
- **Unit tests.** `WorkspaceLinkTests` 9 of 9 on the Mac. Whole PokiCore suite 354 of 356; the two
  failures are `SoakTests` deadline timing on a loaded Mac and do not involve this code.
- **Build.** The Poki Lab simulator build of this branch (at 7ea6d625) succeeded with no fixes.
- **Relay end to end on Linux.** The same link client against the real relay Worker and
  `deploy/cf-relay/test/phone-sim.mjs`: OAuth, two calls on one session, and a wrong secret refused.

- **`do` through the link.** A `do` launching Settings on the iPad went through and Settings opened,
  but the read after it timed out on the loaded simulator, so the call answered an error. The do
  path's read deadline needs a look.
- **Display mode safety on the simulator (7:24 am ET).** Workspace Display found display 2
  (720x480) beside the main one. Check Displays got no picture from it. With it chosen, tree,
  screenshot and Home were refused and nothing reached the main display; Off restored normal use.
  Eight screenshots of both Settings pages (en and zh-Hans, light and dark) are on the Mac under
  `experiments/ipad-workspace/shots/`.

## Written, not proven

- **iPad workspace display mode** (`InProcess.m`, `PKInProcess (LabDisplay)`) and Settings, Workspace
  Display. It compiles. With a display chosen, screenshots and touches go to that display only, the
  tree read, hardware buttons and launches are refused, and the main display cannot be chosen.
  Whether an app on a real external display can be read and tapped this way is not yet known.
- **The iPad simulator cannot show it.** Its external display powers on (XCTest sees 2 screens) but
  stays black. iPadOS gives an extended desktop only with a keyboard and pointer attached, which
  `simctl` cannot do. There is also no launch-onto-a-display call in XCTest, `simctl` or
  testmanagerd, so an app can only get there by Stage Manager, which you drag.
- **A display Poki creates itself.** On a real iPad this would be the CoreDevice display service a Mac
  allocates (seen on iPhone Nov 21: display 3, 1920x1088, black, no shell). Whether iPadOS gives such
  a display an extended desktop is unknown.

## Your condition about a normal second display

Workspace Display is Off at every launch and uses a display only after you pick it in Settings. Poki
draws nothing on any external display and does not change how iPadOS uses one, so connecting the
iPad to a normal monitor works as before.

## What needs you or a real iPad

1. The Mac's two local commits (4541ae1e link and display probes, d7a43e13 notes, on top of 7ea6d625)
   and evidence wait for your typed yes in the Mac session; a patch is at
   `~/Developer/poki-ipad-workspace.patch`. The branch on GitHub has two newer commits (these notes),
   so the Mac merges before it pushes; nobody force-pushes.
2. The on-device check in `README.md`: real iPad, Stage Manager, a display set to Extend, a keyboard
   and pointer. Drag an app to the display, run Check Displays, choose the display, then `look` and
   one `do` tap from the linked iPhone.
3. Whether this branch should ever leave experimental status. Until you say so it stays as is.

## Try it on simulators

See `README.md`, "Simulator demo". In short: run the relay locally with
`npx --prefix deploy/cf-relay wrangler dev --local --port 8787 --var TOKEN_SECRET:<32+ random characters>`,
build Poki Lab from `project-lab.yml`, set both simulators' relay to `http://localhost:8787`, add an
agent on the iPad and copy its address, paste it on the iPhone in Settings, iPad Workspace, tap Check
Link, and allow the iPhone when Poki on the iPad asks.
