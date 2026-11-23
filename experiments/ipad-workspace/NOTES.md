# iPad workspace: morning status, Nov 23 2026, 7 am ET

Experimental (issue #689). Poki Lab build only (`native/ios-app/project-lab.yml`, bundle id
`nz.zheha.poki.lab`). Nothing here reaches alpha, beta, pre-alpha or a release, and there is no pull
request into `main`.

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
