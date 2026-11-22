"""R6 probe: can the accessibility audit service read and press a background app?

Usage (venv from README):  .build/venv/bin/python ax-probe.py <udid> <pid> [press-label]

Steps, each printed with an ET timestamp:
  1. deviceRunningApplications: what the service lists.
  2. deviceSetAuditTargetPid:<pid>, with on-screen inspector visuals off.
  3. Walk the inspector focus (max 60 elements) and print each element's caption.
  4. If press-label is given, press the first element whose caption equals it.
  5. Walk again and print captions, so a value change can be compared.
"""
import asyncio
import datetime
import sys
from zoneinfo import ZoneInfo

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.accessibilityaudit import AccessibilityAudit

ET = ZoneInfo("America/New_York")


def say(*a):
    print(datetime.datetime.now(ET).strftime("%H:%M:%S.%f")[:-3], *a, flush=True)


async def walk(audit, limit=60):
    seen = []
    try:
        async for focus in audit.iter_elements():
            caption = focus.caption
            seen.append((caption, focus.element))
            if len(seen) >= limit:
                break
    except TimeoutError as e:
        say("walk timeout:", e)
    return seen


async def main(udid, pid, press):
    lockdown = await create_using_usbmux(serial=udid)
    async with AccessibilityAudit(lockdown) as audit:
        apps = await audit._invoke("deviceRunningApplications")
        say("deviceRunningApplications:", apps)
        await audit.set_show_visuals(False)
        reply = await audit._invoke("deviceSetAuditTargetPid:", pid)
        say("deviceSetAuditTargetPid reply:", reply)
        before = await walk(audit)
        say(f"walk 1: {len(before)} elements:", [c for c, _ in before])
        if press:
            match = next((e for c, e in before if c == press), None)
            if match is None:
                say(f"no element captioned {press!r}; nothing pressed")
            else:
                await audit.perform_press(match.identifier)
                say(f"pressed {press!r}")
                await asyncio.sleep(1.0)
                after = await walk(audit)
                say(f"walk 2: {len(after)} elements:", [c for c, _ in after])


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1], int(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else None))
