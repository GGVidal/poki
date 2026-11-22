# Background display experiment (issue #656)

A host-side prototype on the Mac. It asks a stock, paired iPhone for a virtual external
display over CoreDevice, inspects it, and sends touches aimed at it. It never modifies,
re-signs, reinstalls or instruments a target app. Results, verbatim errors and session ids
are in [LOG.md](LOG.md); records are in [records/](records).

## Status (2026-11-21, iPhone18,1 iOS 27.3 24C5037i, Xcode 27.3, CoreDevice 699.2)

| Gate | Result |
| - | - |
| Capability | Phone advertises 972 ("Virtual external video output stream"); Mac client 140. The phone accepts the request anyway. |
| Display allocation | **Observed.** A new display appears for the life of the session: `type: wireless`, name `Wireless`, requested size (1920x1088 or 1280x800), own `uniqueId`. It is solid black and **not** a mirror of the handset. |
| Host video | The phone streams, but avconferenced refuses the Mac-side decoder for an ad-hoc binary (`vcMediaStreamSetSessionConfig failed authorization check ... entitlementStatus=2`). `devicectl device capture screenshot --display-unique-id` is used instead. |
| App placement | **Refused.** `devicectl device process launch --display <any id>` -> SpringBoard: `Can't look up displays without the proper entitlement, bub.` The entitlement next to that string is `com.apple.springboard.display-lookup`. No DDI daemon holds it. A normal launch goes to the handset. |
| Shell / Extended mode | Display 3 has no shell (swipes and taps change nothing). Settings shows no Extended Display option on this iPhone. |
| App content | Photos shows its own external-screen scene (the video alone) on display 3, **only while Photos is in front** on the handset. Black within 2 s of switching to Settings. |
| Input | CoreDevice digitizer targets raw 0/1 = handset. Raw 2/3 never reach the handset (controlled test). Their effect on display 3 is unproven, because no interactive scene can be put there. |
| Headless route | `--no-activate` launch leaves the handset foreground alone. The accessibility audit service reads only the foreground app (background Calculator: 0 elements; foreground: 23), and its press had no effect. |
| Concurrent use | Not reached. |

**Conclusion: partial, last passed gate 2 (display allocation).** On stock iOS 27.3 on an
iPhone 17 Pro, an ordinary app cannot be placed on or kept running on the virtual display.
The scene placement path needs `com.apple.springboard.display-lookup`, which no developer
service has, and external-screen scenes are foreground-only.

Next experiments most likely to change this: an XCTest probe in Poki's in-process session
for a background pid's tree (needs a phone build, owner's go); the same tests on an iPad or
iPhone Duo with Stage Manager (classified separately, not the phone result).

## Build

```bash
./build.sh            # swiftc against /Library/Developer/PrivateFrameworks; no entitlements, ad-hoc
./check-symbols.sh    # every private symbol the binary imports is still exported (fails on drift)
```

Private bindings live only in `Stubs/` (hand-written interfaces matched to the installed
exports). A wrong declaration is a link error, and `check-symbols.sh` re-checks after an
Xcode update.

## Reproduce

Identifier namespaces are kept apart: `--udid` is the devicectl UDID, `--device` the
CoreDevice identifier (`devicectl device info details` -> Identifier), display `uniqueId`
and numeric `displayId` come from `devicectl device info displays`, and the digitizer
target is a raw `DigitizerTarget` value.

```bash
export BGDISPLAY_UDID=<phone UDID>
export BGDISPLAY_STATE="$TMPDIR/bgdisplay"      # control socket and state
.build/bgdisplay probe --device <CoreDevice id>               # support info, feature bits, target raw values
.build/bgdisplay start-display --device <CoreDevice id> --mode external --size 1280x800 --timeout 120 &
.build/bgdisplay displays                                      # the new display: displayId, uniqueId, size
.build/bgdisplay capture out.png                               # screenshot of the virtual display
.build/bgdisplay launch-on-display com.apple.calculator        # reproduces the SpringBoard refusal
.build/bgdisplay act tap 0.38 0.66 --target display2           # normalized point, digitizer target
.build/bgdisplay act swipe 0.5 0.995 0.5 0.6 --target display2 --edge bottom
.build/bgdisplay status
.build/bgdisplay stop                                          # invalidate, stop our stream, release assertion
.build/bgdisplay server-status --device <CoreDevice id>        # phone-side sessions (should be 0 after stop)
```

`start-display` owns the stream and serves the control socket. Other commands talk to it.
`--mode secondary` maps to the same `VirtualExternalDisplay` request on 699.2.

## Cleanup behaviour

`stop`, SIGINT and SIGTERM call `invalidate()` on our own stream (CoreDevice sends
`MediaStreamStop` for it), then release our usage assertion. No global stop-all is used.
After every run in LOG.md, `server-status` showed `running=false sessions=0` and the
virtual display was gone from `devicectl device info displays`.

## Compatibility record

- Mac15,6 (M3 Pro), macOS 27.0 (26A428), Xcode 27.3 (27C5035i), devicectl/CoreDevice 699.2, AVConference 2235.63.5.2.
- iPhone 17 Pro (iPhone18,1), iOS 27.3 (24C5037i), Developer Mode on, paired, CoreDevice tunnel over TCP (reported as localNetwork, later wired). DDI 27C5035i cryptex.
- Target: Calculator `com.apple.calculator` 12.0 (225), installed system app. Diagnostic: Photos `com.apple.mobileslideshow`. Helpers on the phone: none installed. The only XCTest runner present is Poki 0.4.7 (71), unused. Host helper: pymobiledevice3 11.61.2 in a temporary venv (`ax-probe.py`), deleted after the run.
- Simulator: CoreDevice's default `DeviceManager` lists no simulators to this client. The iOS Simulator has no Calculator (`--display` launch -> OSStatus -10814). Simulator results do not count toward the phone result.
