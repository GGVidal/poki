# A virtual display Poki owns on iPad (issue #689, exploration)

The goal: Poki works on an iPad display that nobody looks at. The owner keeps the iPad's own
screen, Poki for iPad included, and a linked iPhone uses the iPad's apps through that display.
This is iPhone Mirroring in reverse: the iPhone sees the iPad's app library, and Poki gets a full
touch surface on the virtual display.

## What is known (Nov 21 to 23 2026, iOS and iPadOS 27.3, CoreDevice 699.2)

| Piece | Status | Source |
| --- | --- | --- |
| A display with no monitor | **Exists.** A Mac's CoreDevice asks a paired device for a "virtual external display" of a chosen size. It appears as display 3, `type: wireless`, name `Wireless`, solid black. | iPhone 17 Pro, Nov 21 (`poki-background-display`, LOG.md gate 2) |
| An app making a display by itself | **None found.** No public or developer call creates a display. testmanagerd's virtual-display entitlements serve screen recording. | testmanagerd strings, 27.3 |
| Extended desktop on that display | **Gated in SpringBoard.** Extended mode needs Stage Manager (Chamois) windowing, and the display must count as a wireless display that "Allow Wireless Displays" (`allowWirelessDisplaysForExtendedDisplayMode`) admits. It also needs all the required hardware: `extendedDisplayHardwareRequirementMask` = 3, meaning a hardware pointing device and a hardware keyboard are attached. Without them the display stays mirrored, and a mirrored scene goes invalid. | SpringBoard 27.3 strings and disassembly |
| Placing an app there | **Not by a developer service.** A display-targeted launch is refused (`com.apple.springboard.display-lookup`, held by nothing in the developer disk images). Inside Stage Manager the owner (or Poki driving Stage Manager's own window controls) moves a window to the display. | iPhone, Nov 21 |
| Input on that display | testmanagerd picks the HID sender per display (`_resolvedDisplayForID:`, per-display digitizer and keyboard). The Lab driver on `dev/ipad-workspace` already routes screenshots and touches to a chosen display id. | testmanagerd strings; Lab build |
| iPhone to iPad link | **Works in the simulator** through the owner's relay (OAuth consent on the iPad, look and do through it). | NOTES.md |
| iPad simulator | No extended desktop: the external display stays black with Stage Manager on (simctl has no hardware keyboard or pointer to attach). It cannot answer this question. | Nov 22 and 23 |

## Ways to give the iPad a display it can extend onto

1. **Mac-made virtual display plus Universal Control.** The Mac creates the virtual display through
   CoreDevice. Universal Control from the same Mac is a hardware pointer and keyboard as far as
   iPadOS is concerned, which could satisfy the hardware rule. No monitor is needed, but a Mac is.
2. **AirPlay to a receiver nobody watches.** With "Allow Wireless Displays" on, an AirPlay receiver
   is a wireless display for Stage Manager. The receiver could be an Apple TV with its HDMI unplugged,
   a Mac, or a small headless AirPlay receiver on the home network. A keyboard and pointer still have
   to be attached (a Magic Keyboard with trackpad does both).
3. **A cheap HDMI dummy plug** on a USB-C hub with a keyboard and pointer. Not virtual, but nothing to
   watch, and it is the one path Stage Manager supports for certain.

In each case Poki chooses that display in Workspace Display (Off by default), so a monitor the owner
connects for their own use is left alone.

## What only a real iPad can answer (in order)

1. With Stage Manager on, a Magic Keyboard (or keyboard plus mouse) attached and a wired display or
   dummy plug: does Poki Lab's Check Displays get a picture of the extended desktop, and do `look`
   and a `do` tap land there without touching the iPad's own screen? This is README.md's on-device
   check.
2. The same with the Mac's CoreDevice virtual display in place of the wired one (`bgdisplay
   start-display --mode external` from `poki-background-display`), with the keyboard attached, then
   with Universal Control in place of the keyboard.
3. The same with an AirPlay receiver and "Allow Wireless Displays".
4. Whether an app on the extended display keeps its scene while the owner uses another app on the
   iPad screen. (On iPhone, an external-screen scene was foreground-only, but that was not Stage
   Manager.)
5. From the linked iPhone: `ipad_look` and `ipad_do` against that display, and how many frames a
   second the relay carries (look returns a screenshot per call; a live view would stream frames).
