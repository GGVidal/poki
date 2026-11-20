#!/usr/bin/env python3
"""Check still outfit previews on a booted iPhone 17 Pro simulator with Debug Poki installed.

Requires Pillow and the Poki simulator helper (built from native/simulator.m).
Use a dedicated simulator: the flow clears its outfit selection.
"""

import argparse
import json
from pathlib import Path
import subprocess
from time import monotonic, sleep

from PIL import Image


BUNDLE = "nz.zheha.poki"
WIDTH, HEIGHT = 402, 874


def until(reason, read, matches=bool):
    deadline = monotonic() + 8
    while monotonic() < deadline:
        value = read()
        if matches(value):
            return value
        sleep(0.1)
    raise AssertionError(reason)


def simctl(device, *args, check=True):
    subprocess.run(["xcrun", "simctl", args[0], device, *args[1:]],
                   check=check, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)


def pixels(image, box):
    data = iter(image.crop(box).tobytes())
    return zip(data, data, data)


def exercise(device, helper, output, strain):
    def element(identifier):
        raw = subprocess.check_output([helper], input=json.dumps({"id": device, "op": "ax"}),
                                      text=True, timeout=15)
        screen = json.loads(raw)
        if screen.get("bundle_id") != BUNDLE:
            return None
        # AX reports the set sheet's controls as offscreen after its entrance animation.
        return next((e for e in screen["elements"] if e.get("identifier") == identifier
                     and e["width"] > 1 and 0 <= e["y"] < HEIGHT), None)

    def control(identifier):
        return until(f"Missing {identifier}", lambda: element(identifier))

    def selected(identifier):
        until(f"{identifier} was not selected", lambda: element(identifier),
              lambda e: e and e["selected"])

    def tap(identifier, fraction=0.5):
        e = control(identifier)
        point = {"x": (e["x"] + e["width"] * fraction) / WIDTH, "y": (e["y"] + e["height"] / 2) / HEIGHT}
        def touch(phase):
            return {"messageType": "IndigoDigitizerEvent", "payload": {
                "pointOne": point, "eventType": phase, "edge": 0, "target": 0}}
        session.stdin.write(json.dumps({"events": [touch(0), {"delay_ms": 65}, touch(2)]}) + "\n")
        session.stdin.flush()
        assert json.loads(session.stdout.readline())["sent"]

    def preview(name):
        path = output / f"{name}.png"
        simctl(device, "io", "screenshot", str(path))
        with Image.open(path) as image:
            return image.convert("RGB").resize((WIDTH, HEIGHT), Image.Resampling.BOX)

    def gold(image):
        return sum(r > 120 and r > 1.08 * g and g > 1.24 * b
                   for r, g, b in pixels(image, (163, 145, 239, 208)))

    def cardigan(image):
        return sum(b > 1.3 * r and b > 1.1 * g and r < 95
                   for r, g, b in pixels(image, (141, 282, 261, 328)))

    simctl(device, "launch", BUNDLE, "-pokiChat", "working", "-uiLanguage", "en",
           "-AppleLanguages", "(en)", "-pokiStrain", strain)
    with subprocess.Popen([helper, "--hid-session", device], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          text=True) as session:
        assert json.loads(session.stdout.readline())["ready"]
        tap("chat.header.outfits")
        tap("wardrobe.set.0")
        selected("wardrobe.set.0")
        tap("wardrobe.mix")
        selected("wardrobe.headwear.0")
        bare = preview("bare")
        tap("wardrobe.headwear.7")
        selected("wardrobe.headwear.7")
        crown = until("Crown is selected but missing from the preview", lambda: preview("crown"),
                      lambda image: gold(image) > gold(bare) + 50)
        tap("wardrobe.pieces", 0.75)
        tap("wardrobe.clothes.4")
        selected("wardrobe.clothes.4")
        until("Mixed preview does not show both the crown and the cardigan", lambda: preview("mixed"),
              lambda image: gold(image) > gold(bare) + 50 and cardigan(image) > cardigan(crown) + 50)
        tap("wardrobe.removeAll")
        selected("wardrobe.clothes.0")
        until("The preview still shows an outfit after Remove All", lambda: preview("removed"),
              lambda image: gold(image) <= gold(bare) + 10 and cardigan(image) <= cardigan(crown) + 10)
    print(f"PASS ({strain}): the still preview shows the crown, the mix, and the bare bear after Remove All.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="dedicated, booted simulator UDID")
    parser.add_argument("helper", type=Path, help="path to the Poki simulator executable")
    parser.add_argument("output", type=Path, help="directory for screenshots")
    parser.add_argument("--strain", choices=("lowPower", "hot"), default="lowPower")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    simctl(args.device, "terminate", BUNDLE, check=False)
    try:
        exercise(args.device, args.helper.resolve(), args.output, args.strain)
    finally:
        simctl(args.device, "terminate", BUNDLE, check=False)
